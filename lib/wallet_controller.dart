import 'package:attested_secure_keys/attested_secure_keys.dart' as ask;
import 'package:flutter/foundation.dart';
import 'package:sdjwt_oid4vc/sdjwt_oid4vc.dart';

import 'attested_keys_signer.dart';
import 'eudi_trust.dart';
import 'mock_backend.dart';

/// Where each step of the run currently stands (drives the UI badges).
enum CriterionState { idle, running, pass, fail }

/// Which backend the holder clients talk to.
///  * [mockA] — the in-process [MockIssuerVerifier] (offline self-test).
///  * [liveEudi] — the live EUDI reference issuer/verifier over real HTTP.
enum WalletMode { mockA, liveEudi }

/// The single source of truth for the demo. Owns the hardware key facade, both
/// backends (mock + live), and the three `sdjwt_oid4vc` holder clients, and
/// drives the whole §1 checklist. Screens read its fields and call its methods.
class WalletController extends ChangeNotifier {
  final ask.AttestedSecureKeys _keys = const ask.AttestedSecureKeys();
  static const _alias = 'wallet.holderKey';

  late final MockIssuerVerifier mock; // Mode A backend
  final DefaultOid4vcHttp _live = DefaultOid4vcHttp(); // Mode B transport

  WalletMode mode = WalletMode.mockA;
  bool get isLive => mode == WalletMode.liveEudi;

  late Oid4vciClient _vci;
  late Oid4vpClient _vp;
  late StatusListResolver _status;
  bool _ready = false;
  bool get isReady => _ready;

  /// Builds the in-process backend and wires the holder clients to it.
  Future<void> init() async {
    mock = await MockIssuerVerifier.create();
    _wireClients();
    _ready = true;
    notifyListeners();
  }

  Oid4vcHttp get _http => isLive ? _live : mock;

  void _wireClients() {
    _vci = Oid4vciClient(_http);
    _vp = Oid4vpClient(_http);
    _status = StatusListResolver(_http);
  }

  /// Switches backend. Keeps the holder key; clears issued/presented state so
  /// the two modes never show each other's results.
  void setMode(WalletMode next) {
    if (next == mode) return;
    mode = next;
    _wireClients();
    credentialCompact = null;
    credential = null;
    claims = null;
    issuerTrusted = null;
    credentialStatus = null;
    importError = null;
    request = null;
    rpAuthentic = null;
    match = null;
    vpToken = null;
    submitRedirect = null;
    disclosed = null;
    presentError = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _live.close();
    super.dispose();
  }

  // --- Home: the hardware holder key ----------------------------------------
  AttestedKeysSigner? signer;
  ask.HwKey? get hwKey => signer?.key;
  String? keyError;
  bool keyBusy = false;

  // --- Import: issue → inspect → trust → status -----------------------------
  String? credentialCompact;
  SdJwtVc? credential;
  Map<String, dynamic>? claims;
  bool? issuerTrusted;
  CredentialStatus? credentialStatus;
  String? importError;
  bool importBusy = false;

  // --- Present: authenticate RP → match → sign KB-JWT → submit --------------
  PresentationRequest? request;
  bool? rpAuthentic;
  CredentialMatch? match;
  String? vpToken;
  String? submitRedirect;
  Map<String, dynamic>? disclosed;
  String? presentError;
  bool presentBusy = false;

  /// Issuer-trust policy per mode. Mode A's mock issuer signs with a bare key
  /// resolvable via issuer metadata; the live EUDI issuer has no jwt-vc-issuer
  /// metadata, so we validate the credential's x5c chain to the bundled IACA.
  IssuerTrust get _issuerTrust => isLive
      ? IssuerTrust.x5cChain(trustAnchors: eudiTrustAnchors)
      : IssuerTrust.issuerMetadata();

  // =========================================================================
  // §6.1 — generate the holder key, wrap it as an Es256Signer.
  // =========================================================================
  Future<void> generateKey() async {
    keyBusy = true;
    keyError = null;
    notifyListeners();
    try {
      // Best available assurance where the hardware allows it; fall back so the
      // demo still runs on an emulator. `effectiveLevel` reports what we got.
      await _keys.deleteKey(alias: _alias); // idempotent across hot-restarts
      final key = await _generateBestEffort();
      signer = AttestedKeysSigner(_keys, key);
    } on Object catch (e) {
      keyError = '$e';
    } finally {
      keyBusy = false;
      notifyListeners();
    }
  }

  Future<ask.HwKey> _generateBestEffort() async {
    try {
      return await _keys.generateKey(
        alias: _alias,
        minSecurityLevel: ask.KeySecurityLevel.trustedEnvironment,
        userAuth: const ask.UserAuthPolicy.perUseBiometric(),
      );
    } on ask.AttestedSecureKeysException {
      // The device can't provide a TEE-backed, auth-gated key right now — e.g.
      // an emulator with no secure hardware (HwKeyUnsupportedError) or with no
      // enrolled biometric (KeyOperationError). Fall back to the best key that
      // always succeeds; `effectiveLevel` reports what we actually got.
      return _keys.generateKey(alias: _alias);
    }
  }

  // =========================================================================
  // §6.2/§6.3 — redeem the offer, then inspect + trust + status.
  // =========================================================================
  Future<void> redeem(String offerLink, String txCode) async {
    if (signer == null) {
      importError = 'Generate the holder key first (Home tab).';
      notifyListeners();
      return;
    }
    importBusy = true;
    importError = null;
    credentialCompact = null;
    credential = null;
    claims = null;
    issuerTrusted = null;
    credentialStatus = null;
    notifyListeners();
    try {
      // §6.2 Issue: proof-of-possession is signed by the hardware key.
      credentialCompact = await _vci.redeemOffer(
        offerUriOrJson: offerLink,
        txCode: txCode,
        signer: signer!,
      );

      // §6.3 Inspect.
      final vc = SdJwt.parse(credentialCompact!);
      credential = vc;
      claims = vc.resolveClaims();

      // §6.3 Trust the issuer (signature + validity window).
      issuerTrusted = await vc.verifyIssuer(
        _issuerTrust,
        http: _http,
        enforceValidity: true,
      );

      // §6.3 Status (Token Status List). Mode A verifies the token's seal via
      // issuer metadata; for the live issuer we just read the status bit.
      final ref = vc.statusListRef;
      credentialStatus = ref == null
          ? null
          : await _status.resolve(
              ref,
              trust: isLive ? null : IssuerTrust.issuerMetadata(),
            );
    } on Object catch (e) {
      importError = '$e';
    } finally {
      importBusy = false;
      notifyListeners();
    }
  }

  bool get isRevoked =>
      credentialStatus != null && !credentialStatus!.isValid;

  // =========================================================================
  // §6.4 — presentation: authenticate the verifier, match, then present.
  // =========================================================================
  Future<void> loadPresentationRequest(String requestLink) async {
    if (credential == null) {
      presentError = 'Redeem a credential first (Import tab).';
      notifyListeners();
      return;
    }
    presentBusy = true;
    presentError = null;
    request = null;
    rpAuthentic = null;
    match = null;
    vpToken = null;
    submitRedirect = null;
    disclosed = null;
    notifyListeners();
    try {
      final req = await _vp.fetchRequest(requestLink);
      request = req;

      // Authenticate the RP. Mode A's JAR is signed with a bare verifier key
      // (verify with its JWK); the live EUDI verifier signs with an x5c chain
      // (verify against the leaf — trust/pinning of that cert is app policy).
      rpAuthentic = req.signature != null &&
          (isLive
              ? req.signature!.verifyWithX5cLeaf()
              : req.signature!.verifyWithJwk(mock.verifierPublicJwk));

      match = _vp.match(req, [credential!]);
    } on Object catch (e) {
      presentError = '$e';
    } finally {
      presentBusy = false;
      notifyListeners();
    }
  }

  Future<void> approveAndSend() async {
    if (request == null || match == null || signer == null) return;
    presentBusy = true;
    presentError = null;
    notifyListeners();
    try {
      // Build the 1.0-final vp_token ({queryId: [presentation]}) with the
      // requested claims/paths disclosed + a KB-JWT signed by the hardware key,
      // bound to the verifier's nonce/audience.
      final tokenMap = await _vp.buildVpTokenMap(
        matches: [match!],
        req: request!,
        signer: signer!,
      );
      // submitResponse honours response_mode: plain `direct_post` (Mode A mock)
      // or an encrypted `direct_post.jwt` JWE (the live EUDI verifier).
      submitRedirect = await _vp.submitResponse(req: request!, vpToken: tokenMap);
      // What the verifier now sees: only the disclosed claims.
      vpToken = tokenMap[match!.queryId]?.first;
      if (vpToken != null) disclosed = SdJwt.parse(vpToken!).resolveClaims();
    } on Object catch (e) {
      presentError = '$e';
    } finally {
      presentBusy = false;
      notifyListeners();
    }
  }

  // =========================================================================
  // §1 success-criteria checklist (rendered on Home).
  // =========================================================================
  List<(String, CriterionState)> get criteria => [
        ('Generate hardware key + read JWK', _flag(hwKey != null)),
        ('Wrap key as Es256Signer', _flag(signer != null)),
        ('Issue: redeem offer (VCI + tx_code + PoP)',
            _flag(credentialCompact != null)),
        ('Inspect: decode + display claims', _flag(claims != null)),
        ('Trust: verify issuer signature + validity', _tri(issuerTrusted)),
        ('Status: resolve Token Status List', _flag(credentialStatus != null)),
        ('Present: OpenID4VP + KB-JWT (hardware-signed)',
            _flag(submitRedirect != null || disclosed != null)),
      ];

  CriterionState _flag(bool done) =>
      done ? CriterionState.pass : CriterionState.idle;
  CriterionState _tri(bool? v) => v == null
      ? CriterionState.idle
      : (v ? CriterionState.pass : CriterionState.fail);
}
