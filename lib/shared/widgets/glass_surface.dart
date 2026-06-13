import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/settings/app_settings_provider.dart';
import '../theme/app_colors.dart';
import '../theme/theme_preset.dart';
import '../theme/theme_provider.dart';
import 'glow_ripple.dart';
import 'noise_overlay.dart';

/// Reusable glassmorphic surface that reads `elementOpacity` / `elementBlur` /
/// `noiseOpacity` / `noiseIntensity` from the active theme preset.
///
/// Replaces ad-hoc `ClipRRect + BackdropFilter + Container(alpha 0.8)` blocks
/// that were scattered across app-bar/nav-bar/sheet/toast/menu surfaces with
/// hardcoded values.
class GlassSurface extends ConsumerWidget {
  final Widget child;
  final BorderRadius borderRadius;
  final Color? tint;
  final BoxBorder? border;
  final List<BoxShadow>? boxShadow;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool enableRipple;
  final Color? glowColor;
  final double rippleRadiusFactor;
  final double rippleIntensity;

  const GlassSurface({
    super.key,
    required this.child,
    required this.borderRadius,
    this.tint,
    this.border,
    this.boxShadow,
    this.onTap,
    this.onLongPress,
    this.enableRipple = false,
    this.glowColor,
    this.rippleRadiusFactor = 1.0,
    this.rippleIntensity = 0.15,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preset = ref.watch(themeProvider).activePreset;
    final batterySaver =
        ref.watch(appSettingsProvider).value?.batterySaver ?? false;
    return _build(context, preset, batterySaver);
  }

  Widget _build(BuildContext context, ThemePreset preset, bool batterySaver) {
    final alpha = batterySaver ? 1.0 : preset.elementOpacity.clamp(0.0, 1.0);
    final blur = batterySaver ? 0.0 : preset.elementBlur;
    final defaultBase = Theme.of(context).colorScheme.surfaceContainerHighest;
    final effectiveTint = tint;
    final fillColor = effectiveTint == null
        ? defaultBase.withValues(alpha: alpha)
        : effectiveTint.withValues(
            alpha: (effectiveTint.a * alpha).clamp(0.0, 1.0),
          );

    final filled = DecoratedBox(
      decoration: BoxDecoration(
        color: fillColor,
        borderRadius: borderRadius,
        border: border,
        boxShadow: boxShadow,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: child,
      ),
    );

    final withNoise = !batterySaver && preset.noiseOpacity > 0
        ? Stack(
            fit: StackFit.passthrough,
            children: [
              filled,
              Positioned.fill(
                child: IgnorePointer(
                  child: ClipRRect(
                    borderRadius: borderRadius,
                    child: NoiseOverlay(
                      opacity: preset.noiseOpacity,
                      intensity: preset.noiseIntensity,
                    ),
                  ),
                ),
              ),
            ],
          )
        : filled;

    final surface = ClipRRect(
      borderRadius: borderRadius,
      child: blur > 0
          ? BackdropFilter(
              filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
              child: withNoise,
            )
          : withNoise,
    );

    final hasTapHandler = onTap != null || onLongPress != null;
    if (hasTapHandler) {
      return GlowInkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: borderRadius,
        glowColor: glowColor ?? context.cs.primary,
        radiusFactor: rippleRadiusFactor,
        intensity: rippleIntensity,
        child: surface,
      );
    }
    if (enableRipple) {
      return GlowRippleOverlay(
        glowColor: glowColor ?? context.cs.primary,
        radiusFactor: rippleRadiusFactor,
        intensity: rippleIntensity,
        child: surface,
      );
    }
    return surface;
  }
}
