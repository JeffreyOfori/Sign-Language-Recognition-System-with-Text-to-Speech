import 'dart:ui' show Size;

import 'package:camera/camera.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

class LandmarkFrame {
  LandmarkFrame({required this.poses, required this.imageSize, required this.rotation});
  final List<Pose> poses;
  final Size imageSize;
  final InputImageRotation rotation;
}

class LandmarkService {
  final PoseDetector _detector = PoseDetector(
    options: PoseDetectorOptions(
      mode: PoseDetectionMode.stream,
      model: PoseDetectionModel.base,
    ),
  );

  bool _busy = false;

  Future<LandmarkFrame?> detect(CameraImage image, CameraDescription camera) async {
    if (_busy) return null;
    _busy = true;
    try {
      final input = _toInputImage(image, camera);
      if (input == null) return null;
      final poses = await _detector.processImage(input);
      return LandmarkFrame(
        poses: poses,
        imageSize: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: input.metadata!.rotation,
      );
    } catch (_) {
      return null;
    } finally {
      _busy = false;
    }
  }

  InputImage? _toInputImage(CameraImage image, CameraDescription camera) {
    final rotation = InputImageRotationValue.fromRawValue(camera.sensorOrientation);
    if (rotation == null) return null;

    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null) return null;

    if (image.planes.isEmpty) return null;
    final plane = image.planes.first;

    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  Future<void> dispose() => _detector.close();
}
