import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/theme/app_colors.dart';
import '../catalog_models.dart';
import '../catalog_provider.dart';
import '../services/chub_provider.dart';
import '../services/datacat_provider.dart';
import '../services/janitor_provider.dart';
import 'catalog_card.dart';
import 'catalog_controls.dart';
import 'catalog_detail_launcher.dart';

class CatalogGrid extends ConsumerWidget {
  final double topPadding;
  final double bottomPadding;
  final Widget? tabBar;

  const CatalogGrid({
    super.key,
    this.topPadding = 0,
    this.bottomPadding = 16,
    this.tabBar,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(catalogProvider);
    final notifier = ref.read(catalogProvider.notifier);

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollEndNotification &&
            notification.metrics.extentAfter < 600 &&
            !state.loading &&
            state.hasMore) {
          notifier.loadMore();
        }
        return false;
      },
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: CustomScrollView(
        slivers: [
          if (topPadding > 0)
            SliverToBoxAdapter(child: SizedBox(height: topPadding)),
          if (tabBar != null) SliverToBoxAdapter(child: tabBar!),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: CatalogControls(state: state, notifier: notifier),
            ),
          ),
          if (state.filters.tagIds.isNotEmpty || state.filters.tagNames.isNotEmpty)
            SliverToBoxAdapter(
              child: _ActiveTagsRow(state: state, notifier: notifier),
            ),
          if (state.error != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Text(
                    state.error!,
                    style: TextStyle(
                      color: context.cs.onSurfaceVariant,
                      fontSize: 13,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          if (state.activeProvider != CatalogProvider.janny && state.activeProvider != CatalogProvider.chub)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                child: Text(
                  '${state.total} result${state.total == 1 ? '' : 's'}',
                  style: TextStyle(
                    fontSize: 11,
                    color: context.cs.onSurfaceVariant,
                  ),
                ),
              ),
            )
          else
            const SliverToBoxAdapter(child: SizedBox(height: 12)),
          if (state.results.isEmpty && !state.loading && state.page > 1)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: 80),
                child: Center(
                  child: Text(
                    state.error != null ? '' : 'No characters found',
                    style: TextStyle(
                      color: context.cs.onSurfaceVariant,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, bottomPadding),
              sliver: SliverLayoutBuilder(
                builder: (context, constraints) {
                  final crossAxisCount = (constraints.crossAxisExtent / 212).ceil().clamp(1, 10);
                  final rowCount = (state.results.length / crossAxisCount).ceil();

                  return SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (_, i) {
                        final startIndex = i * crossAxisCount;
                        final rowItems = state.results.skip(startIndex).take(crossAxisCount).toList();

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: List.generate(crossAxisCount, (colIndex) {
                              if (colIndex < rowItems.length) {
                                return Expanded(
                                  child: Padding(
                                    padding: EdgeInsets.only(
                                      right: colIndex < crossAxisCount - 1 ? 12 : 0,
                                    ),
                                    child: CatalogCard(
                                      item: rowItems[colIndex],
                                      onTap: () => _openDetail(
                                        context,
                                        rowItems[colIndex],
                                        state.activeProvider,
                                      ),
                                    ),
                                  ),
                                );
                              } else {
                                return Expanded(
                                  child: Padding(
                                    padding: EdgeInsets.only(
                                      right: colIndex < crossAxisCount - 1 ? 12 : 0,
                                    ),
                                    child: const SizedBox.shrink(),
                                  ),
                                );
                              }
                            }),
                          ),
                        ),
                      );
                    },
                      childCount: rowCount,
                    ),
                  );
                },
              ),
            ),
          if (state.loading)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Center(
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: context.cs.primary,
                    ),
                  ),
                ),
              ),
            ),
          if (!state.hasMore && state.results.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Center(
                  child: Text(
                    'End of results',
                    style: TextStyle(
                      fontSize: 12,
                      color: context.cs.onSurfaceVariant.withValues(alpha: 0.5),
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

  void _openDetail(
    BuildContext context,
    CatalogItem item,
    CatalogProvider provider,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CatalogDetailLauncher(item: item, provider: provider),
    );
  }
}

class _ActiveTagsRow extends StatelessWidget {
  final CatalogState state;
  final CatalogNotifier notifier;

  const _ActiveTagsRow({required this.state, required this.notifier});

  List<String> _getActiveTagNames() {
    final names = <String>{};
    names.addAll(state.filters.tagNames);

    if (state.filters.tagIds.isNotEmpty) {
      List<CatalogTag> allTags = [];
      if (state.activeProvider == CatalogProvider.chub) {
        allTags = getCachedChubTags();
      } else if (state.activeProvider == CatalogProvider.datacat) {
        allTags = getCachedDatacatTags();
      } else {
        allTags = getCachedJanitorTags();
      }

      for (final tag in allTags) {
        if (tag.id != null && state.filters.tagIds.contains(tag.id)) {
          names.add(tag.name);
        }
      }
    }

    final list = names.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }

  void _removeTag(String name) {
    List<CatalogTag> allTags = [];
    if (state.activeProvider == CatalogProvider.chub) {
      allTags = getCachedChubTags();
    } else if (state.activeProvider == CatalogProvider.datacat) {
      allTags = getCachedDatacatTags();
    } else {
      allTags = getCachedJanitorTags();
    }

    final tag = allTags.firstWhere((t) => t.name == name, orElse: () => CatalogTag(name: name));

    final newNames = state.filters.tagNames.toList();
    final newIds = state.filters.tagIds.toList();

    if (tag.id != null) {
      newIds.remove(tag.id);
    } else {
      newNames.remove(name);
    }

    notifier.setFilters(state.filters.copyWith(
      tagNames: newNames,
      tagIds: newIds,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final names = _getActiveTagNames();
    if (names.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: SizedBox(
        height: 28,
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          scrollDirection: Axis.horizontal,
          itemCount: names.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final name = names[index];
            return GestureDetector(
              onTap: () => _removeTag(name),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: context.cs.primary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: context.cs.primary),
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.close, size: 10, color: Colors.white),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

