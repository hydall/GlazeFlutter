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
  bool _generating = false;

  @override
  void didUpdateWidget(NoiseOverlay old) {
    super.didUpdateWidget(old);
    if (old.intensity != widget.intensity ||
        old.tint != widget.tint ||
        old.opacity != widget.opacity) {
      _cachedImage?.dispose();
      _cachedImage = null;
      _cachedSize = null;
      _generating = false;
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
        getCachedSize: () => _cachedSize,
        // True while an async raster is already in flight, so the synchronous
        // per-cell fallback path doesn't re-schedule a new toImage() every
        // frame before the first one resolves.
        isGenerating: () => _generating,
        beginGenerate: () => _generating = true,
        setCachedImage: (img, size) {
          if (!mounted) {
            img.dispose();
            return;
          }
          if (_cachedImage == img) return;
          // setState so the painter rebuilds and switches to the cheap
          // drawImage path; previously the cache was populated silently and the
          // expensive per-cell loop kept running on every repaint.
          setState(() {
            _cachedImage?.dispose();
            _cachedImage = img;
            _cachedSize = size;
            _generating = false;
          });
        },
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
  final bool Function() isGenerating;
  final void Function() beginGenerate;

  _CachedNoisePainter({
    required this.intensity,
    required this.tint,
    required this.opacity,
    required this.getCachedImage,
    required this.setCachedImage,
    required this.getCachedSize,
    required this.isGenerating,
    required this.beginGenerate,
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
    // Only schedule one raster at a time. Once it resolves the state setter
    // triggers a rebuild and subsequent paints take the cheap drawImage path.
    if (!isGenerating()) {
      beginGenerate();
      picture.toImage(size.width.toInt(), size.height.toInt()).then((img) {
        setCachedImage(img, size);
      });
    }

    canvas.drawPicture(picture);
  }

  @override
  bool shouldRepaint(covariant _CachedNoisePainter old) =>
      intensity != old.intensity || tint != old.tint || opacity != old.opacity;
}
