import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class GlazeTabItem {
  final String label;
  final IconData icon;

  const GlazeTabItem({required this.label, required this.icon});
}

class GlazeTabBar extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        final tabWidth = totalWidth / tabs.length;

        return Container(
          height: 42,
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(21),
            border: Border.all(color: AppColors.accent.withValues(alpha: 0.2)),
          ),
          child: Stack(
            children: [
              // Sliding active background
              AnimatedPositioned(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                left: activeIndex * tabWidth,
                top: 0,
                bottom: 0,
                width: tabWidth,
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(21),
                  ),
                ),
              ),
              // Tab buttons
              Positioned.fill(
                child: Row(
                  children: List.generate(tabs.length, (index) {
                    final tab = tabs[index];
                    final isActive = index == activeIndex;
                    final color = isActive ? Colors.white : AppColors.accent;

                    return Expanded(
                      child: GestureDetector(
                        onTap: () => onChanged(index),
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
        );
      },
    );
  }
}
