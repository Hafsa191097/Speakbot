import 'package:flutter/material.dart';
import 'package:voice_agent/widgets/gradient.dart';

class AnimatedGradientCircle extends StatefulWidget {
  const AnimatedGradientCircle({super.key});

  @override
  State<AnimatedGradientCircle> createState() => _AnimatedGradientCircleState();
}

class _AnimatedGradientCircleState extends State<AnimatedGradientCircle>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          size: const Size(250, 250),
          painter: GradientCirclePainter(_controller.value),
        );
      },
    );
  }
}
