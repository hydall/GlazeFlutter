import 'dart:math';
import 'dart:ui';

import 'package:flutter/widgets.dart';

class NoiseOverlay extends StatelessWidget {
  final double opacity;
  final double intensity;
  final Color tint;

  const NoiseOverlay({
    required this.opacity,
    required this.intensity,
    this.tint = const Color(0xFF000000),
  });

  @override
  Widget build(BuildContext context) {
    if (opacity <= 0) return const SizedBox.shrink();
    return CustomPaint(
      painter: _NoisePainter(intensity: intensity, tint: tint, opacity: opacity),
      size: Size.infinite,
    );
  }
}

class _NoisePainter extends CustomPainter {
  final double intensity;
  final Color tint;
  final double opacity;

  _NoisePainter({required this.intensity, required this.tint, required this.opacity});

  @override
  void paint(Canvas canvas, Size size) {
    final random = Random(42);
    final paint = Paint();
    final pixels = size.width * size.height;
    final step = (pixels / 50000).ceil().clamp(1, 10);

    for (var x = 0.0; x < size.width; x += step) {
      for (var y = 0.0; y < size.height; y += step) {
        final v = random.nextDouble();
        final alpha = (v * intensity * opacity * 255).round().clamp(0, 255);
        paint.color = tint.withValues(alpha: alpha / 255.0);
        canvas.drawRect(Rect.fromLTWH(x, y, step.toDouble(), step.toDouble()), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _NoisePainter old) =>
      intensity != old.intensity || tint != old.tint || opacity != old.opacity;
}
