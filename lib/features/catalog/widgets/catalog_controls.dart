import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/theme/app_colors.dart';
import '../../../shared/widgets/glaze_bottom_sheet.dart';
import '../catalog_models.dart';
import '../catalog_provider.dart';
import '../services/datacat_provider.dart';
import '../services/janitor_provider.dart';
import '../services/janny_provider.dart';
import '../services/chub_provider.dart';
import 'catalog_filter_sheet.dart';

class CatalogControls extends StatelessWidget {
  final CatalogState state;
  final CatalogNotifier notifier;

  const CatalogControls({
    super.key,
    required this.state,
    required this.notifier,
  });

  static String providerLabel(CatalogProvider p) => switch (p) {
    CatalogProvider.janitor => 'JanitorAI',
    CatalogProvider.janny => 'JannyAI',
    CatalogProvider.datacat => 'DataCat',
    CatalogProvider.chub => 'Chub.ai',
  };

  static Map<String, String> sortOptionsForProvider(CatalogProvider p) =>
      switch (p) {
        CatalogProvider.janitor => {
          'trending': 'Trending',
          'trending_24h': 'Trending 24h',
          'popular': 'Popular',
          'latest': 'Latest',
        },
        CatalogProvider.janny => {
          'newest': 'Newest',
          'oldest': 'Oldest',
          'tokens_desc': 'Most Tokens',
          'tokens_asc': 'Least Tokens',
          'relevant': 'Relevant',
        },
        CatalogProvider.datacat => {
          'recent': 'Recent',
          'fresh': 'Fresh',
          'score_week': 'Score (Week)',
          'score_24h': 'Score (24h)',
          'chat_count_week': 'Chats (Week)',
          'chat_count_24h': 'Chats (24h)',
        },
        CatalogProvider.chub => {
          'popular': 'Popular',
          'trending_week': 'Trending (Week)',
          'trending_24h': 'Trending (24h)',
          'latest': 'Latest',
          'rating': 'Rating',
          'updated': 'Updated',
        },
      };

  int _activeFilterCount() {
    final f = state.filters;
    int count = 0;
    if (f.nsfw) count++;
    if (f.nsfl) count++;
    if (f.tagIds.isNotEmpty) count += f.tagIds.length;
    if (f.tagNames.isNotEmpty) count += f.tagNames.length;
    if (f.minTokens != 29) count++;
    if (f.maxTokens != 100000) count++;
    return count;
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _ProviderPill(
          provider: state.activeProvider,
          onTap: () => _showPickerSheet(
            context,
            title: 'Provider',
            items: CatalogProvider.values
                .map(
                  (p) => _PickerItem(
                    label: providerLabel(p),
                    isActive: p == state.activeProvider,
                    value: p,
                  ),
                )
                .toList(),
            onSelect: (v) => notifier.setProvider(v as CatalogProvider),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _SearchField(
            query: state.query,
            onSubmitted: (q) {
              notifier.setQuery(q);
              notifier.search(reset: true);
            },
          ),
        ),
        const SizedBox(width: 8),
        _IconPill(
          icon: Icons.sort_rounded,
          onTap: () => _showPickerSheet(
            context,
            title: 'Sort',
            items: sortOptionsForProvider(state.activeProvider).entries
                .map(
                  (e) => _PickerItem(
                    label: e.value,
                    isActive: e.key == state.filters.sort,
                    value: e.key,
                  ),
                )
                .toList(),
            onSelect: (v) => notifier.setSort(v as String),
          ),
        ),
        const SizedBox(width: 6),
        _FilterPillBadge(
          count: _activeFilterCount(),
          onTap: () => GlazeBottomSheet.show(
            context,
            child: CatalogFilterSheet(
              filters: state.filters,
              provider: state.activeProvider,
              onApply: (f) => notifier.setFilters(f),
            ),
          ),
        ),
      ],
    );
  }

  void _showPickerSheet(
    BuildContext context, {
    required String title,
    required List<_PickerItem> items,
    required ValueChanged<dynamic> onSelect,
  }) {
    GlazeBottomSheet.show(
      context,
      title: title,
      items: items
          .map(
            (item) => BottomSheetItem(
              icon: item.isActive ? Icons.check_rounded : null,
              iconColor: AppColors.accent,
              label: item.label,
              onTap: () {
                Navigator.of(context, rootNavigator: true).pop();
                onSelect(item.value);
              },
            ),
          )
          .toList(),
    );
  }
}

class _PickerItem {
  final String label;
  final bool isActive;
  final dynamic value;
  const _PickerItem({
    required this.label,
    required this.isActive,
    required this.value,
  });
}

class _ProviderPill extends StatelessWidget {
  final CatalogProvider provider;
  final VoidCallback onTap;

  const _ProviderPill({required this.provider, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final label = CatalogControls.providerLabel(provider);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.accent.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.accent.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.accent,
              ),
            ),
            const SizedBox(width: 2),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 16,
              color: AppColors.accent,
            ),
          ],
        ),
      ),
    );
  }
}

class _IconPill extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _IconPill({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 36,
        width: 36,
        decoration: BoxDecoration(
          color: AppColors.accent.withValues(alpha: 0.15),
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.accent.withValues(alpha: 0.2)),
        ),
        child: Icon(icon, size: 18, color: AppColors.accent),
      ),
    );
  }
}

class _FilterPillBadge extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const _FilterPillBadge({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 36,
        width: 36,
        decoration: BoxDecoration(
          color: count > 0
              ? AppColors.accent.withValues(alpha: 0.3)
              : AppColors.accent.withValues(alpha: 0.15),
          shape: BoxShape.circle,
          border: Border.all(
            color: count > 0
                ? AppColors.accent.withValues(alpha: 0.4)
                : AppColors.accent.withValues(alpha: 0.2),
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            const Icon(
              Icons.filter_list_rounded,
              size: 18,
              color: AppColors.accent,
            ),
            if (count > 0)
              Positioned(
                top: 4,
                right: 4,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: const BoxDecoration(
                    color: AppColors.accent,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '$count',
                      style: const TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SearchField extends StatefulWidget {
  final String query;
  final ValueChanged<String> onSubmitted;

  const _SearchField({required this.query, required this.onSubmitted});

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  late final _controller = TextEditingController(text: widget.query);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: TextField(
        controller: _controller,
        style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
        decoration: InputDecoration(
          hintText: 'Search characters...',
          hintStyle: const TextStyle(
            fontSize: 13,
            color: AppColors.textSecondary,
          ),
          prefixIcon: const Icon(
            Icons.search_rounded,
            size: 18,
            color: AppColors.textSecondary,
          ),
          suffixIcon: _controller.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(
                    Icons.clear_rounded,
                    size: 16,
                    color: AppColors.textSecondary,
                  ),
                  onPressed: () {
                    _controller.clear();
                    widget.onSubmitted('');
                  },
                )
              : null,
          filled: true,
          fillColor: AppColors.surfaceHigh,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
        ),
        onSubmitted: widget.onSubmitted,
      ),
    );
  }
}
