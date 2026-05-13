import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../theme.dart';

class PosePainter extends CustomPainter {
  PosePainter({
    required this.poses,
    required this.imageSize,
    required this.rotation,
    required this.cameraLensDirection,
  });

  final List<Pose> poses;
  final Size imageSize;
  final InputImageRotation rotation;
  final CameraLensDirection cameraLensDirection;

  static const _connections = <List<PoseLandmarkType>>[
    [PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder],
    [PoseLandmarkType.leftShoulder, PoseLandmarkType.leftElbow],
    [PoseLandmarkType.leftElbow, PoseLandmarkType.leftWrist],
    [PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow],
    [PoseLandmarkType.rightElbow, PoseLandmarkType.rightWrist],
    [PoseLandmarkType.leftWrist, PoseLandmarkType.leftIndex],
    [PoseLandmarkType.leftWrist, PoseLandmarkType.leftPinky],
    [PoseLandmarkType.leftWrist, PoseLandmarkType.leftThumb],
    [PoseLandmarkType.rightWrist, PoseLandmarkType.rightIndex],
    [PoseLandmarkType.rightWrist, PoseLandmarkType.rightPinky],
    [PoseLandmarkType.rightWrist, PoseLandmarkType.rightThumb],
  ];

  static const _handJoints = <PoseLandmarkType>{
    PoseLandmarkType.leftWrist,
    PoseLandmarkType.rightWrist,
    PoseLandmarkType.leftIndex,
    PoseLandmarkType.rightIndex,
    PoseLandmarkType.leftPinky,
    PoseLandmarkType.rightPinky,
    PoseLandmarkType.leftThumb,
    PoseLandmarkType.rightThumb,
  };

  @override
  void paint(Canvas canvas, Size size) {
    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..color = AppColors.accent.withValues(alpha: 0.18)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = AppColors.accent.withValues(alpha: 0.95);

    final bodyPoint = Paint()
      ..style = PaintingStyle.fill
      ..color = AppColors.accentSoft;

    final handPoint = Paint()
      ..style = PaintingStyle.fill
      ..color = AppColors.success;

    final handGlow = Paint()
      ..style = PaintingStyle.fill
      ..color = AppColors.success.withValues(alpha: 0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

    for (final pose in poses) {
      for (final pair in _connections) {
        final a = pose.landmarks[pair[0]];
        final b = pose.landmarks[pair[1]];
        if (a == null || b == null) continue;
        final p1 = _project(a.x, a.y, size);
        final p2 = _project(b.x, b.y, size);
        canvas.drawLine(p1, p2, glowPaint);
        canvas.drawLine(p1, p2, linePaint);
      }
      for (final entry in pose.landmarks.entries) {
        final pt = _project(entry.value.x, entry.value.y, size);
        if (_handJoints.contains(entry.key)) {
          canvas.drawCircle(pt, 10, handGlow);
          canvas.drawCircle(pt, 5, handPoint);
        } else {
          canvas.drawCircle(pt, 4, bodyPoint);
        }
      }
    }
  }

  Offset _project(double x, double y, Size widget) {
    double sx;
    double sy;
    switch (rotation) {
      case InputImageRotation.rotation90deg:
        sx = widget.width * (y / imageSize.height);
        sy = widget.height * (x / imageSize.width);
        if (cameraLensDirection == CameraLensDirection.front) {
          sx = widget.width - sx;
        }
        break;
      case InputImageRotation.rotation270deg:
        sx = widget.width * (1 - y / imageSize.height);
        sy = widget.height * (1 - x / imageSize.width);
        if (cameraLensDirection == CameraLensDirection.front) {
          sx = widget.width - sx;
        }
        break;
      case InputImageRotation.rotation0deg:
      case InputImageRotation.rotation180deg:
        sx = widget.width * (x / imageSize.width);
        sy = widget.height * (y / imageSize.height);
        break;
    }
    return Offset(sx, sy);
  }

  @override
  bool shouldRepaint(covariant PosePainter old) =>
      old.poses != poses || old.imageSize != imageSize;
}
