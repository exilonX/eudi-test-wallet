# Test Wallet — live EUDI testing guide

How this test wallet was validated end-to-end against the **live EUDI reference**
(issuer + verifier), the configuration that makes it work, and a step-by-step so
anyone can reproduce a test on their own device.

The app exists to prove two published packages work together on real hardware:

- **[`attested_secure_keys`](https://pub.dev/packages/attested_secure_keys)** — a
  non-exportable EC P-256 holder key in secure hardware (TEE/StrongBox/Secure
  Enclave), ES256 signing, hardware attestation.
- **[`sdjwt_oid4vc`](https://pub.dev/packages/sdjwt_oid4vc)** `0.1.2` — SD-JWT VC +
  OpenID4VCI (issuance) + OpenID4VP (presentation), holder role, pure Dart.

---

## 1. What was tested (and passed) — live

Verified on a physical **Android device (Redmi Note 9 Pro, Android 11)** against the
public EUDI reference deployments, no signup:

| Step | Result |
|---|---|
| **Hardware holder key** | Real TEE key: `effectiveLevel = trustedEnvironment`, `hasHardwareAttestation = true`, biometric-gated (fingerprint prompt on every signature). |
| **Issuance — OpenID4VCI** | Redeemed a **pre-authorized_code** offer + `tx_code` from `issuer.eudiw.dev` → held a **real EUDI PID SD-JWT VC** (`vct: urn:eudi:pid:1`, `iss: https://backend.issuer.eudiw.dev`). The proof-of-possession was signed by the hardware key. |
| **Trust** | Issuer signature verified via `IssuerTrust.x5cChain` against a bundled EUDI dev IACA (`PID Issuer CA - UT 02`). Validity window enforced. |
| **Status** | Token Status List resolved over the network → valid. |
| **Presentation — OpenID4VP `direct_post.jwt`** | Answered a `verifier.eudiw.dev` request: authenticated the RP (`verifyWithX5cLeaf` on the `x509_hash` signed request), disclosed only the requested claims, signed a **KB-JWT with the hardware key**, and POSTed an **encrypted JWE response**. The verifier **accepted** it (HTTP 200) and displayed the received document. |
| **Selective disclosure incl. nested** | Disclosed `family_name`, `given_name`, and the **nested** `place_of_birth → locality` (Bucuresti); the sibling members (`region`, `country`) stayed hidden. |

This exercises the full EUDI holder loop — **hardware key → issuance → presentation
(encrypted)** — against the real EU reference services.

---

## 2. Prerequisites

- **Flutter** ≥ 3.22 (validated with Flutter 3.41 / Dart 3.11). `flutter doctor` green
  for Android.
- **An Android device or emulator:**
  - **Real device (recommended):** gives a true hardware key + attestation + biometric.
    Needs an **enrolled fingerprint/PIN** (the holder key is biometric-gated).
  - **Emulator:** works, but the key degrades to `software` and attestation to `none`
    (honest fallback) — fine for a functional test, not for hardware assurance.
  - iOS needs a real device + a Mac (not covered here).
- A **second screen** (a computer browser) to open the EUDI issuer/verifier web pages
  — you scan the QR codes they show with the phone.
- Network access to `*.eudiw.dev` (public, no credentials).

---

## 3. Configuration that makes it work

These are the non-obvious settings already applied in this repo (and *why*), so you can
reproduce them in any wallet:

**Dependencies** (`pubspec.yaml`)
```yaml
sdjwt_oid4vc: ^0.1.2        # incl. direct_post.jwt + nested-claim DCQL
attested_secure_keys: ^0.1.0
mobile_scanner: ^7.2.0      # QR scan of the EUDI offer / request codes
archive: ^4.0.0             # zlib for the Mode A mock status list
```

**Android** (required for the hardware key + biometric + camera)
- `android/app/build.gradle.kts` → `minSdk = 24` (`attested_secure_keys` needs API 24+).
- `MainActivity` extends **`FlutterFragmentActivity`** (not the default `FlutterActivity`)
  — required so the biometric prompt (`androidx.biometric`) can show when signing with a
  user-auth-gated key. Without this, `sign` throws *"Biometric-gated signing requires the
  host Activity to be a FlutterFragmentActivity."*
- `AndroidManifest.xml` → `<uses-permission android:name="android.permission.CAMERA"/>`
  (QR scanning).

**Holder key generation** (`lib/wallet_controller.dart`)
- Tries `minSecurityLevel: trustedEnvironment` + `perUseBiometric()`, and **falls back**
  to a plain software key if the device can't (emulator, or no enrolled biometric) — so
  the demo always runs; `effectiveLevel` reports what you actually got.

**EUDI trust (Mode B)** (`lib/eudi_trust.dart`)
- The EUDI issuer does **not** serve `/.well-known/jwt-vc-issuer`, so issuer verification
  uses **`IssuerTrust.x5cChain(trustAnchors:)`** against a **bundled** IACA root
  (`pidissuerca02_ut`, "PID Issuer CA - UT 02", base64 DER embedded). Source: the EUDI
  reference wallet repo `eudi-app-android-wallet-ui/.../res/raw/pidissuerca02_ut.pem`.
- The verifier signs its request with an `x5c` cert (`client_id` scheme `x509_hash`), so
  RP authentication uses **`verifyWithX5cLeaf()`**.
- The verifier uses **`response_mode: direct_post.jwt`** (an encrypted JWE response). The
  library's `Oid4vpClient.submitResponse` builds and POSTs that JWE automatically (ECDH-ES
  + A128GCM); see `sdjwt_oid4vc/docs/DIRECT_POST_JWT.md`.

**Two modes** (toggle on the Home screen)
- **Mode A · mock** — a fully in-process issuer + verifier (`lib/mock_backend.dart`).
  Offline, no backend; proves the wiring incl. the hardware key. Good for a quick check.
- **Mode B · EUDI** — points the same holder clients at the live EUDI services via
  `DefaultOid4vcHttp()`.

---

## 4. Run a live test — step by step

### 4.0 Launch the app
```bash
flutter pub get
flutter devices                 # find your device id
flutter run -d <device-id>      # e.g. flutter run -d a236a4e4
```
On **Home**: switch the backend toggle to **Mode B · EUDI**, then tap **Generate hardware
key** (approve the biometric enrolment prompt if asked). You should see
`effectiveLevel` and `hwAttestation`.

### 4.1 Issue a real EUDI PID

**On your computer:**
1. Open **`https://issuer.eudiw.dev/credential_offer`**.
2. Under **“sd-jwt vc format”**, tick **PID (SD-JWT VC)**.
3. Under **Grants**, choose **Pre-Authorization Code Grant**.
4. Leave *Credentials Offer URI* as its default (e.g. `haip-vci://` or
   `openid-credential-offer://`) and **Submit**.
5. The page shows a **QR code** and a **5-digit numeric PIN** (`tx_code`).

**In the app → Import tab:**
6. Tap **Scan QR** and scan the issuer's QR.
7. Type the **5-digit PIN** into the `tx_code` field.
8. Tap **Redeem** → approve the **biometric** prompt (this signs the PoP proof).
9. You should now hold the PID: **issuer signature valid**, **status: valid**, and the
   decoded claims (name, birthdate, nationality, place of birth, …).

### 4.2 Present to the EUDI verifier

**On your computer:**
1. Open **`https://verifier.eudiw.dev`** and start a new presentation request.
2. Select attestation **Person Identification Data (PID)**, format **`dc+sd-jwt`**,
   **Specific attributes**.
3. **Select Attributes** — pick claims your PID actually has, e.g. `family_name` +
   `given_name` (and, to test nesting, `place_of_birth → locality`). Avoid mdoc and any
   claim your credential doesn't carry, or the wallet will report "no match".
4. Presentation options: **HAIP** (or **OpenID4VP**), **Request URI Method: GET**,
   Authorization Endpoint e.g. `openid4vp://` (or `haip-vp://`). **Submit** → a **QR**.

**In the app → Present tab:**
5. Tap **Scan QR** and scan the verifier's QR, then **Load request**.
6. Confirm **RP request signature authentic** and the **Requested claims** shown.
7. Tap **Approve & send** → approve the **biometric** prompt (this signs the KB-JWT).
8. The app shows **Presented (what the verifier receives)** with the disclosed claims.

### 4.3 Confirm on the verifier side
Back on `verifier.eudiw.dev`, the **“Invoke Wallet”** result page shows the received
document (`urn:eudi:pid:1`, `dc+sd-jwt`) and, via **transaction log**, the actual
`vp_token` — the issuer SD-JWT + your disclosures + the hardware-signed KB-JWT.

---

## 5. How you know it worked

- App **Home → §1 success criteria**: all seven rows green.
- App **Import**: `issuer signature valid` + `status: valid` badges; real PID claims.
- App **Present**: `RP request signature authentic`, then `submitted → …` and the
  disclosed claims (only what was requested; the rest hidden).
- Verifier page: shows your document and the disclosed values.

---

## 6. Troubleshooting

| Symptom | Cause / fix |
|---|---|
| **"No held credential satisfies this request."** | The verifier request wasn't for **SD-JWT VC PID** (`urn:eudi:pid:1`), or asked for a claim you don't hold. On `verifier.eudiw.dev` pick **PID / `dc+sd-jwt`** and top-level claims like `family_name`,`given_name`. The Present screen prints a **diff** (`format · vct · claims` vs what you hold) to pinpoint it. |
| **`Biometric-gated signing requires … FlutterFragmentActivity`** | `MainActivity` must extend `FlutterFragmentActivity` (already set here). Real device also needs an **enrolled** fingerprint/PIN. |
| **Submit fails with HTTP 400 on `direct_post.jwt`** | Needs `sdjwt_oid4vc ≥ 0.1.1`. On `0.1.2` the failure message includes the verifier's response body. |
| **Gradle: `Could not read workspace metadata … transforms … metadata.bin`** | Corrupted Gradle cache. Fix: `cd android && ./gradlew --stop`, delete `~/.gradle/caches/<ver>/transforms`, then `flutter clean` and rebuild. |
| **`effectiveLevel = software`, attestation `none`** | You're on an emulator (or a device without a TEE / enrolled biometric). Functionally fine; not hardware-assured. |
| **`Refusing to fetch over an insecure URL`** | The library enforces HTTPS (loopback `http` allowed). Use the real `https://…eudiw.dev` endpoints. |

---

## 7. Offline self-test (no backend) — Mode A

For a quick check with **zero external dependencies** (e.g. CI, or verifying a device):

- **In-app:** Home toggle → **Mode A · mock**; use the **Load demo** buttons on Import /
  Present. An in-process issuer + verifier runs the whole loop with the hardware key.
- **Headless (Dart, no device):**
  ```bash
  flutter test test/widget_test.dart      # full holder flow vs the in-process mock
  ```
- **On-device (real plugin):**
  ```bash
  flutter test integration_test/mode_a_test.dart -d <device-id>
  ```

---

## 8. Scope

**Validated:** SD-JWT VC (`dc+sd-jwt`), OpenID4VCI pre-authorized_code + `tx_code`,
hardware PoP + key attestation, OpenID4VP with DCQL, RP auth via `x5c`, KB-JWT,
`direct_post.jwt` encrypted response, Token Status List, x5c-chain issuer trust, and
nested selective disclosure — all against live EUDI.

**Out of scope (showcase, not a product):** mdoc/ISO-18013, multi-credential requests,
encrypted local storage, deferred issuance, real EU LOTL fetch/parse (a single dev anchor
is bundled), deep-link registration polish.

---

## 9. References

- EUDI issuer: `https://issuer.eudiw.dev` · verifier: `https://verifier.eudiw.dev`
  (backend `https://verifier-backend.eudiw.dev`).
- Packages: `sdjwt_oid4vc` `0.1.2`, `attested_secure_keys` `0.1.0` (pub.dev).
- Design of the encrypted response: `../sdjwt_oid4vc/docs/DIRECT_POST_JWT.md`.
- Trust anchor: `PID Issuer CA - UT 02` from `eu-digital-identity-wallet/eudi-app-android-wallet-ui`
  (`resources-logic/src/main/res/raw/pidissuerca02_ut.pem`), bundled in `lib/eudi_trust.dart`.
- App architecture and flow-to-API mapping: `IMPLEMENTATION.md`.
