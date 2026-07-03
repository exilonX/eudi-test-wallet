// On-device Mode A proof: drives the whole §1 flow through the REAL
// `attested_secure_keys` plugin (via the WalletController) on the emulator, so
// the hardware key path — generateKey / sign / attest over the method channel —
// is exercised end to end, not just the pure-Dart library.
//
// Run:  flutter test integration_test/mode_a_test.dart -d emulator-5554
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:test_wallet/mock_backend.dart';
import 'package:test_wallet/wallet_controller.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Mode A end-to-end with the real hardware key', (tester) async {
    final c = WalletController();
    await c.init();

    // §6.1 — hardware key + Es256Signer.
    await c.generateKey();
    expect(c.hwKey, isNotNull, reason: c.keyError);
    expect(c.signer, isNotNull);
    // Report the assurance the emulator actually landed on (software/none).
    // ignore: avoid_print
    print('effectiveLevel=${c.hwKey!.effectiveLevel.name} '
        'hwAttestation=${c.hwKey!.hasHardwareAttestation}');

    // §6.2/§6.3 — redeem the offer, inspect, trust, status.
    await c.redeem(c.mock.buildOfferLink(), MockIssuerVerifier.txCode);
    expect(c.importError, isNull, reason: c.importError);
    expect(c.credentialCompact, isNotNull);
    expect(c.claims, isNotNull);
    expect(c.issuerTrusted, isTrue);
    expect(c.credentialStatus?.isValid, isTrue);

    // §6.4 — authenticate the RP, match, present.
    await c.loadPresentationRequest(c.mock.buildPresentationRequestLink());
    expect(c.presentError, isNull, reason: c.presentError);
    expect(c.rpAuthentic, isTrue);
    expect(c.match, isNotNull);

    await c.approveAndSend();
    expect(c.presentError, isNull, reason: c.presentError);
    expect(c.disclosed?['employment_status'], 'active');
    expect(c.disclosed!.containsKey('given_name'), isFalse);
    expect(c.disclosed!.containsKey('family_name'), isFalse);

    // Every §1 criterion must be green.
    for (final (label, state) in c.criteria) {
      expect(state, CriterionState.pass, reason: 'criterion failed: $label');
    }
  });
}
