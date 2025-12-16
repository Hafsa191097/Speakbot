import 'dart:math' as math;

import 'package:flutter/material.dart';

class GradientCirclePainter extends CustomPainter {
  final double animationValue;

  GradientCirclePainter(this.animationValue);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    for (int i = 0; i < 3; i++) {
      final layerRadius = radius - (i * 20);
      final rotation = (animationValue * 2 * math.pi) + (i * math.pi / 3);

      final rect = Rect.fromCircle(center: center, radius: layerRadius);

      final gradient = SweepGradient(
        colors: [
          Colors.pink.withOpacity(0.3),
          Colors.purple.withOpacity(0.3),
          Colors.blue.withOpacity(0.3),
          Colors.cyan.withOpacity(0.3),
          Colors.green.withOpacity(0.3),
          Colors.yellow.withOpacity(0.3),
          Colors.orange.withOpacity(0.3),
          Colors.pink.withOpacity(0.3),
        ],
        stops: const [0.0, 0.14, 0.28, 0.42, 0.56, 0.7, 0.84, 1.0],
        transform: GradientRotation(rotation),
      );

      final paint = Paint()
        ..shader = gradient.createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 + (i * 2);

      canvas.drawCircle(center, layerRadius, paint);
    }

    final glowPaint = Paint()
      ..color = Colors.white.withOpacity(0.8)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 30);
    canvas.drawCircle(center, 30, glowPaint);

    final centerPaint = Paint()..color = Colors.white;
    canvas.drawCircle(center, 25, centerPaint);
  }

  @override
  bool shouldRepaint(GradientCirclePainter oldDelegate) {
    return oldDelegate.animationValue != animationValue;
  }
}
