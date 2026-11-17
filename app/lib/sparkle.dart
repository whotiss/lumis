import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'theme.dart';

/// How bright the star is. The same star shows confidence on the result screen.
enum SparkleStyle {
  bright, // the logo, and a high-confidence result: gradient star with a star-shaped glow
  low, // low confidence: faint, no glow
  outline, // inconclusive: outline only
}

/// The Lumis four-point star. In its bright form it "breathes": the star and its glow slowly brighten and dim.
/// The animation stops when the phone asks for reduced motion.
class Sparkle extends StatefulWidget {
  const Sparkle({super.key, this.size = 24, this.style = SparkleStyle.bright, this.animate = false, this.period});
  final double size;
  final SparkleStyle style;
  final bool animate;

  /// One full breath (dim → bright → dim). The loading screen breathes faster.
  final Duration? period;

  @override
  State<Sparkle> createState() => _SparkleState();
}

class _SparkleState extends State<Sparkle> with SingleTickerProviderStateMixin {
  AnimationController? _breath;

  bool get _wantsAnimation => widget.animate && widget.style == SparkleStyle.bright;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant Sparkle oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final on = _wantsAnimation && !reduce;
    if (on && _breath == null) {
      final half = (widget.period ?? const Duration(milliseconds: 4200)) ~/ 2;
      _breath = AnimationController(vsync: this, duration: half)..repeat(reverse: true);
    } else if (!on && _breath != null) {
      _breath!.dispose();
      _breath = null;
    }
  }

  @override
  void dispose() {
    _breath?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final breath = _breath;
    Widget paint(double t) => CustomPaint(
          size: Size.square(widget.size),
          painter: SparklePainter(style: widget.style, palette: p, breath: t),
        );
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: widget.size,
        child: breath == null
            ? paint(1)
            : AnimatedBuilder(
                animation: breath,
                builder: (_, _) => paint(Curves.easeInOut.transform(breath.value)),
              ),
      ),
    );
  }
}

/// The star path from the brand sheet, in a 100 × 100 box.
Path sparklePath(double size, {double scale = 1}) {
  final s = size / 100;
  Offset o(double x, double y) => Offset(50 * s + (x - 50) * s * scale, 50 * s + (y - 50) * s * scale);
  final a = o(50, 4);
  final path = Path()..moveTo(a.dx, a.dy);
  void c(double x1, double y1, double x2, double y2, double x, double y) {
    final p1 = o(x1, y1), p2 = o(x2, y2), p = o(x, y);
    path.cubicTo(p1.dx, p1.dy, p2.dx, p2.dy, p.dx, p.dy);
  }

  c(52, 40, 60, 48, 96, 50);
  c(60, 52, 52, 60, 50, 96);
  c(48, 60, 40, 52, 4, 50);
  c(40, 48, 48, 40, 50, 4);
  return path..close();
}

class SparklePainter extends CustomPainter {
  SparklePainter({required this.style, required this.palette, this.breath = 1});
  final SparkleStyle style;
  final LumisPalette palette;

  /// 0 = dimmest point of the breath, 1 = brightest.
  final double breath;

  @override
  void paint(Canvas canvas, Size size) {
    final d = size.shortestSide;
    final s = d / 100;
    switch (style) {
      case SparkleStyle.outline:
        canvas.drawPath(
          sparklePath(d),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = (4 * s).clamp(1.0, 3.0)
            ..strokeJoin = StrokeJoin.round
            ..color = palette.starOutline,
        );
      case SparkleStyle.low:
        canvas.drawPath(sparklePath(d), Paint()..color = palette.starLow);
      case SparkleStyle.bright:
        // Glow: two blurred copies of the star, so the light comes off the four points rather than a circle.
        final glowScale = 0.92 + 0.14 * breath;
        final glowAlpha = 0.45 + 0.55 * breath;
        final outer = palette.isDark ? 0.95 : 0.84;
        final inner = palette.isDark ? 1.0 : 0.92;
        canvas.drawPath(
          sparklePath(d, scale: 1.25 * glowScale),
          Paint()
            ..color = palette.glow.withValues(alpha: outer * glowAlpha * (palette.isDark ? 0.65 : 0.5))
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, 7 * s),
        );
        canvas.drawPath(
          sparklePath(d, scale: glowScale),
          Paint()
            ..color = palette.glow.withValues(alpha: inner * glowAlpha * (palette.isDark ? 0.75 : 0.6))
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, 2.5 * s),
        );
        final star = Paint()
          ..shader = ui.Gradient.linear(
            Offset(0, d / 2),
            Offset(d, d / 2),
            [palette.starStart, palette.starEnd],
            const [0.3, 0.8],
          );
        canvas.saveLayer(Offset.zero & size, Paint()..color = Colors.white.withValues(alpha: 0.78 + 0.22 * breath));
        canvas.drawPath(sparklePath(d), star);
        canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant SparklePainter old) =>
      old.breath != breath || old.style != style || old.palette != palette;
}

/// The star for a band: bright for high, faint for low, outline for inconclusive.
SparkleStyle sparkleFor(String band) => switch (band) {
      'high' => SparkleStyle.bright,
      'moderate' => SparkleStyle.low,
      _ => SparkleStyle.outline,
    };

/// The small star + LUMIS wordmark used at the top of screens.
class LumisWordmark extends StatelessWidget {
  const LumisWordmark({super.key, this.size = 17});
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      label: 'Lumis',
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Sparkle(size: size * 1.4),
        SizedBox(width: size * 0.6),
        ExcludeSemantics(
          child: Text('LUMIS',
              style: TextStyle(
                  fontFamily: headingFont,
                  fontWeight: FontWeight.w400,
                  fontSize: size,
                  letterSpacing: size * 0.3,
                  color: p.ink)),
        ),
      ]),
    );
  }
}
