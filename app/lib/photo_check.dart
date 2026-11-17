import 'dart:typed_data';

import 'package:camera/camera.dart';

/// What the live camera check thinks of the current view. Only light and movement are checked: both can be
/// measured reliably from the preview. Focus is not, because healthy-looking skin has little texture and would
/// often be called blurry.
enum LightLevel { ok, dark, bright }

class LiveCheck {
  const LiveCheck({this.light = LightLevel.ok, this.steady = true});
  final LightLevel light;
  final bool steady;

  bool get good => light == LightLevel.ok && steady;

  /// The one hint to show above the frame, or null when everything is fine.
  String? get hint => switch (light) {
        LightLevel.dark => 'A bit dark. Move to brighter light.',
        LightLevel.bright => 'Too bright. Avoid direct sun or flash glare.',
        LightLevel.ok => steady ? null : 'Hold the phone still.',
      };
}

/// Reads camera preview frames (a few per second) and reports light and movement for the centre square.
/// Thresholds are first guesses on a 0 to 255 brightness scale; adjust after testing on real phones.
class LiveChecker {
  static const darkBelow = 70.0;
  static const brightAbove = 235.0;
  static const movingAbove = 18.0; // average change per sample point between two frames
  static const _grid = 24;

  Float64List? _previous;
  DateTime _lastRun = DateTime.fromMillisecondsSinceEpoch(0);

  /// Returns a new result about every 400 ms, otherwise null (the frame is skipped).
  LiveCheck? analyze(CameraImage image, {double frameFraction = 0.8}) {
    final now = DateTime.now();
    if (now.difference(_lastRun) < const Duration(milliseconds: 400)) return null;
    _lastRun = now;
    final samples = _sample(image, frameFraction);
    if (samples == null) return null;
    var sum = 0.0;
    for (final v in samples) {
      sum += v;
    }
    final mean = sum / samples.length;
    var steady = true;
    final prev = _previous;
    if (prev != null && prev.length == samples.length) {
      var diff = 0.0;
      for (var i = 0; i < samples.length; i++) {
        diff += (samples[i] - prev[i]).abs();
      }
      steady = diff / samples.length < movingAbove;
    }
    _previous = samples;
    final light = mean < darkBelow
        ? LightLevel.dark
        : mean > brightAbove
            ? LightLevel.bright
            : LightLevel.ok;
    return LiveCheck(light: light, steady: steady);
  }

  /// Brightness at a 24 × 24 grid of points inside the centre square.
  Float64List? _sample(CameraImage image, double frameFraction) {
    if (image.planes.isEmpty) return null;
    final plane = image.planes.first;
    final bytes = plane.bytes;
    final w = image.width, h = image.height;
    final side = (frameFraction * (w < h ? w : h)).floor();
    final left = (w - side) ~/ 2, top = (h - side) ~/ 2;
    final bgra = image.format.group == ImageFormatGroup.bgra8888;
    final pixelStride = bgra ? 4 : (plane.bytesPerPixel ?? 1);
    final out = Float64List(_grid * _grid);
    var k = 0;
    for (var gy = 0; gy < _grid; gy++) {
      final y = top + (gy * side) ~/ _grid;
      for (var gx = 0; gx < _grid; gx++) {
        final x = left + (gx * side) ~/ _grid;
        final i = y * plane.bytesPerRow + x * pixelStride;
        if (i + (bgra ? 2 : 0) >= bytes.length) return null;
        out[k++] = bgra
            ? 0.114 * bytes[i] + 0.587 * bytes[i + 1] + 0.299 * bytes[i + 2] // B, G, R
            : bytes[i].toDouble(); // Y (luminance) plane of YUV 4:2:0
      }
    }
    return out;
  }
}
