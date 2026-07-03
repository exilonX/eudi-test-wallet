import 'dart:convert';
import 'dart:typed_data';

import 'package:attested_secure_keys/attested_secure_keys.dart' as ask;
import 'package:sdjwt_oid4vc/sdjwt_oid4vc.dart';

/// The ENTIRE integration between the two packages.
///
/// Adapts one hardware key (an [ask.HwKey]) to `sdjwt_oid4vc`'s [Es256Signer]
/// interface. `sdjwt_oid4vc` never imports a key backend — it asks an
/// `Es256Signer` for a public JWK, an ES256 signature, and (optionally) a key
/// attestation. We satisfy those three calls from secure hardware.
///
/// Deliberate details (see IMPLEMENTATION.md §5/§11):
///  * both packages export a type named `KeyAttestation`, so `attested_secure_keys`
///    is imported `as ask`;
///  * [ask.HwKey.publicJwk] is a [ask.Jwk] object → `.toJson()` for the `Map`;
///  * [ask.AttestedSecureKeys.sign] takes bytes and returns `.jose` (raw R‖S,
///    base64url) — exactly the JOSE ES256 shape [signEs256] must return;
///  * [attest] is optional: on an emulator (or any device without hardware
///    attestation) we return `null` and the library simply omits the key
///    attestation — the OpenID4VCI proof still binds the key via `cnf`.
class AttestedKeysSigner implements Es256Signer {
  AttestedKeysSigner(this._keys, this._key, {this.promptTitle = 'Authorize'});

  final ask.AttestedSecureKeys _keys;
  final ask.HwKey _key;
  final String promptTitle;

  /// The hardware key this signer wraps (exposed so the UI can show its
  /// `effectiveLevel` / attestation status).
  ask.HwKey get key => _key;

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
    try {
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
    } on ask.AttestedSecureKeysException {
      // No hardware attestation available (typical on an emulator). Attestation
      // is optional in this demo — the proof-of-possession already binds the
      // key via `cnf`, so fall back to no attestation.
      return null;
    }
  }
}
