import 'package:flutter/material.dart';

import '../mock_backend.dart';
import '../scan_screen.dart';
import '../ui_helpers.dart';
import '../wallet_controller.dart';

/// Import — paste/scan an offer link + tx_code, redeem it, then inspect + trust
/// + status (IMPLEMENTATION.md §7.2 / §6.2 / §6.3).
class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key, required this.controller});

  final WalletController controller;

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  late final TextEditingController _offer;
  late final TextEditingController _txCode;

  @override
  void initState() {
    super.initState();
    // Mode A has no external issuer, so the app pre-fills the offer the mock
    // would have produced. Mode B starts empty — the user scans a real EUDI
    // offer QR. (The screen is keyed by mode, so this re-runs on a mode switch.)
    final c = widget.controller;
    _offer = TextEditingController(
        text: c.isLive ? '' : c.mock.buildOfferLink());
    _txCode = TextEditingController(
        text: c.isLive ? '' : MockIssuerVerifier.txCode);
  }

  @override
  void dispose() {
    _offer.dispose();
    _txCode.dispose();
    super.dispose();
  }

  void _loadDemo() {
    setState(() {
      _offer.text = widget.controller.mock.buildOfferLink();
      _txCode.text = MockIssuerVerifier.txCode;
    });
  }

  Future<void> _scan() async {
    final code = await ScanScreen.open(context, title: 'Scan offer QR');
    if (code != null && mounted) setState(() => _offer.text = code);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        sectionCard(context, 'Credential offer', [
          TextField(
            controller: _offer,
            maxLines: 3,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            decoration: const InputDecoration(
              labelText: 'openid-credential-offer:// link or offer JSON',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _txCode,
            decoration: const InputDecoration(
              labelText: 'tx_code',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            FilledButton.icon(
              onPressed: c.importBusy
                  ? null
                  : () => c.redeem(_offer.text.trim(), _txCode.text.trim()),
              icon: c.importBusy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.download),
              label: const Text('Redeem'),
            ),
            OutlinedButton.icon(
              onPressed: _scan,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Scan QR'),
            ),
            if (!c.isLive)
              TextButton(onPressed: _loadDemo, child: const Text('Load demo')),
          ]),
          if (c.importError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(c.importError!,
                  style: const TextStyle(color: Colors.red)),
            ),
        ]),
        if (c.claims != null) ...[
          const SizedBox(height: 8),
          sectionCard(context, 'Issued credential', [
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (c.issuerTrusted != null)
                outcomeChip(
                  c.issuerTrusted! ? 'issuer signature valid' : 'issuer invalid',
                  ok: c.issuerTrusted!,
                ),
              if (c.credentialStatus != null)
                outcomeChip(
                  'status: ${c.credentialStatus!.kind.name}',
                  ok: c.credentialStatus!.isValid,
                ),
            ]),
            const Divider(height: 24),
            Text('Claims', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final e in c.claims!.entries)
              kvRow(e.key, truncate('${e.value}', 48)),
          ]),
        ],
      ],
    );
  }
}
