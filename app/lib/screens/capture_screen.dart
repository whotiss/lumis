import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../image_tools.dart';
import 'questions_screen.dart';

/// Camera with a square framing guide and lighting tips, or a photo from the gallery (FR1, CP1 section 3.4.2).
/// A camera photo is cropped to the square, so what the person framed is what Lumis analyzes.
class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key});

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> with WidgetsBindingObserver {
  CameraController? _camera;
  String? _cameraError;
  bool _taking = false;
  Uint8List? _photo; // photo waiting for "Use this photo"
  bool _fromGallery = false;

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
    // Android takes the camera away when the app is in the background
    if (state == AppLifecycleState.inactive) {
      final c = _camera;
      _camera = null;
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
      final c = CameraController(back, ResolutionPreset.veryHigh,
          enableAudio: false, imageFormatGroup: ImageFormatGroup.jpeg);
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
    } on CameraException catch (e) {
      if (!mounted) return;
      setState(() => _cameraError = e.code.contains('Denied')
          ? 'Lumis needs permission to use the camera. You can allow it in your phone settings, '
              'or choose a photo from your gallery.'
          : 'The camera could not start. You can choose a photo from your gallery instead.');
    }
  }

  Future<void> _take() async {
    final c = _camera;
    if (c == null || _taking) return;
    setState(() => _taking = true);
    try {
      final shot = await c.takePicture();
      final cropped = await cropToFrame(await shot.readAsBytes());
      if (mounted) {
        setState(() {
          _photo = cropped;
          _fromGallery = false;
        });
      }
    } on CameraException {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not take the photo. Try again.')));
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
    if (mounted) {
      setState(() {
        _photo = bytes;
        _fromGallery = true;
      });
    }
  }

  void _use() => Navigator.push(context, MaterialPageRoute(builder: (_) => QuestionsScreen(photo: _photo!)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(_photo == null ? 'Take a photo' : 'Check your photo'),
      ),
      body: SafeArea(child: _photo != null ? _review() : _viewfinder()),
    );
  }

  Widget _viewfinder() {
    final c = _camera;
    return Column(children: [
      const Padding(
        padding: EdgeInsets.fromLTRB(20, 4, 20, 12),
        child: Text(
          'Fill the square with the skin you are worried about. Use daylight or a bright room, '
          'hold the phone about 10 to 15 cm away and keep it steady.',
          style: TextStyle(color: Colors.white70),
          textAlign: TextAlign.center,
        ),
      ),
      Expanded(
        child: Center(
          child: _cameraError != null
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(_cameraError!, style: const TextStyle(color: Colors.white), textAlign: TextAlign.center),
                )
              : c == null || !c.value.isInitialized
                  ? const CircularProgressIndicator()
                  : CameraPreview(c, child: const _FrameGuide()),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          IconButton(
            tooltip: 'Choose from gallery',
            iconSize: 32,
            color: Colors.white,
            icon: const Icon(Icons.photo_library_outlined),
            onPressed: _pickFromGallery,
          ),
          Semantics(
            button: true,
            label: 'Take photo',
            child: GestureDetector(
              onTap: c == null ? null : _take,
              child: Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 4)),
                padding: const EdgeInsets.all(5),
                child: DecoratedBox(
                  decoration: BoxDecoration(shape: BoxShape.circle, color: _taking ? Colors.white38 : Colors.white),
                ),
              ),
            ),
          ),
          const SizedBox(width: 48),
        ]),
      ),
    ]);
  }

  Widget _review() {
    return Column(children: [
      Expanded(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.memory(_photo!)),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        child: Text(
          _fromGallery
              ? 'Lumis checks the whole photo. Is the skin in focus and does it fill most of the photo?'
              : 'Is the skin in focus and well lit?',
          style: const TextStyle(color: Colors.white70),
          textAlign: TextAlign.center,
        ),
      ),
      Padding(
        padding: const EdgeInsets.all(20),
        child: Row(children: [
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white54)),
              onPressed: () {
                setState(() => _photo = null);
                if (_camera == null) _startCamera();
              },
              child: const Text('Retake'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: FilledButton(onPressed: _use, child: const Text('Use this photo'))),
        ]),
      ),
    ]);
  }
}

/// The square guide over the camera preview; everything outside it is dimmed.
class _FrameGuide extends StatelessWidget {
  const _FrameGuide();

  @override
  Widget build(BuildContext context) => const CustomPaint(painter: _FramePainter(), child: SizedBox.expand());
}

class _FramePainter extends CustomPainter {
  const _FramePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final side = frameFraction * (size.width < size.height ? size.width : size.height);
    final square = Rect.fromCenter(center: size.center(Offset.zero), width: side, height: side);
    final outside = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      Path()..addRRect(RRect.fromRectAndRadius(square, const Radius.circular(12))),
    );
    canvas.drawPath(outside, Paint()..color = Colors.black.withValues(alpha: 0.45));
    canvas.drawRRect(
      RRect.fromRectAndRadius(square, const Radius.circular(12)),
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
