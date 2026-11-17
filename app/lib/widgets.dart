import 'package:flutter/material.dart';

import 'sparkle.dart';
import 'theme.dart';

/// The glossy card used everywhere: paper with a soft top-to-bottom sheen, a hairline border and sharp corners.
class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.tone = PanelTone.paper,
    this.onTap,
    this.raised = false,
    this.radius = 10,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final PanelTone tone;
  final VoidCallback? onTap;
  final bool raised; // a stronger shadow, for the main card on a screen
  final double radius;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final nebula = tone == PanelTone.nebula;
    final r = BorderRadius.circular(radius);
    final box = BoxDecoration(
      gradient: nebula ? p.nebulaGradient : p.cardGradient,
      borderRadius: r,
      border: Border.all(color: nebula ? p.nebulaBorder : p.border),
      boxShadow: [
        BoxShadow(color: p.shadow, blurRadius: raised ? 36 : 18, offset: Offset(0, raised ? 14 : 6)),
      ],
    );
    final content = Padding(padding: padding, child: child);
    return DecoratedBox(
      decoration: box,
      child: onTap == null
          ? content
          : Material(
              type: MaterialType.transparency,
              child: InkWell(borderRadius: r, onTap: onTap, child: content),
            ),
    );
  }
}

enum PanelTone { paper, nebula }

/// Small spaced capitals above a section ("IN YOUR PHOTO").
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final label = Text(text.toUpperCase(),
        style: TextStyle(fontSize: 11, letterSpacing: 2, color: context.palette.muted, height: 1.2));
    if (trailing == null) return Semantics(header: true, child: label);
    return Row(children: [Expanded(child: Semantics(header: true, child: label)), trailing!]);
  }
}

enum LumisButtonKind { primary, secondary }

/// The main buttons: a glossy indigo (lavender in dark mode) gradient, or a quiet outline.
class LumisButton extends StatelessWidget {
  const LumisButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.kind = LumisButtonKind.primary,
    this.busy = false,
    this.height,
  });
  const LumisButton.secondary({super.key, required this.label, required this.onPressed, this.icon, this.busy = false})
      : kind = LumisButtonKind.secondary,
        height = null;

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final LumisButtonKind kind;
  final bool busy;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final primary = kind == LumisButtonKind.primary;
    final enabled = onPressed != null && !busy;
    final fg = primary ? p.onButton : p.ink;
    final r = BorderRadius.circular(8);
    final h = height ?? (primary ? 54.0 : 50.0);
    final child = busy
        ? SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2, color: fg))
        : Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, size: 18, color: fg), const SizedBox(width: 9)],
            Flexible(
              child: Text(label,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: bodyFont, fontWeight: FontWeight.w500, fontSize: 15, color: fg)),
            ),
          ]);
    return Semantics(
      button: true,
      enabled: enabled,
      child: Opacity(
        opacity: enabled || busy ? 1 : 0.45,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: primary ? p.buttonGradient : null,
            borderRadius: r,
            border: primary ? null : Border.all(color: p.secondaryBorder),
            boxShadow: primary
                ? [
                    BoxShadow(
                        color: (p.isDark ? p.buttonBottom : p.accent).withValues(alpha: 0.26),
                        blurRadius: 22,
                        offset: const Offset(0, 8)),
                  ]
                : null,
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: r,
              onTap: enabled ? onPressed : null,
              child: SizedBox(height: h, child: Center(child: child)),
            ),
          ),
        ),
      ),
    );
  }
}

/// A 44 × 44 bordered square with an icon (back, settings, light/dark).
class SquareIconButton extends StatelessWidget {
  const SquareIconButton({super.key, required this.icon, required this.tooltip, required this.onPressed});
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: SizedBox.square(
          dimension: 44,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: p.cardGradient,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: p.border),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: onPressed,
                child: Icon(icon, size: 19, color: p.ink),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The top bar used on inner screens: a square back button, then a title (Jost) or a small label.
PreferredSizeWidget lumisAppBar(BuildContext context,
    {String? title, String? label, String? subtitle, List<Widget> actions = const []}) {
  final p = context.palette;
  final canPop = Navigator.of(context).canPop();
  return AppBar(
    automaticallyImplyLeading: false,
    toolbarHeight: subtitle == null ? 72 : 84,
    titleSpacing: 20,
    title: Row(children: [
      if (canPop) ...[
        SquareIconButton(
            icon: Icons.chevron_left_rounded, tooltip: 'Back', onPressed: () => Navigator.of(context).maybePop()),
        const SizedBox(width: 12),
      ],
      Expanded(
        child: label != null
            ? SectionLabel(label)
            : Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(title ?? '',
                    maxLines: subtitle == null ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontFamily: headingFont,
                        fontWeight: FontWeight.w300,
                        fontSize: subtitle == null ? 26 : 24,
                        height: 1.15,
                        color: p.ink)),
                if (subtitle != null)
                  Text(subtitle, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w300, color: p.muted)),
              ]),
      ),
    ]),
    actions: [...actions, const SizedBox(width: 12)],
  );
}

/// The screening-aid statement (FR9). Shown on every result, near the top, never hidden.
class DisclaimerBanner extends StatelessWidget {
  const DisclaimerBanner(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        gradient: p.nebulaGradient,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: p.nebulaBorder),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(Icons.info_outline_rounded, size: 17, color: p.nebulaText),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: TextStyle(fontSize: 13, height: 1.5, color: p.nebulaText))),
      ]),
    );
  }
}

/// Confidence as three steps, each with a star as bright as the band: Inconclusive (outline), Low (faint),
/// High (glowing). Never a percentage (CP1 section 3.4.2). On 2026-11-15 the "moderate" band was labeled
/// "Low confidence" because those results were right only 31% of the time on phone photos, so there is no
/// "Moderate" step.
class ConfidenceScale extends StatelessWidget {
  const ConfidenceScale({super.key, required this.band, required this.label});
  final String band; // high | moderate | refer
  final String label; // the server's wording, read by screen readers

  static int stepFor(String band) => switch (band) { 'high' => 2, 'moderate' => 1, _ => 0 };
  static const _steps = [
    ('Inconclusive', SparkleStyle.outline),
    ('Low', SparkleStyle.low),
    ('High', SparkleStyle.bright),
  ];

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final active = stepFor(band);
    return Semantics(
      label: 'Confidence: $label',
      excludeSemantics: true,
      child: Row(children: [
        for (var i = 0; i < 3; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              decoration: BoxDecoration(
                gradient: i == active ? p.nebulaGradient : null,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: i == active ? (p.isDark ? p.buttonBottom : p.accent) : Colors.transparent),
              ),
              child: Column(children: [
                Opacity(opacity: i == active ? 1 : 0.5, child: Sparkle(size: 26, style: _steps[i].$2)),
                const SizedBox(height: 6),
                Text(_steps[i].$1,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: i == active ? FontWeight.w500 : FontWeight.w400,
                        color: i == active ? p.ink : p.starOutline)),
              ]),
            ),
          ),
        ],
      ]),
    );
  }
}

/// A card with a section label, used for each part of a result or condition.
class InfoCard extends StatelessWidget {
  const InfoCard({super.key, this.title, this.icon, required this.child, this.trailing});
  final String? title;
  final IconData? icon; // kept for older callers; the redesign uses labels without icons
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (title != null) ...[SectionLabel(title!, trailing: trailing), const SizedBox(height: 10)],
        DefaultTextStyle.merge(style: Theme.of(context).textTheme.bodyMedium, child: child),
      ]),
    );
  }
}

/// Shown when something failed, with a way to try again.
class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, this.onRetry, this.icon});
  final String message;
  final VoidCallback? onRetry;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          icon != null
              ? Icon(icon, size: 40, color: p.starOutline)
              : const Sparkle(size: 44, style: SparkleStyle.outline),
          const SizedBox(height: 16),
          Text(message, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
          if (onRetry != null) ...[
            const SizedBox(height: 18),
            SizedBox(
              width: 200,
              child: LumisButton.secondary(label: 'Try again', icon: Icons.refresh_rounded, onPressed: onRetry),
            ),
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
          style: FilledButton.styleFrom(minimumSize: const Size(0, 42)),
          onPressed: () => Navigator.pop(c, true),
          child: Text(action),
        ),
      ],
    ),
  );
  return ok ?? false;
}
