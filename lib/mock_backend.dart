import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:sdjwt_oid4vc/sdjwt_oid4vc.dart';
import 'package:sdjwt_oid4vc/testing.dart';

/// A self-contained, in-process issuer **and** verifier that satisfies the
/// entire `sdjwt_oid4vc` holder flow with no network — this is "Mode A"
/// (IMPLEMENTATION.md §8). It implements the library's [Oid4vcHttp] seam and
/// answers, by route, every HTTP call the holder clients make:
///
///   OpenID4VCI (issuance, driven by `Oid4vciClient.redeemOffer`):
///     GET  issuer.example/.well-known/openid-credential-issuer   → metadata
///     POST issuer.example/token         (pre-auth code + tx_code) → access token + c_nonce
///     POST issuer.example/credential    (holder PoP proof)        → the SD-JWT VC
///   Trust + status:
///     GET  issuer.example/.well-known/jwt-vc-issuer              → issuer JWK set
///     GET  issuer.example/status/1                               → signed status-list token
///   OpenID4VP (presentation, driven by `Oid4vpClient`):
///     GET  verifier.example/request                              → signed request object (JAR)
///     POST verifier.example/response    (vp_token)               → { redirect_uri }
///
/// The issuer and verifier each own a software EC P-256 key ([SoftwareEs256Signer]).
/// The HOLDER key is the real hardware key, injected as the signer at redeem /
/// present time — so the hardware path is exercised for the PoP proof and the
/// KB-JWT while everything else runs canned in memory.
class MockIssuerVerifier implements Oid4vcHttp {
  MockIssuerVerifier._(this._issuer, this._verifier, this._statusListToken);

  /// Builds the mock and pre-signs its status-list token.
  static Future<MockIssuerVerifier> create() async {
    final issuer = SoftwareEs256Signer.generate();
    final verifier = SoftwareEs256Signer.generate();
    final statusToken = await _buildStatusListToken(issuer);
    return MockIssuerVerifier._(issuer, verifier, statusToken);
  }

  final SoftwareEs256Signer _issuer;
  final SoftwareEs256Signer _verifier;
  final String _statusListToken;

  // --- Fixed identities / demo constants ------------------------------------
  static const issuerId = 'https://issuer.example';
  static const verifierId = 'https://verifier.example';
  static const vct = 'https://issuer.example/extras-salariat/v1';
  static const configId = 'extras-salariat-v1';
  static const statusUri = 'https://issuer.example/status/1';
  static const issuerKid = 'issuer-1';

  /// The pre-authorized code and transaction code baked into the demo offer.
  /// A real wallet reads the code from the offer and the user types `txCode`.
  static const preAuthCode = 'demo-preauthorized-code';
  static const txCode = '123456';

  /// Requested by the demo verifier (only this claim is disclosed on present).
  static const requestedClaim = 'employment_status';

  /// The verifier's public key, so the holder app can authenticate the signed
  /// request object with [RequestObjectSignature.verifyWithJwk]. In a real flow
  /// this key would arrive via the JAR's `x5c` chain and be trust-anchored;
  /// here the app trusts it because the mock is the RP.
  Map<String, dynamic> get verifierPublicJwk => _verifier.publicJwkSync();

  // --- Things the UI hands to the holder clients ----------------------------

  /// An `openid-credential-offer://` deep link (pre-authorized_code + tx_code),
  /// exactly what a wallet would scan. Redeem it with `Oid4vciClient.redeemOffer`.
  String buildOfferLink() {
    final offer = jsonEncode({
      'credential_issuer': issuerId,
      'credential_configuration_ids': [configId],
      'grants': {
        'urn:ietf:params:oauth:grant-type:pre-authorized_code': {
          'pre-authorized_code': preAuthCode,
          'tx_code': {
            'length': txCode.length,
            'input_mode': 'numeric',
            'description': 'Enter the demo transaction code',
          },
        },
      },
    });
    return 'openid-credential-offer://?credential_offer='
        '${Uri.encodeQueryComponent(offer)}';
  }

  /// An OpenID4VP request deep link pointing at the verifier's `request_uri`.
  /// Fetch + parse it with `Oid4vpClient.fetchRequest`.
  String buildPresentationRequestLink() =>
      'openid4vp://authorize?request_uri='
      '${Uri.encodeQueryComponent('$verifierId/request')}';

  // --- Oid4vcHttp implementation --------------------------------------------

  @override
  Future<HttpResp> get(Uri url, {Map<String, String>? headers}) async {
    switch ((url.host, url.path)) {
      case (_, '/.well-known/openid-credential-issuer'):
        return _json({
          'credential_issuer': issuerId,
          'token_endpoint': '$issuerId/token',
          'credential_endpoint': '$issuerId/credential',
          'nonce_endpoint': '$issuerId/nonce',
          'credential_configurations_supported': {
            configId: {'vct': vct, 'format': 'dc+sd-jwt'},
          },
        });

      case (_, '/.well-known/jwt-vc-issuer'):
        // Both the credential and the status-list token are sealed by the
        // issuer key, so this one JWK set verifies both.
        return _json({
          'issuer': issuerId,
          'jwks': {
            'keys': [
              {..._issuer.publicJwkSync(), 'kid': issuerKid},
            ],
          },
        });

      case (_, '/status/1'):
        return HttpResp(200, _statusListToken);

      case (_, '/request'):
        return HttpResp(200, await _buildRequestObject());

      default:
        return HttpResp(404, 'no route for GET $url');
    }
  }

  @override
  Future<HttpResp> postForm(
    Uri url,
    Map<String, String> form, {
    Map<String, String>? headers,
  }) async {
    switch ((url.host, url.path)) {
      case (_, '/token'):
        if (form['pre-authorized_code'] != preAuthCode) {
          return _error(400, 'invalid_grant', 'unknown pre-authorized_code');
        }
        if (form['tx_code'] != txCode) {
          return _error(400, 'invalid_grant', 'wrong tx_code');
        }
        return _json({
          'access_token': 'demo-access-token',
          'token_type': 'Bearer',
          'c_nonce': 'demo-c-nonce-${DateTime.now().microsecondsSinceEpoch}',
          'expires_in': 3600,
        });

      case (_, '/nonce'):
        return _json({'c_nonce': 'demo-c-nonce-nonce-endpoint'});

      case (_, '/response'):
        // The verifier received the vp_token. Happy path: acknowledge.
        return _json({'redirect_uri': '$verifierId/success'});

      default:
        return _error(404, 'not_found', 'no route for POST(form) $url');
    }
  }

  @override
  Future<HttpResp> postJson(
    Uri url,
    Object body, {
    Map<String, String>? headers,
  }) async {
    switch ((url.host, url.path)) {
      case (_, '/credential'):
        return _issueCredential(body);
      default:
        return _error(404, 'not_found', 'no route for POST(json) $url');
    }
  }

  // --- Issuer internals -----------------------------------------------------

  /// Mints the SD-JWT VC, binding the credential to the holder's key. The
  /// holder public key is lifted from the proof-of-possession JWT's header
  /// (`header.jwk`), which was signed by the hardware key.
  Future<HttpResp> _issueCredential(Object body) async {
    final map = body as Map<String, dynamic>;
    final proofJwt = (map['proof'] as Map)['jwt'] as String;
    final holderJwk = _headerJwkOf(proofJwt);
    // NOTE (Mode A): a real issuer verifies the proof signature + c_nonce here.
    // The mock trusts the proof (happy path) and simply binds `cnf.jwk`.

    final compact = await SdJwt.issue(
      claims: {
        'iss': issuerId,
        'vct': vct,
        'cnf': {'jwk': holderJwk}, // binds the holder (hardware) key
        'iat': _epoch(DateTime.utc(2024)),
        'exp': _epoch(DateTime.utc(2099)),
        'given_name': 'Ada',
        'family_name': 'Lovelace',
        'employment_status': 'active',
        'status': {
          'status_list': {'uri': statusUri, 'idx': 0},
        },
      },
      header: const {'kid': issuerKid},
      selectivelyDisclosable: const {
        'given_name',
        'family_name',
        'employment_status',
      },
      signer: _issuer,
    );
    return _json({'credential': compact});
  }

  /// The signed status-list token where index 0 is "valid" (bit 0 = 0).
  static Future<String> _buildStatusListToken(SoftwareEs256Signer issuer) async {
    final lst = b64uEncode(const ZLibEncoder().encode([0x00]));
    final signingInput = Jws.signingInput(
      const {'alg': 'ES256', 'typ': 'statuslist+jwt'},
      {
        'iss': issuerId,
        'sub': statusUri,
        'status_list': {'bits': 1, 'lst': lst},
      },
    );
    return '$signingInput.${await issuer.signEs256(signingInput)}';
  }

  // --- Verifier internals ---------------------------------------------------

  /// The verifier's signed Request Object (JAR): asks for exactly one claim via
  /// a DCQL query, signed with the verifier key (typ `oauth-authz-req+jwt`).
  Future<String> _buildRequestObject() async {
    final signingInput = Jws.signingInput(
      const {'alg': 'ES256', 'typ': 'oauth-authz-req+jwt'},
      {
        'client_id': verifierId,
        'nonce': 'verifier-nonce-1',
        'response_uri': '$verifierId/response',
        'response_mode': 'direct_post',
        'dcql_query': {
          'credentials': [
            {
              'id': 'c1',
              'format': 'dc+sd-jwt',
              'meta': {
                'vct_values': [vct],
              },
              'claims': [
                {
                  'path': [requestedClaim],
                },
              ],
            },
          ],
        },
      },
    );
    return '$signingInput.${await _verifier.signEs256(signingInput)}';
  }

  // --- helpers --------------------------------------------------------------

  HttpResp _json(Map<String, dynamic> body) => HttpResp(200, jsonEncode(body));

  HttpResp _error(int status, String error, String description) => HttpResp(
        status,
        jsonEncode({'error': error, 'error_description': description}),
      );

  static int _epoch(DateTime dt) => dt.toUtc().millisecondsSinceEpoch ~/ 1000;

  /// Decodes the `jwk` from a compact JWT's protected header.
  Map<String, dynamic> _headerJwkOf(String compactJwt) {
    final headerB64 = compactJwt.split('.').first;
    final normalized = base64Url.normalize(headerB64);
    final header =
        jsonDecode(utf8.decode(base64Url.decode(normalized))) as Map;
    return (header['jwk'] as Map).cast<String, dynamic>();
  }
}
