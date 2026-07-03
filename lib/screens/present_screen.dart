import 'package:flutter/material.dart';

import '../scan_screen.dart';
import '../ui_helpers.dart';
import '../wallet_controller.dart';

/// Present — load a verifier's OpenID4VP request, authenticate the RP, then
/// disclose only the requested claims with a hardware-signed KB-JWT
/// (IMPLEMENTATION.md §7.3 / §6.4).
class PresentScreen extends StatefulWidget {
  const PresentScreen({super.key, required this.controller});

  final WalletController controller;

  @override
  State<PresentScreen> createState() => _PresentScreenState();
}

class _PresentScreenState extends State<PresentScreen> {
  late final TextEditingController _request;

  @override
  void initState() {
    super.initState();
    // Mode A prefills the mock's request; Mode B starts empty (scan the EUDI
    // verifier's QR). Keyed by mode, so this re-runs on a mode switch.
    final c = widget.controller;
    _request = TextEditingController(
        text: c.isLive ? '' : c.mock.buildPresentationRequestLink());
  }

  @override
  void dispose() {
    _request.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    final code = await ScanScreen.open(context, title: 'Scan request QR');
    if (code != null && mounted) setState(() => _request.text = code);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        sectionCard(context, 'Presentation request', [
          TextField(
            controller: _request,
            maxLines: 2,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            decoration: const InputDecoration(
              labelText: 'openid4vp:// request link',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            FilledButton.icon(
              onPressed: c.presentBusy
                  ? null
                  : () => c.loadPresentationRequest(_request.text.trim()),
              icon: c.presentBusy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.search),
              label: const Text('Load request'),
            ),
            OutlinedButton.icon(
              onPressed: _scan,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Scan QR'),
            ),
            if (!c.isLive)
              TextButton(
                onPressed: () => setState(() => _request.text =
                    c.mock.buildPresentationRequestLink()),
                child: const Text('Load demo'),
              ),
          ]),
          if (c.presentError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(c.presentError!,
                  style: const TextStyle(color: Colors.red)),
            ),
        ]),
        if (c.request != null) ...[
          const SizedBox(height: 8),
          sectionCard(context, 'Verifier (RP)', [
            kvRow('client_id', c.request!.clientId),
            kvRow('response_mode', c.request!.responseMode),
            const SizedBox(height: 8),
            if (c.rpAuthentic != null)
              outcomeChip(
                c.rpAuthentic!
                    ? 'RP request signature authentic'
                    : 'RP signature INVALID',
                ok: c.rpAuthentic!,
              ),
            if (c.match != null) ...[
              const Divider(height: 24),
              Text('Requested claims',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                // Render full DCQL paths (incl. nested, e.g. place_of_birth/locality),
                // not just top-level names — that's what actually gets disclosed.
                (c.match!.requestedPaths.isNotEmpty
                        ? c.match!.requestedPaths
                            .map((p) => p.map((s) => s ?? '*').join('/'))
                        : c.match!.requestedClaims)
                    .join(', '),
                style: const TextStyle(fontFamily: 'monospace'),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: c.presentBusy ? null : c.approveAndSend,
                icon: const Icon(Icons.send),
                label: const Text('Approve & send'),
              ),
            ] else ...[
              const SizedBox(height: 12),
              const Text('No held credential satisfies this request.',
                  style: TextStyle(
                      color: Colors.orange, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text('The request asks for:',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              for (final q in c.request!.dcql.credentials)
                kvRow(
                  q.id.isEmpty ? 'query' : q.id,
                  'format=${q.format ?? "any"} · '
                      'vct=${q.vctValues.isEmpty ? "any" : q.vctValues.join(", ")} · '
                      'claims=${q.claims.isEmpty ? "(all)" : q.claims.map((cl) => cl.path.map((p) => p ?? "*").join("/")).join(", ")}',
                ),
              const SizedBox(height: 4),
              kvRow('you hold', 'vct=${c.credential?.vct ?? "-"}'),
              const SizedBox(height: 8),
              const Text(
                'On verifier.eudiw.dev, request PID in SD-JWT VC format '
                '(vct urn:eudi:pid:1) with top-level claims — not mdoc.',
                style: TextStyle(color: Colors.black54),
              ),
            ],
          ]),
        ],
        if (c.disclosed != null) ...[
          const SizedBox(height: 8),
          sectionCard(context, 'Presented (what the verifier receives)', [
            if (c.submitRedirect != null)
              outcomeChip('submitted → ${truncate(c.submitRedirect!, 32)}',
                  ok: true),
            const SizedBox(height: 8),
            Text('Disclosed claims',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            for (final e in c.disclosed!.entries)
              kvRow(e.key, truncate('${e.value}', 48)),
            const SizedBox(height: 8),
            Text(
              'Hidden: given_name=${!c.disclosed!.containsKey('given_name')}, '
              'family_name=${!c.disclosed!.containsKey('family_name')}',
              style: const TextStyle(color: Colors.black54),
            ),
          ]),
        ],
      ],
    );
  }
}
