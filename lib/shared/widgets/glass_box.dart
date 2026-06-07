import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/settings/app_settings_provider.dart';

class GlassBox extends ConsumerWidget {
  final double sigma;
  final Color color;
  final double borderRadius;
  final BorderRadius? borderRadiusOnly;
  final Widget child;
  final Border? border;
  final BoxShape shape;

  const GlassBox({
    super.key,
    this.sigma = 20,
    required this.color,
    this.borderRadius = 0,
    this.borderRadiusOnly,
    this.border,
    this.shape = BoxShape.rectangle,
    required this.child,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final batterySaver =
        ref.watch(appSettingsProvider).value?.batterySaver ?? false;
    final br =
        borderRadiusOnly ??
        (borderRadius > 0
            ? BorderRadius.circular(borderRadius)
            : BorderRadius.zero);

    if (batterySaver) {
      return Container(
        decoration: BoxDecoration(
          color: color,
          borderRadius: shape == BoxShape.rectangle ? br : null,
          shape: shape,
          border: border,
        ),
        child: child,
      );
    }

    final Widget clipped = ClipRRect(
      borderRadius: shape == BoxShape.rectangle ? br : BorderRadius.zero,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: Container(
          decoration: BoxDecoration(
            color: color,
            borderRadius: shape == BoxShape.rectangle ? br : null,
            shape: shape,
            border: border,
          ),
          child: child,
        ),
      ),
    );

    if (shape == BoxShape.circle) {
      return ClipOval(child: clipped);
    }
    return clipped;
  }
}
