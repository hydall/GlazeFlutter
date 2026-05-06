import 'package:flutter/material.dart';

import '../../../core/models/character.dart';
import '../../../shared/theme/app_colors.dart';
import 'character_card.dart';

enum SortType { name, date }

enum SortDir { asc, desc }

class CharacterGrid extends StatelessWidget {
  final List<Character> characters;
  final SortType sortBy;
  final SortDir sortDir;
  final VoidCallback onSortDirToggle;
  final ValueChanged<SortType> onSortTypeChanged;

  const CharacterGrid({
    super.key,
    required this.characters,
    required this.sortBy,
    required this.sortDir,
    required this.onSortDirToggle,
    required this.onSortTypeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
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
                _SortTypePill(
                  sortBy: sortBy,
                  onChanged: onSortTypeChanged,
                ),
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
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          sliver: SliverGrid(
            delegate: SliverChildBuilderDelegate(
              (_, i) => CharacterCard(character: characters[i]),
              childCount: characters.length,
            ),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 180,
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
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: AppColors.accent.withValues(alpha: 0.15),
          shape: BoxShape.circle,
          border: Border.all(
              color: AppColors.accent.withValues(alpha: 0.2)),
        ),
        child: AnimatedRotation(
          turns: isAsc ? 0.5 : 0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutBack,
          child: const Icon(
            Icons.arrow_downward_rounded,
            size: 18,
            color: AppColors.accent,
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
          border: Border.all(
              color: AppColors.accent.withValues(alpha: 0.2)),
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
            const Icon(Icons.keyboard_arrow_down_rounded,
                size: 18, color: AppColors.accent),
          ],
        ),
      ),
    );
  }

  void _showPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.inactiveTab.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              title: Text(
                'Sort by Name',
                style: TextStyle(
                  color: sortBy == SortType.name
                      ? AppColors.accent
                      : AppColors.textPrimary,
                  fontWeight: sortBy == SortType.name
                      ? FontWeight.w600
                      : FontWeight.normal,
                ),
              ),
              trailing: sortBy == SortType.name
                  ? const Icon(Icons.check_rounded,
                      color: AppColors.accent, size: 20)
                  : null,
              onTap: () {
                Navigator.pop(context);
                onChanged(SortType.name);
              },
            ),
            ListTile(
              title: Text(
                'Sort by Date',
                style: TextStyle(
                  color: sortBy == SortType.date
                      ? AppColors.accent
                      : AppColors.textPrimary,
                  fontWeight: sortBy == SortType.date
                      ? FontWeight.w600
                      : FontWeight.normal,
                ),
              ),
              trailing: sortBy == SortType.date
                  ? const Icon(Icons.check_rounded,
                      color: AppColors.accent, size: 20)
                  : null,
              onTap: () {
                Navigator.pop(context);
                onChanged(SortType.date);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
