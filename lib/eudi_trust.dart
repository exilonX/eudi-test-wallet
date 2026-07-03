/// EUDI reference (dev) trust anchors, bundled out-of-band.
///
/// The online EUDI issuer (`https://issuer.eudiw.dev`) does NOT serve
/// `/.well-known/jwt-vc-issuer`, so SD-JWT VC issuer verification cannot use
/// `IssuerTrust.issuerMetadata()`. Instead the credential carries an `x5c`
/// chain down to the document-signer cert, and the wallet must validate that
/// chain to a bundled IACA root — hence `IssuerTrust.x5cChain(trustAnchors:)`.
///
/// Below is the "PID Issuer CA - UT 02" self-signed root (base64 DER), taken
/// from the EUDI reference wallet:
///   eu-digital-identity-wallet/eudi-app-android-wallet-ui
///   resources-logic/src/main/res/raw/pidissuerca02_ut.pem
/// Subject == Issuer: CN=PID Issuer CA - UT 02, O=EUDI Wallet Reference
/// Implementation, C=UT · valid 2025-03-24 .. 2034-06-20.
const String eudiPidIssuerCaUt02 =
    'MIIC3TCCAoOgAwIBAgIUEwybFc9Jw+az3r188OiHDaxCfHEwCgYIKoZIzj0EAwMw'
    'XDEeMBwGA1UEAwwVUElEIElzc3VlciBDQSAtIFVUIDAyMS0wKwYDVQQKDCRFVURJ'
    'IFdhbGxldCBSZWZlcmVuY2UgSW1wbGVtZW50YXRpb24xCzAJBgNVBAYTAlVUMB4X'
    'DTI1MDMyNDIwMjYxNFoXDTM0MDYyMDIwMjYxM1owXDEeMBwGA1UEAwwVUElEIElz'
    'c3VlciBDQSAtIFVUIDAyMS0wKwYDVQQKDCRFVURJIFdhbGxldCBSZWZlcmVuY2Ug'
    'SW1wbGVtZW50YXRpb24xCzAJBgNVBAYTAlVUMFkwEwYHKoZIzj0CAQYIKoZIzj0D'
    'AQcDQgAEesDKj9rCIcrGj0wbSXYvCV953bOPSYLZH5TNmhTz2xa7VdlvQgQeGZRg'
    '1PrF5AFwt070wvL9qr1DUDdvLp6a1qOCASEwggEdMBIGA1UdEwEB/wQIMAYBAf8C'
    'AQAwHwYDVR0jBBgwFoAUYseURyi9D6IWIKeawkmURPEB08cwEwYDVR0lBAwwCgYI'
    'K4ECAgAAAQcwQwYDVR0fBDwwOjA4oDagNIYyaHR0cHM6Ly9wcmVwcm9kLnBraS5l'
    'dWRpdy5kZXYvY3JsL3BpZF9DQV9VVF8wMi5jcmwwHQYDVR0OBBYEFGLHlEcovQ+i'
    'FiCnmsJJlETxAdPHMA4GA1UdDwEB/wQEAwIBBjBdBgNVHRIEVjBUhlJodHRwczov'
    'L2dpdGh1Yi5jb20vZXUtZGlnaXRhbC1pZGVudGl0eS13YWxsZXQvYXJjaGl0ZWN0'
    'dXJlLWFuZC1yZWZlcmVuY2UtZnJhbWV3b3JrMAoGCCqGSM49BAMDA0gAMEUCIQCe'
    '4R9rO4JhFp821kO8Gkb8rXm4qGG/e5/Oi2XmnTQqOQIgfFs+LDbnP2/j1MB4rwZ1'
    'FgGdpr4oyrFB9daZyRIcP90=';

/// Trust anchors accepted for EUDI (dev) issuer verification.
const List<String> eudiTrustAnchors = [eudiPidIssuerCaUt02];
