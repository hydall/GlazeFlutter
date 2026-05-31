import 'package:flutter/material.dart';


import '../../../shared/theme/app_colors.dart';
import '../../../shared/widgets/glaze_bottom_sheet.dart';
import '../catalog_models.dart';
import '../catalog_provider.dart';
import 'catalog_filter_sheet.dart';
import 'package:easy_localization/easy_localization.dart';

class CatalogControls extends StatelessWidget {
  final CatalogState state;
  final CatalogNotifier notifier;

  const CatalogControls({
    super.key,
    required this.state,
    required this.notifier,
  });

  static String providerLabel(CatalogProvider p) => switch (p) {
    CatalogProvider.janitor => 'catalog_provider_janitor_label'.tr(),
    CatalogProvider.janny => 'catalog_provider_janny_label'.tr(),
    CatalogProvider.datacat => 'catalog_provider_datacat_label'.tr(),
    CatalogProvider.chub => 'catalog_provider_chub_label'.tr(),
  };

  static Map<String, String> sortOptionsForProvider(CatalogProvider p) =>
      switch (p) {
        CatalogProvider.janitor => {
          'trending': 'catalog_sort_janitor_trending'.tr(),
          'trending_24h': 'catalog_sort_janitor_trending24'.tr(),
          'popular': 'catalog_sort_janitor_popular'.tr(),
          'latest': 'catalog_sort_janitor_latest'.tr(),
        },
        CatalogProvider.janny => {
          'newest': 'catalog_sort_janny_newest'.tr(),
          'oldest': 'catalog_sort_janny_oldest'.tr(),
          'tokens_desc': 'catalog_sort_janny_tokens_desc'.tr(),
          'tokens_asc': 'catalog_sort_janny_tokens_asc'.tr(),
          'relevant': 'catalog_sort_janny_relevant'.tr(),
        },
        CatalogProvider.datacat => {
          'recent': 'catalog_sort_datacat_recent'.tr(),
          'fresh': 'catalog_sort_datacat_fresh'.tr(),
          'score_week': 'catalog_sort_datacat_score_week'.tr(),
          'score_24h': 'catalog_sort_datacat_score_24h'.tr(),
          'chat_count_week': 'catalog_sort_datacat_chat_count_week'.tr(),
          'chat_count_24h': 'catalog_sort_datacat_chat_count_24h'.tr(),
        },
        CatalogProvider.chub => {
          'popular': 'catalog_sort_chub_popular'.tr(),
          'trending_week': 'catalog_sort_chub_trending_week'.tr(),
          'trending_24h': 'catalog_sort_chub_trending_24h'.tr(),
          'latest': 'catalog_sort_chub_latest'.tr(),
          'rating': 'catalog_sort_chub_rating'.tr(),
          'updated': 'catalog_sort_chub_updated'.tr(),
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

  String _currentSortLabel() {
    final opts = sortOptionsForProvider(state.activeProvider);
    return opts[state.filters.sort] ?? state.filters.sort;
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _LabeledChip(
          label: providerLabel(state.activeProvider),
          onTap: () => _showPickerSheet(
            context,
            title: 'blacklist_glossary_chip'.tr(),
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
        const Spacer(),
        _FilterIconButton(
          count: _activeFilterCount(),
          onTap: () => showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            useRootNavigator: true,
            useSafeArea: true,
            backgroundColor: Colors.transparent,
            builder: (_) => CatalogFilterSheet(
              filters: state.filters,
              provider: state.activeProvider,
              onApply: (f) => notifier.setFilters(f),
            ),
          ),
        ),
        const SizedBox(width: 8),
        _LabeledChip(
          label: _currentSortLabel(),
          onTap: () => _showPickerSheet(
            context,
            title: 'sort_by'.tr(),
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
              iconColor: context.cs.primary,
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

class _LabeledChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _LabeledChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
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
              label,
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
}

class _FilterIconButton extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const _FilterIconButton({required this.count, required this.onTap});

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
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Icon(
              Icons.filter_list_rounded,
              size: 18,
              color: context.cs.primary,
            ),
            if (count > 0)
              Positioned(
                top: -2,
                right: -2,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: context.cs.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '$count',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        height: 1.0,
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
