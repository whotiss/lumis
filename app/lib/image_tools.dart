import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Share of the shorter side covered by the on-screen framing square. The capture screen draws the square with
/// the same number, so what the person framed is what gets analyzed.
const double frameFraction = 0.8;

/// Longest side sent to the server. The model works at 448 px and Claude at 1024 px, so more only slows the upload.
const int maxUploadEdge = 1280;

/// Camera photo -> the part inside the framing square, upright, as JPEG. Runs off the UI thread.
Future<Uint8List> cropToFrame(Uint8List jpeg) => compute(_cropToFrame, jpeg);

Uint8List _cropToFrame(Uint8List jpeg) {
  final decoded = img.decodeImage(jpeg);
  if (decoded == null) return jpeg;
  final upright = img.bakeOrientation(decoded); // phones often store the pixels sideways
  final side = (frameFraction * (upright.width < upright.height ? upright.width : upright.height)).round();
  var square = img.copyCrop(upright,
      x: (upright.width - side) ~/ 2, y: (upright.height - side) ~/ 2, width: side, height: side);
  if (side > maxUploadEdge) square = img.copyResize(square, width: maxUploadEdge, height: maxUploadEdge);
  return Uint8List.fromList(img.encodeJpg(square, quality: 90));
}
