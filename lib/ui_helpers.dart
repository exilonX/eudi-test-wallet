import 'package:flutter/material.dart';

import 'wallet_controller.dart';

/// A pass/idle/fail/running glyph for a §1 criterion.
Icon stepIcon(CriterionState s) => switch (s) {
      CriterionState.pass => const Icon(Icons.check_circle, color: Colors.green),
      CriterionState.fail => const Icon(Icons.cancel, color: Colors.red),
      CriterionState.running =>
        const Icon(Icons.hourglass_top, color: Colors.orange),
      CriterionState.idle =>
        const Icon(Icons.radio_button_unchecked, color: Colors.grey),
    };

/// A coloured chip for a boolean outcome (green=ok, red=not).
Widget outcomeChip(String text, {required bool ok}) => Chip(
      avatar: Icon(ok ? Icons.check : Icons.close,
          size: 18, color: Colors.white),
      label: Text(text),
      backgroundColor: ok ? Colors.green.shade600 : Colors.red.shade600,
      labelStyle: const TextStyle(color: Colors.white),
      visualDensity: VisualDensity.compact,
    );

/// A labelled key/value row for showing decoded fields.
Widget kvRow(String k, String v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 128,
            child: Text(k,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          Expanded(
              child: Text(v, style: const TextStyle(fontFamily: 'monospace'))),
        ],
      ),
    );

/// A titled card wrapper.
Widget sectionCard(BuildContext context, String title, List<Widget> children) =>
    Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );

/// Truncate long values (keys, tokens) for compact display.
String truncate(String s, [int max = 44]) =>
    s.length <= max ? s : '${s.substring(0, max)}…';
