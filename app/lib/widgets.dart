import 'package:flutter/material.dart';

import 'theme.dart';

const _gap = SizedBox(height: 12);

/// A white card with an optional title, used for each part of a result.
class InfoCard extends StatelessWidget {
  const InfoCard({super.key, this.title, this.icon, required this.child, this.color});
  final String? title;
  final IconData? icon;
  final Widget child;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Card(
      color: color ?? Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null) ...[
              Row(children: [
                if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 8)],
                Expanded(child: Text(title!, style: t.titleMedium)),
              ]),
              const SizedBox(height: 8),
            ],
            child,
          ],
        ),
      ),
    );
  }
}

/// The screening-aid statement (FR9). Shown on every result, near the top, never hidden.
class DisclaimerBanner extends StatelessWidget {
  const DisclaimerBanner(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: scheme.secondaryContainer, borderRadius: BorderRadius.circular(12)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.info_outline, color: scheme.onSecondaryContainer),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: TextStyle(color: scheme.onSecondaryContainer))),
      ]),
    );
  }
}

/// Confidence as a banded indicator with a label, never a percentage (CP1 section 3.4.2).
class BandIndicator extends StatelessWidget {
  const BandIndicator({super.key, required this.band, required this.label});
  final String band; // high | moderate | refer
  final String label;

  static Color colorFor(String band) => switch (band) {
        'high' => LumisColors.high,
        'moderate' => LumisColors.low,
        _ => LumisColors.inconclusive,
      };

  @override
  Widget build(BuildContext context) {
    final filled = switch (band) { 'high' => 3, 'moderate' => 1, _ => 0 };
    final color = colorFor(band);
    return Semantics(
      label: 'Confidence: $label',
      child: Row(children: [
        for (var i = 0; i < 3; i++)
          Container(
            width: 28,
            height: 8,
            margin: const EdgeInsets.only(right: 4),
            decoration: BoxDecoration(
              color: i < filled ? color : color.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

/// Shown when something failed, with a way to try again.
class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, this.onRetry, this.icon = Icons.cloud_off_outlined});
  final String message;
  final VoidCallback? onRetry;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 48, color: Theme.of(context).colorScheme.outline),
          _gap,
          Text(message, textAlign: TextAlign.center),
          if (onRetry != null) ...[
            _gap,
            OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Try again')),
          ],
        ]),
      ),
    );
  }
}

void showMessage(BuildContext context, String message) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

Future<bool> confirm(BuildContext context, {required String title, required String body, required String action}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
          onPressed: () => Navigator.pop(c, true),
          child: Text(action),
        ),
      ],
    ),
  );
  return ok ?? false;
}
