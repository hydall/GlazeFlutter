import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../features/settings/app_settings_provider.dart';
import '../shell/nav_height_provider.dart';
import '../theme/app_colors.dart';
import 'glow_ripple.dart';

String _iconSvg(String path) =>
    '<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path d="$path"/></svg>';

class GlassNavBar extends ConsumerStatefulWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const GlassNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  ConsumerState<GlassNavBar> createState() => _GlassNavBarState();
}

class _GlassNavBarState extends ConsumerState<GlassNavBar> {
  final _key = GlobalKey();

  static const _items = [
    _NavItem(
      label: 'Chats',
      svgPath:
          'M20 2H4c-1.1 0-2 .9-2 2v18l4-4h14c1.1 0 2-.9 2-2V4c0-1.1-.9-2-2-2z',
    ),
    _NavItem(
      label: 'Characters',
      svgPath:
          'M12 12c2.21 0 4-1.79 4-4s-1.79-4-4-4-4 1.79-4 4 1.79 4 4 4zm0 2c-2.67 0-8 1.34-8 4v2h16v-2c0-2.66-5.33-4-8-4z',
    ),
    _NavItem(
      label: 'Tools',
      svgPath:
          'm21.71 20.29l-1.42 1.42a1 1 0 0 1-1.41 0L7 9.85A3.81 3.81 0 0 1 6 10a4 4 0 0 1-3.78-5.3l2.54 2.54l.53-.53l1.42-1.42l.53-.53L4.7 2.22A4 4 0 0 1 10 6a3.81 3.81 0 0 1-.15 1l11.86 11.88a1 1 0 0 1 0 1.41M2.29 18.88a1 1 0 0 0 0 1.41l1.42 1.42a1 1 0 0 0 1.41 0l5.47-5.46l-2.83-2.83M20 2l-4 2v2l-2.17 2.17l2 2L18 8h2l2-4Z',
    ),
    _NavItem(
      label: 'Menu',
      svgPath: 'M3 18h18v-2H3v2zm0-5h18v-2H3v2zm0-7v2h18V6H3z',
    ),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  void _measure() {
    final box = _key.currentContext?.findRenderObject() as RenderBox?;
    if (box != null && mounted) {
      ref.read(navHeightProvider.notifier).state = box.size.height;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    final batterySaver = ref.watch(appSettingsProvider).valueOrNull?.batterySaver ?? false;

    final navContent = Container(
      decoration: BoxDecoration(
        color: context.cs.surfaceContainerHighest.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.cs.outlineVariant),
      ),
      child: batterySaver
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: List.generate(
                  _items.length,
                  (i) => _NavButton(
                    item: _items[i],
                    isActive: i == widget.currentIndex,
                    onTap: () => widget.onTap(i),
                  ),
                ),
              ),
            )
          : GlowRippleOverlay(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Opacity(
                      opacity: 0.03,
                      child: CustomPaint(painter: _NoisePainter()),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: List.generate(
                        _items.length,
                        (i) => _NavButton(
                          item: _items[i],
                          isActive: i == widget.currentIndex,
                          onTap: () => widget.onTap(i),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );

    return Padding(
      key: _key,
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottomPad),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: batterySaver
            ? navContent
            : BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: navContent,
              ),
      ),
    );
  }
}

class _NoisePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final random = Random(42);
    final paint = Paint()..color = Colors.white;
    for (int i = 0; i < 800; i++) {
      final x = random.nextDouble() * size.width;
      final y = random.nextDouble() * size.height;
      canvas.drawRect(Rect.fromLTWH(x, y, 1, 1), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _NavItem {
  final String label;
  final String svgPath;

  const _NavItem({required this.label, required this.svgPath});
}

class _NavButton extends StatelessWidget {
  final _NavItem item;
  final bool isActive;
  final VoidCallback onTap;

  const _NavButton({
    required this.item,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final target = isActive ? 1.0 : 0.0;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: target, end: target),
        duration: const Duration(milliseconds: 125),
        curve: Curves.easeInOut,
        builder: (context, t, _) {
          final inactive = context.cs.onSurfaceVariant;
          final active = context.colors.accent;
          final inactiveLum = inactive.computeLuminance();
          final activeLum = active.computeLuminance();
          final surfaceLum = context.cs.surface.computeLuminance();
          final effectiveActive = (activeLum > surfaceLum) == (inactiveLum > surfaceLum)
              ? active
              : (surfaceLum < 0.5
                  ? HSLColor.fromColor(active).withLightness((HSLColor.fromColor(active).lightness + 0.3).clamp(0.0, 1.0)).toColor()
                  : HSLColor.fromColor(active).withLightness((HSLColor.fromColor(active).lightness - 0.3).clamp(0.0, 1.0)).toColor());
          final color =
              Color.lerp(inactive, effectiveActive, t)!;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SvgPicture.string(
                  _iconSvg(item.svgPath),
                  width: 28,
                  height: 28,
                  colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
                ),
                const SizedBox(height: 2),
                Text(
                  item.label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: color,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
