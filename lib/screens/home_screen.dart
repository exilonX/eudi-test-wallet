import 'package:flutter/material.dart';

import '../ui_helpers.dart';
import '../wallet_controller.dart';

/// Home — generate the hardware holder key and see the §1 checklist + any held
/// credential (IMPLEMENTATION.md §7.1).
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.controller});

  final WalletController controller;

  @override
  Widget build(BuildContext context) {
    final key = controller.hwKey;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        sectionCard(context, 'Backend', [
          SegmentedButton<WalletMode>(
            segments: const [
              ButtonSegment(
                  value: WalletMode.mockA,
                  label: Text('Mode A · mock'),
                  icon: Icon(Icons.dns_outlined)),
              ButtonSegment(
                  value: WalletMode.liveEudi,
                  label: Text('Mode B · EUDI'),
                  icon: Icon(Icons.public)),
            ],
            selected: {controller.mode},
            onSelectionChanged: (s) => controller.setMode(s.first),
          ),
          const SizedBox(height: 8),
          Text(
            controller.isLive
                ? 'Live EUDI reference (issuer.eudiw.dev). Generate a pre-auth '
                    'PID offer on the issuer site, then scan its QR on Import.'
                : 'In-process mock issuer + verifier — offline, no backend.',
            style: const TextStyle(color: Colors.black54),
          ),
        ]),
        const SizedBox(height: 8),
        sectionCard(context, 'Holder key', [
          if (key == null)
            const Text('No key yet — generate a hardware-backed EC P-256 key.')
          else ...[
            kvRow('alias', key.alias),
            kvRow('effectiveLevel', key.effectiveLevel.name),
            kvRow('hwAttestation', '${key.hasHardwareAttestation}'),
            kvRow('public JWK',
                truncate('${key.publicJwk.toJson()['x']}', 40)),
          ],
          if (controller.keyError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(controller.keyError!,
                  style: const TextStyle(color: Colors.red)),
            ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: controller.keyBusy ? null : controller.generateKey,
            icon: controller.keyBusy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.key),
            label: Text(key == null ? 'Generate hardware key' : 'Regenerate'),
          ),
        ]),
        const SizedBox(height: 8),
        sectionCard(context, '§1 success criteria', [
          for (final (label, state) in controller.criteria)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: stepIcon(state),
              title: Text(label),
            ),
        ]),
        if (controller.credential != null) ...[
          const SizedBox(height: 8),
          _heldCredentialCard(context),
        ],
      ],
    );
  }

  Widget _heldCredentialCard(BuildContext context) {
    final c = controller;
    final vct = c.credential!.vct ?? '(none)';
    final status = c.credentialStatus;
    return sectionCard(context, 'Held credential', [
      kvRow('vct', truncate(vct, 40)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        if (c.issuerTrusted != null)
          outcomeChip(
            c.issuerTrusted! ? 'issuer trusted' : 'issuer NOT trusted',
            ok: c.issuerTrusted!,
          ),
        if (status != null)
          outcomeChip(
            'status: ${status.kind.name}',
            ok: status.isValid,
          ),
      ]),
    ]);
  }
}
