import 'package:flutter/material.dart';
import 'package:soft_edge_blur/soft_edge_blur.dart';

import '../../../shared/theme/app_colors.dart';

/// Shared shell for bottom slide-up panels (Magic Drawer, Quick Replies).
/// Provides background, drag handle, top soft-edge blur, header slot,
/// and an optional loading overlay.
///
/// Background is hardcoded to a dark neutral so the panel always looks correct
/// regardless of the active theme's charBubbleColor (light themes would
/// otherwise produce a white/light background here).
class DrawerPanelScaffold extends StatelessWidget {
  final Widget content;
  final Widget? header;
  final bool loading;
  final bool disableEffects;

  const DrawerPanelScaffold({
    super.key,
    required this.content,
    this.header,
    this.loading = false,
    this.disableEffects = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        border: Border(top: BorderSide(color: context.cs.outlineVariant)),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: disableEffects
                ? content
                : SoftEdgeBlur(
                    edges: [
                      EdgeBlur(
                        type: EdgeType.topEdge,
                        size: 68,
                        sigma: 24,
                        tintColor: context.cs.surface.withValues(alpha: 0.4),
                        controlPoints: [
                          ControlPoint(
                            position: 0.5,
                            type: ControlPointType.visible,
                          ),
                          ControlPoint(
                            position: 1.0,
                            type: ControlPointType.transparent,
                          ),
                        ],
                      ),
                    ],
                    child: content,
                  ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Center(
                  child: Container(
                    width: 32,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[600],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (header != null)
            Positioned(top: 0, left: 0, right: 0, child: header!),
          if (loading)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x22000000),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }
}
