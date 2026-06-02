import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

class NoiseOverlay extends StatefulWidget {
  final double opacity;
  final double intensity;
  final Color tint;

  const NoiseOverlay({
    super.key,
    required this.opacity,
    required this.intensity,
    this.tint = const Color(0xFF000000),
  });

  @override
  State<NoiseOverlay> createState() => _NoiseOverlayState();
}

class _NoiseOverlayState extends State<NoiseOverlay> {
  ui.Image? _cachedImage;
  Size? _cachedSize;

  @override
  void didUpdateWidget(NoiseOverlay old) {
    super.didUpdateWidget(old);
    if (old.intensity != widget.intensity ||
        old.tint != widget.tint ||
        old.opacity != widget.opacity) {
      _cachedImage?.dispose();
      _cachedImage = null;
      _cachedSize = null;
    }
  }

  @override
  void dispose() {
    _cachedImage?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.opacity <= 0) return const SizedBox.shrink();
    return CustomPaint(
      painter: _CachedNoisePainter(
        intensity: widget.intensity,
        tint: widget.tint,
        opacity: widget.opacity,
        getCachedImage: () => _cachedImage,
        setCachedImage: (img, size) {
          if (_cachedImage != img) {
            _cachedImage?.dispose();
            _cachedImage = img;
            _cachedSize = size;
          }
        },
        getCachedSize: () => _cachedSize,
      ),
      size: Size.infinite,
    );
  }
}

class _CachedNoisePainter extends CustomPainter {
  final double intensity;
  final Color tint;
  final double opacity;
  final ui.Image? Function() getCachedImage;
  final void Function(ui.Image, Size) setCachedImage;
  final Size? Function() getCachedSize;

  _CachedNoisePainter({
    required this.intensity,
    required this.tint,
    required this.opacity,
    required this.getCachedImage,
    required this.setCachedImage,
    required this.getCachedSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cached = getCachedImage();
    final cachedSize = getCachedSize();
    if (cached != null && cachedSize == size) {
      canvas.drawImage(cached, Offset.zero, Paint());
      return;
    }

    final recorder = ui.PictureRecorder();
    final offscreen = Canvas(recorder);
    final random = Random(42);
    final paint = Paint();
    final pixels = size.width * size.height;
    final step = (pixels / 50000).ceil().clamp(1, 10);

    for (var x = 0.0; x < size.width; x += step) {
      for (var y = 0.0; y < size.height; y += step) {
        final v = random.nextDouble();
        final alpha = (v * intensity * opacity * 255).round().clamp(0, 255);
        paint.color = tint.withValues(alpha: alpha / 255.0);
        offscreen.drawRect(
          Rect.fromLTWH(x, y, step.toDouble(), step.toDouble()),
          paint,
        );
      }
    }

    final picture = recorder.endRecording();
    picture.toImage(size.width.toInt(), size.height.toInt()).then((img) {
      setCachedImage(img, size);
    });

    canvas.drawPicture(picture);
  }

  @override
  bool shouldRepaint(covariant _CachedNoisePainter old) =>
      intensity != old.intensity || tint != old.tint || opacity != old.opacity;
}
