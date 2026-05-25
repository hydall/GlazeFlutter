import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/app_colors.dart';
import '../theme/theme_font_provider.dart';
import '../theme/theme_provider.dart';
import 'noise_overlay.dart';

class GlazeBackground extends ConsumerWidget {
  final Widget child;
  final Color? backgroundColor;

  const GlazeBackground({
    super.key,
    required this.child,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bytes = ref.watch(bgImageBytesProvider);
    final preset = ref.watch(themeProvider).activePreset;
    final base = backgroundColor ?? context.cs.surface;

    return Container(
      color: base,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (bytes != null)
            Positioned.fill(
              child: Opacity(
                opacity: preset.bgOpacity.clamp(0.0, 1.0),
                child: ImageFiltered(
                  imageFilter: preset.bgBlur > 0
                      ? ImageFilter.blur(
                          sigmaX: preset.bgBlur,
                          sigmaY: preset.bgBlur,
                          tileMode: TileMode.clamp,
                        )
                      : ImageFilter.blur(sigmaX: 0, sigmaY: 0),
                  child: Image.memory(
                    bytes,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                  ),
                ),
              ),
            ),
          if (preset.bgNoiseOpacity > 0)
            Positioned.fill(
              child: IgnorePointer(
                child: NoiseOverlay(
                  opacity: preset.bgNoiseOpacity,
                  intensity: preset.bgNoiseIntensity,
                ),
              ),
            ),
          child,
        ],
      ),
    );
  }
}
