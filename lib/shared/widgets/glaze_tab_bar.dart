import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'glass_surface.dart';
import 'swipe_tab_switcher.dart';

class GlazeTabItem {
  final String label;
  final IconData icon;

  const GlazeTabItem({required this.label, required this.icon});
}

class GlazeTabBar extends StatefulWidget {
  final List<GlazeTabItem> tabs;
  final int activeIndex;
  final ValueChanged<int> onChanged;

  const GlazeTabBar({
    super.key,
    required this.tabs,
    required this.activeIndex,
    required this.onChanged,
  });

  @override
  State<GlazeTabBar> createState() => _GlazeTabBarState();
}

class _GlazeTabBarState extends State<GlazeTabBar> {
  // Accumulated horizontal travel for a swipe performed directly on the strip.
  double _swipeDistance = 0;

  void _handleSwipeEnd(double velocity) {
    final target = resolveSwipeTarget(
      index: widget.activeIndex,
      length: widget.tabs.length,
      distance: _swipeDistance,
      velocity: velocity,
    );
    if (target != null) widget.onChanged(target);
  }

  @override
  Widget build(BuildContext context) {
    final tabs = widget.tabs;
    final activeIndex = widget.activeIndex;

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        final tabWidth = totalWidth / tabs.length;
        final radius = BorderRadius.circular(21);

        return GestureDetector(
          // Swiping on the strip itself flips the tab. Per-tab taps use tap
          // recognizers, which don't compete with this horizontal drag.
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (_) => _swipeDistance = 0,
          onHorizontalDragUpdate: (d) => _swipeDistance += d.delta.dx,
          onHorizontalDragEnd: (d) => _handleSwipeEnd(d.primaryVelocity ?? 0),
          child: SizedBox(
            height: 42,
            child: GlassSurface(
              borderRadius: radius,
              tint: context.cs.surface,
              border:
                  Border.all(color: context.cs.primary.withValues(alpha: 0.18)),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOutCubic,
                    left: activeIndex * tabWidth,
                    top: 3,
                    bottom: 3,
                    width: tabWidth,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: GlassSurface(
                        borderRadius: BorderRadius.circular(18),
                        tint: context.cs.primary,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.14),
                        ),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: Row(
                      children: List.generate(tabs.length, (index) {
                        final tab = tabs[index];
                        final isActive = index == activeIndex;
                        final color =
                            isActive ? Colors.white : context.cs.primary;

                        return Expanded(
                          child: GestureDetector(
                            onTap: () => widget.onChanged(index),
                            behavior: HitTestBehavior.opaque,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(tab.icon, size: 18, color: color),
                                const SizedBox(width: 8),
                                Text(
                                  tab.label,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: color,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
