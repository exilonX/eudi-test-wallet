import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// A full-screen QR scanner. Pops the first decoded string back to the caller.
/// Used in Mode B to scan the EUDI issuer's offer QR and the verifier's request
/// QR shown on screen.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key, this.title = 'Scan QR'});

  final String title;

  /// Opens the scanner and returns the scanned string, or null if cancelled.
  static Future<String?> open(BuildContext context, {String? title}) {
    return Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => ScanScreen(title: title ?? 'Scan QR'),
      ),
    );
  }

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  bool _handled = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: MobileScanner(
        onDetect: (capture) {
          if (_handled) return;
          final code = capture.barcodes.isNotEmpty
              ? capture.barcodes.first.rawValue
              : null;
          if (code == null || code.isEmpty) return;
          _handled = true;
          Navigator.of(context).pop(code);
        },
      ),
    );
  }
}
