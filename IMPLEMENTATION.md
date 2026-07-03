# Test Wallet — implementation guide

A **minimal** Flutter app whose only job is to prove that the two published
packages work together, end to end, on a real device:

- **[`attested_secure_keys`](https://pub.dev/packages/attested_secure_keys)** — the holder key: a non-exportable EC P-256 key in secure hardware (StrongBox/TEE/Secure Enclave), ES256 signing, and a hardware-attestation proof.
- **[`sdjwt_oid4vc`](https://pub.dev/packages/sdjwt_oid4vc)** — the protocol: SD-JWT VC + OpenID4VCI (issuance) + OpenID4VP (presentation), holder role, pure Dart.

This is a **showcase, not a wallet.** No account system, no encrypted vault, no
multi-credential management, no polish. Happy path only. If the flows below run
green on a device, the libraries are proven.

---

## 1. What we're proving (success criteria)

- [ ] Generate a hardware-backed holder key and read its public JWK.
- [ ] Wrap that key as an `Es256Signer` (one small adapter class — the only glue).
- [ ] **Issue:** redeem a credential offer (OpenID4VCI pre-auth + `tx_code`) → hold an SD-JWT VC signed with a proof of possession from the hardware key.
- [ ] **Inspect:** decode + display the credential's claims.
- [ ] **Trust:** verify the issuer signature (+ optional cert-chain trust) and validity window.
- [ ] **Status:** resolve the credential's Token Status List entry (valid/revoked/suspended).
- [ ] **Present:** answer a verifier's OpenID4VP request — authenticate the verifier, disclose only the requested claims, sign a KB-JWT with the hardware key, submit.

Everything except key generation/signing is a call into `sdjwt_oid4vc`.

---

## 2. The two libraries and their roles

| Concern | Package | You call |
|---|---|---|
| Hardware key gen | `attested_secure_keys` | `AttestedSecureKeys().generateKey(...)` |
| ES256 signature (raw R‖S) | `attested_secure_keys` | `keys.sign(alias:, payload:)` |
| Key attestation (proof of HW origin) | `attested_secure_keys` | `keys.attest(alias:, serverNonce:)` |
| Everything protocol (issue/present/verify/status) | `sdjwt_oid4vc` | `Oid4vciClient`, `Oid4vpClient`, `SdJwt`, `IssuerTrust`, `StatusListResolver` |

**The seam:** `sdjwt_oid4vc` never imports a key backend. It takes an
`Es256Signer` (interface) and an `Oid4vcHttp` (interface, defaults to
`DefaultOid4vcHttp` over `package:http`). We provide one adapter that turns a
hardware key into an `Es256Signer`. That adapter is the entire integration.

---

## 3. Architecture

```
┌──────────────────────── Flutter app (this repo) ────────────────────────┐
│  UI: 3 screens (Home / Import / Present)                                 │
│                                                                          │
│  AttestedKeysSigner  implements  Es256Signer   ◄── the ONLY glue class   │
│        │  publicJwk()  signEs256()  attest()                             │
│        ▼                                                                 │
│  attested_secure_keys            sdjwt_oid4vc                            │
│  (HwKey, sign, attest)  ──────►  Oid4vciClient / Oid4vpClient / SdJwt    │
│                                  IssuerTrust / StatusListResolver        │
│                                  DefaultOid4vcHttp ──► issuer / verifier │
└──────────────────────────────────────────────────────────────────────────┘
```

`sdjwt_oid4vc` does all the JOSE/SD-JWT/DCQL/KB-JWT work in pure Dart. The app
supplies (a) the key, via the adapter, and (b) network, via the default HTTP
client (or a mock — see §8).

---

## 4. Dependencies

`pubspec.yaml`:

```yaml
environment:
  sdk: ">=3.4.0 <4.0.0"
  flutter: ">=3.22.0"

dependencies:
  flutter:
    sdk: flutter
  sdjwt_oid4vc: ^0.1.0-dev.2       # protocol (holder)
  attested_secure_keys: ^0.1.0-dev.1  # hardware key + attestation
  mobile_scanner: ^5.0.0           # QR scan for offers / VP requests (optional)

dev_dependencies:
  flutter_lints: ^4.0.0
```

> `attested_secure_keys` is a **platform plugin** (Android/iOS). It won't do real
> hardware keys on desktop/web — run the demo on an Android device/emulator or an
> iOS device. See §10.

---

## 5. The glue — `AttestedKeysSigner`

This is the whole integration. It adapts one hardware key (an `HwKey`) to
`sdjwt_oid4vc`'s `Es256Signer`. Note the deliberate details:

- both packages export a type named `KeyAttestation`, so alias one import;
- `HwKey.publicJwk` is a `Jwk` object → `.toJson()` to the `Map` the interface wants;
- `keys.sign` takes **bytes** and returns `Es256Signature.jose` (raw R‖S base64url) — exactly the JOSE ES256 shape the library expects;
- `attest` is **optional**: return `null` and the library simply doesn't attach a key attestation (the OpenID4VCI proof still binds the key via `cnf`).

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:attested_secure_keys/attested_secure_keys.dart' as ask;
import 'package:sdjwt_oid4vc/sdjwt_oid4vc.dart';

/// Adapts one hardware key (an [ask.HwKey]) to the library's [Es256Signer].
class AttestedKeysSigner implements Es256Signer {
  AttestedKeysSigner(this._keys, this._key, {this.promptTitle = 'Authorize'});

  final ask.AttestedSecureKeys _keys;
  final ask.HwKey _key;
  final String promptTitle;

  @override
  Future<Map<String, dynamic>> publicJwk() async =>
      _key.publicJwk.toJson().cast<String, dynamic>();

  @override
  Future<String> signEs256(String signingInput) async {
    final sig = await _keys.sign(
      alias: _key.alias,
      payload: Uint8List.fromList(utf8.encode(signingInput)),
      promptTitle: promptTitle, // fires biometric/PIN if the key is auth-gated
    );
    return sig.jose; // raw R‖S, base64url — JOSE ES256
  }

  @override
  Future<KeyAttestation?> attest(String nonce) async {
    final att = await _keys.attest(
      alias: _key.alias,
      serverNonce: Uint8List.fromList(utf8.encode(nonce)),
    );
    final format = switch (att.type) {
      ask.KeyAttestationType.androidKeyAttestation => 'android-key',
      ask.KeyAttestationType.appleAppAttest => 'apple-appattest',
      ask.KeyAttestationType.appleAppAssert => 'apple-appassert',
      ask.KeyAttestationType.none => null,
    };
    if (format == null) return null;
    // The library's KeyAttestation is a flat {format, data} pair; hand the
    // issuer the normalized attestation JSON (chain/CBOR/nonce) as `data`.
    return KeyAttestation(format: format, data: jsonEncode(att.toJson()));
  }
}
```

---

## 6. Flows mapped to library calls

### 6.1 One-time — generate the holder key

```dart
final keys = ask.AttestedSecureKeys();

final hwKey = await keys.generateKey(
  alias: 'wallet.holderKey',                 // in a real wallet: one per credential
  minSecurityLevel: ask.KeySecurityLevel.trustedEnvironment,
  userAuth: const ask.UserAuthPolicy.perUseBiometric(),
  // attestationChallenge: nonceFromIssuer,  // see §11 (Android binds it here)
);

final signer = AttestedKeysSigner(keys, hwKey);
```

### 6.2 Issuance (OpenID4VCI, pre-authorized_code)

```dart
final vci = Oid4vciClient(DefaultOid4vcHttp());

// offerLink is an `openid-credential-offer://...` deep link or the offer JSON
// (scan a QR into `offerLink`, prompt the user for `txCode`).
final compactSdJwt = await vci.redeemOffer(
  offerUriOrJson: offerLink,
  txCode: txCode,
  signer: signer,   // proof-of-possession is signed by the hardware key
);
// Store `compactSdJwt` (a String). In-memory is fine for the demo.
```

### 6.3 Import — inspect, trust, status

```dart
final vc = SdJwt.parse(compactSdJwt);

// Display
final claims = vc.resolveClaims();

// Trust the issuer. Simplest: signature only. Stronger: full chain to anchors.
final trusted = await vc.verifyIssuer(
  IssuerTrust.signatureOnly(),
  // IssuerTrust.x5cChain(trustAnchors: bundledLotlAnchorsDerB64),  // EUDI trust
  enforceValidity: true,   // also checks exp / nbf
);

// Revocation
final status = vc.statusListRef == null
    ? null
    : await StatusListResolver(DefaultOid4vcHttp()).resolve(vc.statusListRef!);
final isRevoked = status != null && !status.isValid;
```

### 6.4 Presentation (OpenID4VP + DCQL + KB-JWT)

```dart
final vp = Oid4vpClient(DefaultOid4vcHttp());

// requestRef is a request_uri / JAR (scan the verifier's QR).
final req = await vp.fetchRequest(requestRef);

// Authenticate the verifier (RP). The library confirms signature integrity;
// the APP owns the trust decision (chain to a reader anchor, SAN vs client_id).
final rpOk = req.signature != null && await req.signature!.verifyWithX5cLeaf();

// Pick the held credential + claims the request asks for.
final match = vp.match(req, [vc]);
if (match == null) { /* nothing satisfies the request */ }

// Build the vp_token: disclose only requested claims + KB-JWT (hardware-signed).
final vpToken = await vp.buildVpToken(
  credential: vc,
  revealClaims: match!.requestedClaims,   // or use present(disclosePaths:) for nested
  req: req,
  signer: signer,
);

await vp.submit(req: req, vpToken: vpToken);
```

---

## 7. Minimal UI (3 screens)

1. **Home** — "Generate key" button (shows `effectiveLevel` + `hasHardwareAttestation`); list of held credentials (claims preview + trust/status badges).
2. **Import** — paste/scan an offer link, enter `tx_code`, "Redeem" → §6.2/§6.3.
3. **Present** — paste/scan a VP request, show requested claims + RP identity, "Approve & send" → §6.4.

No navigation framework needed — three `StatefulWidget`s and a bit of state.

---

## 8. Running it — two modes

**Mode A — self-contained (recommended first).** Real hardware key, but a
**mock `Oid4vcHttp`** that returns canned issuer/verifier responses, so the whole
loop runs on a device with no backend. Use the library's own worked example as
the template for the mock issuer/verifier (it plays both roles in-process with a
`SoftwareEs256Signer` as the *issuer* key and a fake HTTP directory):
`sdjwt_oid4vc/example/sdjwt_oid4vc_example.dart`. Swap that example's software
*holder* signer for our `AttestedKeysSigner`. This proves the full wiring,
including the hardware key, with zero external dependencies.

**Mode B — live.** Replace the mock with `DefaultOid4vcHttp()` and point at a
real issuer/verifier. This is the actual wire-format validation (freezes the API
for `sdjwt_oid4vc` 0.1.0). Capture the real offer, DCQL request, issuer `x5c`,
and status list as fixtures.

---

## 9. EUDI standard alignment

| EUDI / spec element | Where it's handled |
|---|---|
| SD-JWT VC (`dc+sd-jwt`), disclosures, `_sd`/`_sd_alg` | `sdjwt_oid4vc` codec (`SdJwt`, `Disclosure`) |
| OpenID4VCI pre-authorized_code + `tx_code` | `Oid4vciClient.redeemOffer` |
| Proof of possession (`openid4vci-proof+jwt`, `cnf`) | `Oid4vciClient` + hardware `signer` |
| Key attestation (Android Keystore / Apple App Attest) | `attested_secure_keys` → `signer.attest` |
| OpenID4VP + DCQL query | `Oid4vpClient.fetchRequest` / `match` |
| Verifier (RP) request authentication (JAR / `x5c`) | `req.signature.verifyWithX5cLeaf()` (+ app trust policy) |
| Key Binding JWT (`kb+jwt`, `sd_hash`) | `Oid4vpClient.buildVpToken` |
| Token Status List (revocation) | `StatusListResolver.resolve` |
| Issuer trust via EU LOTL / Trusted List | `IssuerTrust.x5cChain(trustAnchors:)` — **anchors are app-provided** (bundle a small set for the demo) |

**Deliberately app-side (out of the library, per its scope):** the Trusted List
*data* (LOTL fetch/parse) and the Relying-Party trust *policy*. For the demo,
bundle a couple of test anchor certs (base64 DER) rather than wiring the real
LOTL.

---

## 10. Platform setup

**Android** (primary target):
- `minSdkVersion 24` (StrongBox needs 28+; the library falls back TEE→software with an honest `effectiveLevel`).
- Real Keystore X.509 attestation works on device and most emulators.

**iOS:**
- Secure Enclave needs a real device (not simulator) for hardware keys.
- App Attest attests the app instance and binds the SE key via the nonce.

**Desktop/web:** not supported by `attested_secure_keys` — the demo is a mobile
app. (For pure-protocol testing without hardware, `sdjwt_oid4vc` ships
`SoftwareEs256Signer` in `package:sdjwt_oid4vc/testing.dart`, but that bypasses
the point of this demo.)

---

## 11. Nuances / gotchas (read before coding)

- **`KeyAttestation` name clash** — both packages export it; alias one import (done in §5).
- **`HwKey.publicJwk` is a `Jwk`, not a `Map`** — call `.toJson()`.
- **`keys.sign` takes bytes** — `utf8.encode(signingInput)`; it returns `.jose` (raw R‖S base64url), which is exactly what `Es256Signer.signEs256` must return.
- **Android binds the attestation challenge at `generateKey`, not `attest`.** If the issuer requires a *fresh* key attestation bound to its `c_nonce`, generate the key with `attestationChallenge: <issuer nonce>` at enrollment. For the demo, attestation is optional — returning it or `null` both work; the proof-of-possession already binds the key via `cnf`. (iOS binds the nonce at `attest` time.)
- **Auth-gated keys prompt on every `sign`** — the `promptTitle` in the adapter surfaces the biometric/PIN dialog. Expect a prompt at each issuance proof and each presentation KB-JWT.
- **HTTPS enforced** — `sdjwt_oid4vc` refuses non-`https` URLs except loopback. A local mock/test issuer must use `https` or `localhost`/`127.0.0.1`.

---

## 12. Out of scope (don't build these)

Encrypted credential storage, multi-credential UX, credential deletion/refresh,
deferred issuance, PID, mdoc/ISO-18013, real LOTL fetch/parse, background status
polling, deep-link registration polish.

---

## 13. Next steps (pick up from here)

1. `flutter create` the app in this folder; add the deps from §4.
2. Drop in `AttestedKeysSigner` (§5) verbatim.
3. Build **Mode A** (§8) first — reuse the library example as the mock counterpart, with our hardware signer as the holder. Get all of §1 green.
4. Switch to **Mode B** against the live issuer/verifier; reconcile any wire-format deltas and capture fixtures. This is the validation that unblocks `sdjwt_oid4vc` 0.1.0.
