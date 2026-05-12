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
            child: _AnimatedCharacterGrid(characters: characters),
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

  const _AnimatedCharacterGrid({required this.characters});

  static const _crossAxisCount = 2;
  static const _spacing = 10.0;
  static const _aspectRatio = 2 / 3;

  @override
  Widget build(BuildContext context) {
    if (characters.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (ctx, constraints) {
        final cellW =
            (constraints.maxWidth - _spacing * (_crossAxisCount - 1)) /
                _crossAxisCount;
        final cellH = cellW / _aspectRatio;
        final rows =
            (characters.length + _crossAxisCount - 1) ~/ _crossAxisCount;
        final totalH = rows * cellH + (rows - 1) * _spacing;

        return SizedBox(
          height: totalH,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (int i = 0; i < characters.length; i++)
                AnimatedPositioned(
                  key: ValueKey(characters[i].id),
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.easeOutCubic,
                  left: (i % _crossAxisCount) * (cellW + _spacing),
                  top: (i ~/ _crossAxisCount) * (cellH + _spacing),
                  width: cellW,
                  height: cellH,
                  child: CharacterCard(character: characters[i]),
                ),
            ],
          ),
        );
      },
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
