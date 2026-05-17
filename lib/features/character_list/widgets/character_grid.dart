import 'package:flutter/material.dart';
import '../../../core/models/character.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/widgets/glaze_bottom_sheet.dart';
import 'character_card.dart';

enum SortType { name, date }

enum SortDir { asc, desc }

class CharacterGrid extends StatelessWidget {
  final List<Character> characters;
  final SortType sortBy;
  final SortDir sortDir;
  final VoidCallback onSortDirToggle;
  final ValueChanged<SortType> onSortTypeChanged;
  final double topPadding;
  final double bottomPadding;
  final Widget? tabBar;
  final bool showOurPicksCard;
  final VoidCallback? onOurPicksTap;
  final VoidCallback? onOurPicksHide;

  const CharacterGrid({
    super.key,
    required this.characters,
    required this.sortBy,
    required this.sortDir,
    required this.onSortDirToggle,
    required this.onSortTypeChanged,
    this.topPadding = 0,
    this.bottomPadding = 16,
    this.tabBar,
    this.showOurPicksCard = false,
    this.onOurPicksTap,
    this.onOurPicksHide,
  });

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        if (topPadding > 0)
          SliverToBoxAdapter(child: SizedBox(height: topPadding)),
        if (tabBar != null) SliverToBoxAdapter(child: tabBar!),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _SortDirButton(
                  isAsc: sortDir == SortDir.asc,
                  onTap: onSortDirToggle,
                ),
                const SizedBox(width: 10),
                _SortTypePill(sortBy: sortBy, onChanged: onSortTypeChanged),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
            child: Text(
              '${characters.length} character${characters.length == 1 ? '' : 's'}',
              style: TextStyle(
                fontSize: 11,
                color: context.cs.onSurfaceVariant,
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, bottomPadding),
          sliver: SliverToBoxAdapter(
            child: _AnimatedCharacterGrid(
              characters: characters,
              showOurPicksCard: showOurPicksCard,
              onOurPicksTap: onOurPicksTap,
              onOurPicksHide: onOurPicksHide,
            ),
          ),
        ),
      ],
    );
  }
}

class _SortDirButton extends StatelessWidget {
  final bool isAsc;
  final VoidCallback onTap;

  const _SortDirButton({required this.isAsc, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: context.cs.primary.withValues(alpha: 0.15),
          shape: BoxShape.circle,
          border: Border.all(color: context.cs.primary.withValues(alpha: 0.2)),
        ),
        child: Center(
          child: AnimatedRotation(
            turns: isAsc ? 0.5 : 0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutBack,
            child: Icon(
              Icons.arrow_downward_rounded,
              size: 18,
              color: context.cs.primary,
            ),
          ),
        ),
      ),
    );
  }
}

class _AnimatedCharacterGrid extends StatelessWidget {
  final List<Character> characters;
  final bool showOurPicksCard;
  final VoidCallback? onOurPicksTap;
  final VoidCallback? onOurPicksHide;

  const _AnimatedCharacterGrid({
    required this.characters,
    required this.showOurPicksCard,
    this.onOurPicksTap,
    this.onOurPicksHide,
  });

  static const _crossAxisCount = 2;
  static const _spacing = 10.0;
  static const _aspectRatio = 2 / 3;

  @override
  Widget build(BuildContext context) {
    final totalCount = characters.length + (showOurPicksCard ? 1 : 0);
    if (totalCount == 0) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (ctx, constraints) {
        final cellW =
            (constraints.maxWidth - _spacing * (_crossAxisCount - 1)) /
                _crossAxisCount;
        final cellH = cellW / _aspectRatio;
        final rows =
            (totalCount + _crossAxisCount - 1) ~/ _crossAxisCount;
        final totalH = rows * cellH + (rows - 1) * _spacing;

        return SizedBox(
          height: totalH,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              if (showOurPicksCard)
                AnimatedPositioned(
                  key: const ValueKey('our_picks_card'),
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.easeOutCubic,
                  left: 0,
                  top: 0,
                  width: cellW,
                  height: cellH,
                  child: _OurPicksCard(
                    onTap: onOurPicksTap,
                    onHide: onOurPicksHide,
                  ),
                ),
              for (int i = 0; i < characters.length; i++)
                (() {
                  final gridIndex = i + (showOurPicksCard ? 1 : 0);
                  return AnimatedPositioned(
                    key: ValueKey(characters[i].id),
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeOutCubic,
                    left: (gridIndex % _crossAxisCount) * (cellW + _spacing),
                    top: (gridIndex ~/ _crossAxisCount) * (cellH + _spacing),
                    width: cellW,
                    height: cellH,
                    child: CharacterCard(character: characters[i]),
                  );
                })(),
            ],
          ),
        );
      },
    );
  }
}

class _OurPicksCard extends StatefulWidget {
  final VoidCallback? onTap;
  final VoidCallback? onHide;

  const _OurPicksCard({this.onTap, this.onHide});

  @override
  State<_OurPicksCard> createState() => _OurPicksCardState();
}

class _OurPicksCardState extends State<_OurPicksCard> {
  bool _pressed = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scale = _pressed ? 0.96 : (_hovered ? 1.01 : 1.0);
    final dy = _hovered && !_pressed ? -4.0 : 0.0;
    final shadowAlpha = _hovered ? 0.3 : 0.1;
    final shadowColor = Colors.black.withValues(alpha: shadowAlpha);

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      builder: (_, t, child) => Opacity(
        opacity: t,
        child: Transform.scale(
          scale: 0.9 + 0.1 * t,
          child: child,
        ),
      ),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutBack,
            transform: Matrix4.identity()
              ..translateByDouble(0.0, dy, 0.0, 1.0)
              ..scaleByDouble(scale, scale, 1.0, 1.0),
            transformAlignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: shadowColor,
                  blurRadius: _hovered ? 24 : 6,
                  offset: Offset(0, _hovered ? 12 : 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  AnimatedScale(
                    scale: _hovered ? 1.05 : 1.0,
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeOut,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            context.cs.primary,
                            context.cs.secondary,
                          ],
                        ),
                      ),
                      child: Center(
                        child: Icon(
                          Icons.star_rounded,
                          size: 72,
                          color: Colors.white.withValues(alpha: 0.25),
                        ),
                      ),
                    ),
                  ),
                  const Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    height: 150,
                    child: _OurPicksBottomGradient(),
                  ),
                  const Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: _OurPicksCardInfo(),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: _OurPicksCardMenuButton(
                      onTap: () {
                        GlazeBottomSheet.show(
                          context,
                          title: 'Our Picks',
                          items: [
                            BottomSheetItem(
                              icon: Icons.visibility_off_rounded,
                              label: 'Hide',
                              hint: 'можно вернуть из настроек приложения',
                              onTap: () {
                                Navigator.of(context, rootNavigator: true).pop();
                                widget.onHide?.call();
                              },
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.05),
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OurPicksBottomGradient extends StatelessWidget {
  const _OurPicksBottomGradient();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Color(0xF2000000), Color(0x99000000), Colors.transparent],
          stops: [0.0, 0.5, 1.0],
        ),
      ),
    );
  }
}

class _OurPicksCardInfo extends StatelessWidget {
  const _OurPicksCardInfo();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  'Our Picks',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: Colors.white,
                    shadows: [
                      Shadow(blurRadius: 4, color: Colors.black54),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            'Hand-picked featured characters from the Glaze team!',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              color: Colors.white.withValues(alpha: 0.75),
              height: 1.3,
              shadows: const [Shadow(blurRadius: 4, color: Colors.black87)],
            ),
          ),
        ],
      ),
    );
  }
}

class _OurPicksCardMenuButton extends StatelessWidget {
  final VoidCallback onTap;

  const _OurPicksCardMenuButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.5),
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.more_vert_rounded,
          size: 18,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _SortTypePill extends StatelessWidget {
  final SortType sortBy;
  final ValueChanged<SortType> onChanged;

  const _SortTypePill({required this.sortBy, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showPicker(context),
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: context.cs.primary.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.cs.primary.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              sortBy == SortType.name ? 'Name' : 'Date added',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: context.cs.primary,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 18,
              color: context.cs.primary,
            ),
          ],
        ),
      ),
    );
  }

  void _showPicker(BuildContext context) {
    BottomSheetItem build(String label, SortType type) => BottomSheetItem(
          label: label,
          actions: sortBy == type
              ? [
                  BottomSheetAction(
                    icon: Icons.check_rounded,
                    color: context.cs.primary,
                    onTap: () {
                      Navigator.of(context, rootNavigator: true).pop();
                      onChanged(type);
                    },
                  ),
                ]
              : const [],
          onTap: () {
            Navigator.of(context, rootNavigator: true).pop();
            onChanged(type);
          },
        );

    GlazeBottomSheet.show(
      context,
      title: 'Sort by',
      items: [
        build('Name', SortType.name),
        build('Date added', SortType.date),
      ],
    );
  }
}
