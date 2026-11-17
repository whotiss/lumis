import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../auth_state.dart';
import '../config.dart';
import '../models.dart';
import '../sparkle.dart';
import '../theme.dart';
import '../widgets.dart';
import 'capture_screen.dart';
import 'result_screen.dart';

/// "Analyzing": sends the photo and shows that work is under way, so the wait is not mistaken for a failure (NFR1).
/// Sending the photo is real progress (bytes sent). After that the server gives no progress, so the ring moves on
/// a timer based on the usual 4 to 5 seconds and only completes when the result arrives.
class ProcessingScreen extends StatefulWidget {
  const ProcessingScreen({super.key, required this.photo, required this.details});
  final Uint8List photo;
  final SymptomDetails details;

  @override
  State<ProcessingScreen> createState() => _ProcessingScreenState();
}

class _ProcessingScreenState extends State<ProcessingScreen> with SingleTickerProviderStateMixin {
  static const _expected = Duration(milliseconds: 4500); // usual time from photo received to result

  late final Ticker _ticker = createTicker((_) => setState(() {}));
  ApiException? _error;
  bool _slow = false;
  Timer? _slowTimer;
  double _sent = 0;
  DateTime? _receivedAt; // when the server had the whole photo
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _send();
  }

  @override
  void dispose() {
    _slowTimer?.cancel();
    _ticker.dispose();
    super.dispose();
  }

  void _retry() {
    setState(() {
      _error = null;
      _slow = false;
      _sent = 0;
      _receivedAt = null;
      _done = false;
    });
    _send();
  }

  void _onUpload(double sent) {
    _sent = sent;
    if (sent >= 1 && _receivedAt == null) _receivedAt = DateTime.now();
  }

  Future<void> _send() async {
    if (!_ticker.isActive) _ticker.start();
    _slowTimer?.cancel();
    _slowTimer = Timer(slowNotice, () {
      if (mounted) setState(() => _slow = true);
    });
    try {
      final s = await context.read<Api>().createScreening(widget.photo, widget.details, onUpload: _onUpload);
      if (!mounted) return;
      setState(() => _done = true);
      HapticFeedback.lightImpact();
      await Future<void>.delayed(const Duration(milliseconds: 350)); // let the ring close
      if (!mounted) return;
      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => ResultScreen(screening: s, photo: widget.photo)));
    } on ApiException catch (e) {
      if (!mounted) return;
      final problem = Api.photoProblem(e);
      if (problem != null) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => PhotoProblemScreen(problem: problem)));
      } else if (e.code == 'consent_required') {
        await context.read<AuthState>().refresh(); // shows the consent screen
        if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
      } else {
        setState(() => _error = e);
      }
    } finally {
      _slowTimer?.cancel();
      if (_ticker.isActive) _ticker.stop();
    }
  }

  /// 0..1 for the time since the photo arrived, eased so it slows down as it approaches the usual finish.
  double get _waited {
    final at = _receivedAt;
    if (at == null) return 0;
    final x = DateTime.now().difference(at).inMilliseconds / _expected.inMilliseconds;
    return 1 - math.exp(-1.6 * x); // never reaches 1 on its own
  }

  double get _progress => _done ? 1 : math.min(0.95, 0.2 * _sent + 0.78 * _waited);

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    if (_error != null) {
      return Scaffold(appBar: lumisAppBar(context, label: 'Analyzing'), body: ErrorView(message: _error!.message, onRetry: _retry));
    }
    final received = _sent >= 1 || _done;
    final comparing = received && !_done && _waited < 0.6;
    final writing = received && !_done && !comparing;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
          child: Column(children: [
            const SectionLabel('Analyzing'),
            Expanded(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Semantics(
                  label: 'Analyzing your photo',
                  value: '${(_progress * 100).round()} percent',
                  child: SizedBox.square(
                    dimension: 220,
                    child: CustomPaint(
                      painter: _RingPainter(progress: _progress, palette: p),
                      child: const Center(child: Sparkle(size: 140, animate: true, period: Duration(milliseconds: 2400))),
                    ),
                  ),
                ),
                const SizedBox(height: 26),
                Text('Analyzing your photo', style: t.headlineMedium, textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text(
                  _slow
                      ? 'Taking longer than usual. The server may be starting up; the first check after a quiet '
                          'period can take up to a minute.'
                      : 'Usually takes about 5 seconds',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w300, height: 1.5, color: p.muted),
                ),
                const SizedBox(height: 24),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: Panel(
                    padding: const EdgeInsets.all(18),
                    child: Column(children: [
                      _Step(received ? 'Photo received' : 'Sending your photo', done: received, active: !received),
                      const SizedBox(height: 12),
                      _Step('Comparing with 5 conditions', done: _done || writing, active: comparing),
                      const SizedBox(height: 12),
                      _Step('Writing your result', done: _done, active: writing),
                    ]),
                  ),
                ),
              ]),
            ),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(value: _progress, minHeight: 4),
            ),
            const SizedBox(height: 14),
            Text(
              'Keep the app open. Your photo is sent securely and is not kept unless you chose that in Settings.',
              textAlign: TextAlign.center,
              style: t.bodySmall,
            ),
          ]),
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step(this.label, {required this.done, required this.active});
  final String label;
  final bool done;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final color = p.isDark ? p.buttonBottom : p.accent;
    final Widget mark = done
        ? Icon(Icons.check_circle_rounded, size: 19, color: color)
        : active
            ? SizedBox.square(
                dimension: 17,
                child: CircularProgressIndicator(strokeWidth: 2.2, color: color, backgroundColor: p.nebulaBorder))
            : Icon(Icons.circle_outlined, size: 19, color: p.secondaryBorder);
    return Row(children: [
      SizedBox(width: 20, child: Center(child: mark)),
      const SizedBox(width: 12),
      Expanded(
        child: Text(label,
            style: TextStyle(fontSize: 14, color: done || active ? p.ink : p.starOutline, fontWeight: FontWeight.w400)),
      ),
    ]);
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.progress, required this.palette});
  final double progress;
  final LumisPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.023;
    final rect = Offset.zero & size;
    final ring = rect.deflate(stroke);
    canvas.drawArc(ring, 0, math.pi * 2, false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..color = palette.border);
    if (progress <= 0) return;
    canvas.drawArc(
      ring,
      -math.pi / 2,
      math.pi * 2 * progress,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          colors: [palette.isDark ? palette.buttonBottom : palette.buttonTop, palette.starEnd],
          transform: const GradientRotation(-math.pi / 2), // start at the top, like the arc
        ).createShader(ring),
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.progress != progress || old.palette != palette;
}

/// Shown instead of a result when the photo check stops a photo (no skin, unclear, or unlike anything Lumis knows).
/// "Nothing detected" never means "your skin is healthy" (NFR8): the wording comes from the server.
class PhotoProblemScreen extends StatelessWidget {
  const PhotoProblemScreen({super.key, required this.problem});
  final PhotoProblem problem;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final p = context.palette;
    return Scaffold(
      appBar: lumisAppBar(context, label: 'Photo check'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          const Align(alignment: Alignment.centerLeft, child: Sparkle(size: 52, style: SparkleStyle.outline)),
          const SizedBox(height: 18),
          Text(problem.headline, style: t.headlineMedium),
          const SizedBox(height: 10),
          Text(problem.advice, style: t.bodyLarge?.copyWith(color: p.body)),
          const SizedBox(height: 20),
          if (problem.disclaimer.isNotEmpty) DisclaimerBanner(problem.disclaimer),
          const SizedBox(height: 26),
          LumisButton(
            label: 'Take another photo',
            icon: Icons.photo_camera_outlined,
            onPressed: () =>
                Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const CaptureScreen())),
          ),
          const SizedBox(height: 10),
          LumisButton.secondary(label: 'Back to home', onPressed: () => Navigator.pop(context)),
        ],
      ),
    );
  }
}
