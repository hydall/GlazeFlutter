import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class GlazeBackground extends StatefulWidget {
  final Widget child;
  final Color? backgroundColor;
  final double noiseOpacity;

  const GlazeBackground({
    super.key,
    required this.child,
    this.backgroundColor,
    this.noiseOpacity = 0.05, // Matching Vue's 0.05 opacity
  });

  @override
  State<GlazeBackground> createState() => _GlazeBackgroundState();
}

class _GlazeBackgroundState extends State<GlazeBackground> {
  @override
  Widget build(BuildContext context) {
    return Container(color: widget.backgroundColor ?? context.colors.background, child: widget.child);
  }
}
