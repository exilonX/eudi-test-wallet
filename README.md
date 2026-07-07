# eudi-test-wallet

A small, honest **reference EU Digital Identity (EUDI) wallet** — built to prove
that two independent Dart/Flutter libraries compose into a working wallet:

| Layer | Package | Role |
| --- | --- | --- |
| Keys | [`attested_secure_keys`](https://pub.dev/packages/attested_secure_keys) | Non-exportable hardware EC P-256 key + attestation (Android/iOS) |
| Protocol | [`sdjwt_oid4vc`](https://pub.dev/packages/sdjwt_oid4vc) | SD-JWT VC + OpenID4VCI / OpenID4VP holder flow |

The **entire integration is one 72-line adaptor** — [`lib/attested_keys_signer.dart`](lib/attested_keys_signer.dart) —
that implements `sdjwt_oid4vc`'s `Es256Signer` interface using the hardware key
from `attested_secure_keys`. Everything else is a thin Material UI over a single
`WalletController`.

> This is a **reference / demo build, not a production wallet**: no credential
> storage, no account system, no production key lifecycle, no real trust-list
> management. Its job is to show the two libraries' seams line up, end to end.

## What it does

Three screens over a bottom-nav shell:

- **Home** — pick a backend, generate the hardware holder key, watch the §1
  acceptance checklist go green, and see the held credential.
- **Import** — redeem a credential offer (`openid-credential-offer://`, paste or
  scan a QR) with a `tx_code`, then inspect the claims, verify the issuer, and
  resolve the Token Status List.
- **Present** — load a verifier's OpenID4VP request, authenticate the RP, match
  against the held credential (DCQL), and disclose **only** the requested claims
  with a hardware-signed Key-Binding JWT.

### Two backends

| Mode | Backend | Notes |
| --- | --- | --- |
| **A · mock** | In-process `MockIssuerVerifier` | Fully offline self-test, no network |
| **B · live EUDI** | `issuer.eudiw.dev` + reference verifier | Real PID credential, `x5c` chain validated to the bundled EU PID Issuer CA root, encrypted `direct_post.jwt` response |

The holder clients take an injected HTTP client, so switching modes swaps one
object — the wallet code is identical.

## Run it

```bash
flutter pub get
flutter run                       # pick a device; Mode A works on an emulator

# On-device end-to-end proof through the REAL hardware-key plugin:
flutter test integration_test/mode_a_test.dart -d <device-id>
```

Mode A runs anywhere. Mode B needs network and a PID offer/request generated on
the EUDI reference issuer/verifier sites (scan their QR codes on Import/Present).

On an emulator without secure hardware, key generation falls back to the best
key available and the UI reports the assurance it actually got; hardware
attestation is simply omitted (the proof-of-possession still binds the key).

## Layout

```
lib/
  main.dart                  # app shell + bottom nav
  wallet_controller.dart     # single source of truth; owns key, backends, holder clients
  attested_keys_signer.dart  # ← the 72-line adaptor: HwKey → Es256Signer
  eudi_trust.dart            # bundled EU reference PID Issuer CA (dev trust anchor)
  mock_backend.dart          # in-process mock issuer + verifier (Mode A)
  screens/                   # home / import / present
  scan_screen.dart           # QR scanner (mobile_scanner)
  ui_helpers.dart            # small shared UI widgets
integration_test/
  mode_a_test.dart           # drives the real plugin through the whole flow
```

## License

Apache-2.0 — same as the two libraries it builds on. See [LICENSE](LICENSE).
