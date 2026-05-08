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
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, bottomPadding),
          sliver: SliverGrid(
            delegate: SliverChildBuilderDelegate(
              (_, i) => CharacterCard(character: characters[i]),
              childCount: characters.length,
            ),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 2 / 3,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
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
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: AppColors.accent.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.accent.withValues(alpha: 0.2)),
        ),
        child: Center(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Text(
              isAsc ? 'Oldest' : 'Newest',
              key: ValueKey(isAsc),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.accent,
              ),
            ),
          ),
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
          color: AppColors.accent.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.accent.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              sortBy == SortType.name ? 'Name' : 'Date',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.accent,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 18,
              color: AppColors.accent,
            ),
          ],
        ),
      ),
    );
  }

  void _showPicker(BuildContext context) {
    GlazeBottomSheet.show(
      context,
      title: 'Sort by',
      items: [
        BottomSheetItem(
          icon: sortBy == SortType.name ? Icons.check_rounded : null,
          iconColor: AppColors.accent,
          label: 'Sort by Name',
          onTap: () {
            Navigator.of(context, rootNavigator: true).pop();
            onChanged(SortType.name);
          },
        ),
        BottomSheetItem(
          icon: sortBy == SortType.date ? Icons.check_rounded : null,
          iconColor: AppColors.accent,
          label: 'Sort by Date',
          onTap: () {
            Navigator.of(context, rootNavigator: true).pop();
            onChanged(SortType.date);
          },
        ),
      ],
    );
  }
}
