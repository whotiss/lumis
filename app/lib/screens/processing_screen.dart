import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../auth_state.dart';
import '../config.dart';
import '../models.dart';
import '../widgets.dart';
import 'capture_screen.dart';
import 'result_screen.dart';

/// Sends the photo and shows that work is under way, so the wait is not mistaken for a failure (NFR1).
class ProcessingScreen extends StatefulWidget {
  const ProcessingScreen({super.key, required this.photo, required this.details});
  final Uint8List photo;
  final SymptomDetails details;

  @override
  State<ProcessingScreen> createState() => _ProcessingScreenState();
}

class _ProcessingScreenState extends State<ProcessingScreen> {
  ApiException? _error;
  bool _slow = false;
  Timer? _slowTimer;

  @override
  void initState() {
    super.initState();
    _send();
  }

  @override
  void dispose() {
    _slowTimer?.cancel();
    super.dispose();
  }

  void _retry() {
    setState(() {
      _error = null;
      _slow = false;
    });
    _send();
  }

  Future<void> _send() async {
    _slowTimer?.cancel();
    _slowTimer = Timer(slowNotice, () {
      if (mounted) setState(() => _slow = true);
    });
    try {
      final s = await context.read<Api>().createScreening(widget.photo, widget.details);
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ResultScreen(screening: s)));
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
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Checking your photo')),
      body: _error != null
          ? ErrorView(message: _error!.message, onRetry: _retry)
          : Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(widget.photo, width: 160, height: 160, fit: BoxFit.cover),
                  ),
                  const SizedBox(height: 28),
                  const LinearProgressIndicator(),
                  const SizedBox(height: 20),
                  Text('Lumis is checking your photo', style: t.titleMedium),
                  const SizedBox(height: 8),
                  Text(
                    _slow
                        ? 'The server is starting up. The first check after a quiet period can take up to a minute.'
                        : 'This usually takes about 5 seconds.',
                    textAlign: TextAlign.center,
                  ),
                ]),
              ),
            ),
    );
  }
}

/// Shown instead of a result when the photo check stops a photo (no skin, unclear, or unlike anything Lumis knows).
/// "Nothing detected" never means "your skin is healthy" (NFR8): the wording comes from the server.
class PhotoProblemScreen extends StatelessWidget {
  const PhotoProblemScreen({super.key, required this.problem});
  final PhotoProblem problem;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Photo check')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Icon(Icons.image_not_supported_outlined, size: 48, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 16),
          Text(problem.headline, style: t.headlineSmall),
          const SizedBox(height: 8),
          Text(problem.advice, style: t.bodyLarge),
          const SizedBox(height: 20),
          if (problem.disclaimer.isNotEmpty) DisclaimerBanner(problem.disclaimer),
          const SizedBox(height: 24),
          FilledButton.icon(
            icon: const Icon(Icons.photo_camera_outlined),
            label: const Text('Take another photo'),
            onPressed: () =>
                Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const CaptureScreen())),
          ),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Back to home')),
        ],
      ),
    );
  }
}
