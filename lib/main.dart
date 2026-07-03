import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'screens/import_screen.dart';
import 'screens/present_screen.dart';
import 'wallet_controller.dart';

void main() => runApp(const TestWalletApp());

/// The whole demo: a hardware holder key ([attested_secure_keys]) driving the
/// SD-JWT VC / OpenID4VCI / OpenID4VP holder flow ([sdjwt_oid4vc]) against an
/// in-process mock issuer + verifier — "Mode A" from IMPLEMENTATION.md.
class TestWalletApp extends StatefulWidget {
  const TestWalletApp({super.key});

  @override
  State<TestWalletApp> createState() => _TestWalletAppState();
}

class _TestWalletAppState extends State<TestWalletApp> {
  final WalletController controller = WalletController();

  @override
  void initState() {
    super.initState();
    controller.init();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Test Wallet',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          if (!controller.isReady) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          return WalletShell(controller: controller);
        },
      ),
    );
  }
}

/// Bottom-nav shell over the three screens. No routing framework — just an index
/// and a shared [WalletController] (IMPLEMENTATION.md §7).
class WalletShell extends StatefulWidget {
  const WalletShell({super.key, required this.controller});

  final WalletController controller;

  @override
  State<WalletShell> createState() => _WalletShellState();
}

class _WalletShellState extends State<WalletShell> {
  int _index = 0;

  static const _titles = ['Home', 'Import', 'Present'];

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final screens = [
      HomeScreen(controller: c),
      // Keyed by mode so switching backends re-runs each screen's prefill.
      ImportScreen(key: ValueKey('import-${c.mode}'), controller: c),
      PresentScreen(key: ValueKey('present-${c.mode}'), controller: c),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text('Test Wallet — ${_titles[_index]}'),
      ),
      body: screens[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Home'),
          NavigationDestination(
              icon: Icon(Icons.download_outlined),
              selectedIcon: Icon(Icons.download),
              label: 'Import'),
          NavigationDestination(
              icon: Icon(Icons.send_outlined),
              selectedIcon: Icon(Icons.send),
              label: 'Present'),
        ],
      ),
    );
  }
}
