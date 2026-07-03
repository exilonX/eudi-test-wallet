package com.example.test_wallet

import io.flutter.embedding.android.FlutterFragmentActivity

// FlutterFragmentActivity (not the default FlutterActivity) is required so that
// attested_secure_keys can show the androidx.biometric BiometricPrompt when
// signing with a user-auth-gated hardware key. On a real device the holder key
// is biometric-gated (effectiveLevel=trustedEnvironment, actuallyGated=true),
// and every sign() — the OpenID4VCI PoP proof and the OpenID4VP KB-JWT — fires
// that prompt, which needs a FragmentActivity host.
class MainActivity : FlutterFragmentActivity()
