import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../image_tools.dart';
import '../photo_check.dart';
import '../theme.dart';
import '../widgets.dart';
import 'questions_screen.dart';

/// Camera with a square framing guide, lighting tips and a live light/steadiness check, or a photo from the
/// gallery (FR1, CP1 section 3.4.2). A camera photo is cropped to the square, so what the person framed is what
/// Lumis analyzes. Always dark, like a camera app, whatever the app's theme.
class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key});

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> with WidgetsBindingObserver {
  static const _night = Color(0xFF07080F);
  static const _moon = Color(0xFFF3EFE6);
  static const _lavender = Color(0xFFC9C6FF);

  CameraController? _camera;
  String? _cameraError;
  bool _taking = false;
  Uint8List? _photo; // photo waiting for "Use this photo"
  bool _fromGallery = false;
  final _checker = LiveChecker();
  LiveCheck _check = const LiveCheck();
  bool _streaming = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _camera?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // the phone takes the camera away when the app is in the background
    if (state == AppLifecycleState.inactive) {
      final c = _camera;
      _camera = null;
      _streaming = false;
      c?.dispose();
      if (mounted) setState(() {});
    } else if (state == AppLifecycleState.resumed && _camera == null && _photo == null) {
      _startCamera();
    }
  }

  Future<void> _startCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw CameraException('none', 'No camera found');
      final back = cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.back, orElse: () => cameras.first);
      // The preview frames are read for the light check; the photo itself is always saved as JPEG.
      final c = CameraController(back, ResolutionPreset.veryHigh,
          enableAudio: false,
          imageFormatGroup: Platform.isIOS ? ImageFormatGroup.bgra8888 : ImageFormatGroup.yuv420);
      await c.initialize();
      await c.setFlashMode(FlashMode.off); // flash causes glare on skin
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() {
        _camera = c;
        _cameraError = null;
      });
      await _startCheck();
    } on CameraException catch (e) {
      if (!mounted) return;
      setState(() => _cameraError = e.code.contains('Denied')
          ? 'Lumis needs permission to use the camera. You can allow it in your phone settings, '
              'or choose a photo from your gallery.'
          : 'The camera could not start. You can choose a photo from your gallery instead.');
    }
  }

  Future<void> _startCheck() async {
    final c = _camera;
    if (c == null || _streaming) return;
    try {
      await c.startImageStream((image) {
        final r = _checker.analyze(image, frameFraction: frameFraction);
        if (r != null && mounted && (r.light != _check.light || r.steady != _check.steady)) {
          setState(() => _check = r);
        }
      });
      _streaming = true;
    } on CameraException {
      _streaming = false; // the check is a help, not a requirement: the camera still works without it
    }
  }

  Future<void> _stopCheck() async {
    final c = _camera;
    if (c == null || !_streaming) return;
    _streaming = false;
    try {
      await c.stopImageStream();
    } on CameraException {
      // already stopped
    }
  }

  Future<void> _take() async {
    final c = _camera;
    if (c == null || _taking) return;
    setState(() => _taking = true);
    try {
      await _stopCheck(); // some phones can't stream and take a photo at the same time
      final shot = await c.takePicture();
      final cropped = await cropToFrame(await shot.readAsBytes());
      if (mounted) {
        setState(() {
          _photo = cropped;
          _fromGallery = false;
        });
      }
    } on CameraException {
      if (mounted) showMessage(context, 'Could not take the photo. Try again.');
      await _startCheck();
    } finally {
      if (mounted) setState(() => _taking = false);
    }
  }

  Future<void> _pickFromGallery() async {
    final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: maxUploadEdge.toDouble(),
        maxHeight: maxUploadEdge.toDouble(),
        imageQuality: 90);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    await _stopCheck();
    if (mounted) {
      setState(() {
        _photo = bytes;
        _fromGallery = true;
      });
    }
  }

  void _retake() {
    setState(() => _photo = null);
    if (_camera == null) {
      _startCamera();
    } else {
      _startCheck();
    }
  }

  void _use() => Navigator.push(context, MaterialPageRoute(builder: (_) => QuestionsScreen(photo: _photo!)));

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: lumisTheme(Brightness.dark),
      child: Scaffold(
        backgroundColor: _night,
        body: SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: Row(children: [
                SquareIconButton(
                    icon: Icons.close_rounded, tooltip: 'Close', onPressed: () => Navigator.of(context).maybePop()),
                Expanded(
                  child: Center(child: SectionLabel(_photo == null ? 'Take a photo' : 'Check your photo')),
                ),
                const SizedBox(width: 44),
              ]),
            ),
            Expanded(child: _photo != null ? _review() : _viewfinder()),
          ]),
        ),
      ),
    );
  }

  Widget _viewfinder() {
    final c = _camera;
    final hint = _check.hint;
    return Column(children: [
      Expanded(
        child: Center(
          child: _cameraError != null
              ? Padding(
                  padding: const EdgeInsets.all(28),
                  child: Text(_cameraError!, style: const TextStyle(color: _moon), textAlign: TextAlign.center),
                )
              : c == null || !c.value.isInitialized
                  ? const CircularProgressIndicator(color: _lavender)
                  : CameraPreview(
                      c,
                      child: LayoutBuilder(builder: (context, box) {
                        final side = frameFraction * box.biggest.shortestSide;
                        final top = (box.maxHeight - side) / 2;
                        return Stack(children: [
                          const Positioned.fill(child: CustomPaint(painter: _FramePainter())),
                          if (_streaming && hint != null)
                            Positioned(
                              left: 0,
                              right: 0,
                              top: (top - 50).clamp(8.0, double.infinity),
                              child: Center(child: _HintChip(hint)),
                            ),
                          if (_streaming)
                            Positioned(
                              left: 0,
                              right: 0,
                              top: top + side + 12,
                              child: _StatusRow(_check),
                            ),
                        ]);
                      }),
                    ),
        ),
      ),
      const Padding(padding: EdgeInsets.fromLTRB(20, 14, 20, 0), child: _Tips()),
      Padding(
        padding: const EdgeInsets.fromLTRB(40, 20, 40, 24),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          SizedBox.square(
            dimension: 52,
            child: SquareIconButton(
                icon: Icons.photo_library_outlined, tooltip: 'Choose from gallery', onPressed: _pickFromGallery),
          ),
          Semantics(
            button: true,
            label: 'Take photo',
            child: GestureDetector(
              onTap: c == null ? null : _take,
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: _moon, width: 3)),
                padding: const EdgeInsets.all(5),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                        begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.white, Color(0xFFE3E0FF)]),
                    boxShadow: [BoxShadow(color: _lavender.withValues(alpha: _taking ? 0.2 : 0.55), blurRadius: 24)],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 52),
        ]),
      ),
    ]);
  }

  Widget _review() {
    return Column(children: [
      Expanded(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.memory(_photo!)),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
        child: Text(
          _fromGallery
              ? 'Lumis checks the whole photo. Is the skin in focus and does it fill most of the photo?'
              : 'Is the skin in focus and well lit?',
          style: TextStyle(color: _moon.withValues(alpha: 0.75), fontWeight: FontWeight.w300),
          textAlign: TextAlign.center,
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Row(children: [
          Expanded(child: LumisButton.secondary(label: 'Retake', onPressed: _retake)),
          const SizedBox(width: 12),
          Expanded(child: LumisButton(label: 'Use this photo', onPressed: _use, height: 50)),
        ]),
      ),
    ]);
  }
}

class _HintChip extends StatelessWidget {
  const _HintChip(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    const warn = Color(0xFFFFD98A);
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: const Color(0xC70F1022),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: warn.withValues(alpha: 0.45)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.wb_sunny_outlined, size: 16, color: warn),
          const SizedBox(width: 10),
          Text(text, style: const TextStyle(fontSize: 13, color: Color(0xFFF3EFE6))),
        ]),
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow(this.check);
  final LiveCheck check;

  @override
  Widget build(BuildContext context) {
    Widget chip(String label, bool ok) {
      const lav = Color(0xFFC9C6FF), warn = Color(0xFFFFD98A);
      final c = ok ? lav : warn;
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(6)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(ok ? Icons.check_rounded : Icons.priority_high_rounded, size: 13, color: c),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(fontSize: 12, color: ok ? const Color(0xFFDCDAF5) : const Color(0xFFFFE7B8))),
        ]),
      );
    }

    final light = switch (check.light) {
      LightLevel.ok => chip('Good light', true),
      LightLevel.dark => chip('Too dark', false),
      LightLevel.bright => chip('Too bright', false),
    };
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      light,
      chip(check.steady ? 'Steady' : 'Moving', check.steady),
    ]);
  }
}

class _Tips extends StatelessWidget {
  const _Tips();

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(fontSize: 13, fontWeight: FontWeight.w300, color: Color(0xFFF3EFE6));
    Widget tip(IconData icon, String text) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Icon(icon, size: 16, color: const Color(0xFFC9C6FF)),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: style)),
          ]),
        );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xB80F1022),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Column(children: [
        tip(Icons.crop_square_rounded, 'Fill the square with the skin you are worried about'),
        tip(Icons.wb_sunny_outlined, 'Daylight or a bright room, no flash'),
        tip(Icons.open_in_full_rounded, 'About 10 to 15 cm away, hold steady'),
      ]),
    );
  }
}

/// The square guide over the camera preview: everything outside it is dimmed, with lavender corner marks.
class _FramePainter extends CustomPainter {
  const _FramePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final side = frameFraction * size.shortestSide;
    final square = Rect.fromCenter(center: size.center(Offset.zero), width: side, height: side);
    final rr = RRect.fromRectAndRadius(square, const Radius.circular(6));
    canvas.drawPath(
      Path.combine(PathOperation.difference, Path()..addRect(Offset.zero & size), Path()..addRRect(rr)),
      Paint()..color = const Color(0x8C07080F),
    );
    canvas.drawRRect(
      rr,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    final corner = Paint()
      ..color = const Color(0xFFC9C6FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    const l = 26.0;
    final r = square;
    canvas.drawPath(Path()..moveTo(r.left, r.top + l)..lineTo(r.left, r.top)..lineTo(r.left + l, r.top), corner);
    canvas.drawPath(Path()..moveTo(r.right - l, r.top)..lineTo(r.right, r.top)..lineTo(r.right, r.top + l), corner);
    canvas.drawPath(
        Path()..moveTo(r.left, r.bottom - l)..lineTo(r.left, r.bottom)..lineTo(r.left + l, r.bottom), corner);
    canvas.drawPath(
        Path()..moveTo(r.right - l, r.bottom)..lineTo(r.right, r.bottom)..lineTo(r.right, r.bottom - l), corner);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
