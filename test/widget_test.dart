// Headless end-to-end proof of the Mode A wiring.
//
// This drives the ENTIRE §1 flow (issue → inspect → trust → status → present)
// against the in-process mock, using a software holder signer as a stand-in for
// the hardware key. If this passes, the only thing the emulator adds on top is
// the real `attested_secure_keys` hardware key behind the same `Es256Signer`.
import 'package:flutter_test/flutter_test.dart';
import 'package:sdjwt_oid4vc/sdjwt_oid4vc.dart';
import 'package:sdjwt_oid4vc/testing.dart';
import 'package:test_wallet/mock_backend.dart';

void main() {
  test('Mode A: full holder flow against the in-process mock', () async {
    final mock = await MockIssuerVerifier.create();
    final holder = SoftwareEs256Signer.generate(); // stands in for the HW key

    // 1/2. Issue: redeem the offer (VCI pre-auth + tx_code + PoP proof).
    final compact = await Oid4vciClient(mock).redeemOffer(
      offerUriOrJson: mock.buildOfferLink(),
      txCode: MockIssuerVerifier.txCode,
      signer: holder,
    );

    // 3. Inspect.
    final vc = SdJwt.parse(compact);
    final claims = vc.resolveClaims();
    expect(vc.vct, MockIssuerVerifier.vct);
    expect(claims['given_name'], 'Ada');
    expect(claims['employment_status'], 'active');

    // 4. Trust the issuer (signature + validity window).
    final trusted = await vc.verifyIssuer(
      IssuerTrust.issuerMetadata(),
      http: mock,
      enforceValidity: true,
    );
    expect(trusted, isTrue);

    // 5. Status (Token Status List): index 0 is valid.
    final status = await StatusListResolver(mock)
        .resolve(vc.statusListRef!, trust: IssuerTrust.issuerMetadata());
    expect(status.isValid, isTrue);

    // 6. Present: authenticate the RP, match, sign the KB-JWT, submit.
    final vp = Oid4vpClient(mock);
    final req = await vp.fetchRequest(mock.buildPresentationRequestLink());
    expect(req.signature!.verifyWithJwk(mock.verifierPublicJwk), isTrue);

    final match = vp.match(req, [vc])!;
    expect(match.requestedClaims, contains(MockIssuerVerifier.requestedClaim));

    final tokenMap =
        await vp.buildVpTokenMap(matches: [match], req: req, signer: holder);
    await vp.submitResponse(req: req, vpToken: tokenMap);

    // 7. The verifier sees only the requested claim; the rest stay hidden.
    final disclosed =
        SdJwt.parse(tokenMap[match.queryId]!.first).resolveClaims();
    expect(disclosed['employment_status'], 'active');
    expect(disclosed.containsKey('given_name'), isFalse);
    expect(disclosed.containsKey('family_name'), isFalse);
  });
}
