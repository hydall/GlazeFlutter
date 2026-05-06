import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/theme/app_colors.dart';
import '../catalog_models.dart';
import '../catalog_provider.dart';
import '../services/datacat_provider.dart';
import '../services/janitor_provider.dart';
import '../services/janny_provider.dart';
import '../services/chub_provider.dart';
import 'catalog_card.dart';

class CatalogGrid extends ConsumerWidget {
  const CatalogGrid({super.key});

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
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: _CatalogControls(state: state, notifier: notifier),
            ),
          ),
          if (state.error != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Text(
                    state.error!,
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
              child: Text(
                '${state.total} result${state.total == 1 ? '' : 's'}',
                style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
            ),
          ),
          if (state.results.isEmpty && !state.loading)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: 80),
                child: Center(
                  child: Text(
                    state.error != null ? '' : 'No characters found',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              sliver: SliverGrid(
                delegate: SliverChildBuilderDelegate(
                  (_, i) => CatalogCard(
                    item: state.results[i],
                    onTap: () => _onCardTap(context, ref, state.results[i]),
                  ),
                  childCount: state.results.length,
                ),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 180,
                  childAspectRatio: 2 / 3,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                ),
              ),
            ),
          if (state.loading)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.only(bottom: 24),
                child: Center(
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.accent),
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
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary.withValues(alpha: 0.5)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _onCardTap(BuildContext context, WidgetRef ref, CatalogItem item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PreviewSheet(item: item),
    );
  }
}

class _CatalogControls extends StatelessWidget {
  final CatalogState state;
  final CatalogNotifier notifier;

  const _CatalogControls({required this.state, required this.notifier});

  static String _providerLabel(CatalogProvider p) => switch (p) {
        CatalogProvider.janitor => 'JanitorAI',
        CatalogProvider.janny => 'JannyAI',
        CatalogProvider.datacat => 'DataCat',
        CatalogProvider.chub => 'Chub.ai',
      };

  static Map<String, String> _sortOptionsForProvider(CatalogProvider p) => switch (p) {
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
                .map((p) => _PickerItem(label: _providerLabel(p), isActive: p == state.activeProvider, value: p))
                .toList(),
            onSelect: (v) => notifier.setProvider(v as CatalogProvider),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: _SearchField(query: state.query, onSubmitted: (q) { notifier.setQuery(q); notifier.search(reset: true); })),
        const SizedBox(width: 8),
        _IconPill(
          icon: Icons.sort_rounded,
          onTap: () => _showPickerSheet(
            context,
            title: 'Sort',
            items: _sortOptionsForProvider(state.activeProvider)
                .entries
                .map((e) => _PickerItem(label: e.value, isActive: e.key == state.filters.sort, value: e.key))
                .toList(),
            onSelect: (v) => notifier.setSort(v as String),
          ),
        ),
        const SizedBox(width: 6),
        _FilterPillBadge(
          count: _activeFilterCount(),
          onTap: () => _showFilterSheet(context),
        ),
      ],
    );
  }

  void _showPickerSheet(BuildContext context, {required String title, required List<_PickerItem> items, required ValueChanged<dynamic> onSelect}) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceHigh,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(width: 36, height: 4, decoration: BoxDecoration(color: AppColors.inactiveTab.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 12),
            ...items.map((item) => ListTile(
                  title: Text(item.label, style: TextStyle(color: item.isActive ? AppColors.accent : AppColors.textPrimary, fontWeight: item.isActive ? FontWeight.w600 : FontWeight.normal)),
                  trailing: item.isActive ? const Icon(Icons.check_rounded, color: AppColors.accent, size: 20) : null,
                  onTap: () {
                    Navigator.pop(context);
                    onSelect(item.value);
                  },
                )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showFilterSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceHigh,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _FilterSheet(
        filters: state.filters,
        provider: state.activeProvider,
        onApply: (f) => notifier.setFilters(f),
      ),
    );
  }
}

class _PickerItem {
  final String label;
  final bool isActive;
  final dynamic value;
  const _PickerItem({required this.label, required this.isActive, required this.value});
}

class _ProviderPill extends StatelessWidget {
  final CatalogProvider provider;
  final VoidCallback onTap;

  const _ProviderPill({required this.provider, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final label = switch (provider) {
      CatalogProvider.janitor => 'JanitorAI',
      CatalogProvider.janny => 'JannyAI',
      CatalogProvider.datacat => 'DataCat',
      CatalogProvider.chub => 'Chub.ai',
    };
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
            Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.accent)),
            const SizedBox(width: 2),
            const Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: AppColors.accent),
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
          color: count > 0 ? AppColors.accent.withValues(alpha: 0.3) : AppColors.accent.withValues(alpha: 0.15),
          shape: BoxShape.circle,
          border: Border.all(color: count > 0 ? AppColors.accent.withValues(alpha: 0.4) : AppColors.accent.withValues(alpha: 0.2)),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            const Icon(Icons.filter_list_rounded, size: 18, color: AppColors.accent),
            if (count > 0)
              Positioned(
                top: 4,
                right: 4,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
                  child: Center(child: Text('$count', style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: Colors.white))),
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
          hintStyle: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
          prefixIcon: const Icon(Icons.search_rounded, size: 18, color: AppColors.textSecondary),
          suffixIcon: _controller.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear_rounded, size: 16, color: AppColors.textSecondary),
                  onPressed: () { _controller.clear(); widget.onSubmitted(''); },
                )
              : null,
          filled: true,
          fillColor: AppColors.surfaceHigh,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
        ),
        onSubmitted: widget.onSubmitted,
      ),
    );
  }
}

// ─── Filter Sheet ────────────────────────────────────────────────────────

class _FilterSheet extends StatefulWidget {
  final CatalogFilters filters;
  final CatalogProvider provider;
  final ValueChanged<CatalogFilters> onApply;

  const _FilterSheet({required this.filters, required this.provider, required this.onApply});

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late bool _nsfw;
  late bool _nsfl;
  late int _minTokens;
  late int _maxTokens;

  @override
  void initState() {
    super.initState();
    _nsfw = widget.filters.nsfw;
    _nsfl = widget.filters.nsfl;
    _minTokens = widget.filters.minTokens;
    _maxTokens = widget.filters.maxTokens;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(width: 36, height: 4, decoration: BoxDecoration(color: AppColors.inactiveTab.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 12),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Align(alignment: Alignment.centerLeft, child: Text('Filters', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary))),
            ),
            const SizedBox(height: 16),
            _toggleTile('NSFW', _nsfw, (v) => setState(() => _nsfw = v)),
            if (widget.provider == CatalogProvider.chub)
              _toggleTile('NSFL', _nsfl, (v) => setState(() => _nsfl = v)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(child: _tokenField('Min tokens', _minTokens, (v) => setState(() => _minTokens = v))),
                  const SizedBox(width: 12),
                  Expanded(child: _tokenField('Max tokens', _maxTokens, (v) => setState(() => _maxTokens = v))),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() { _nsfw = false; _nsfl = false; _minTokens = 29; _maxTokens = 100000; }),
                      child: Container(
                        height: 44,
                        decoration: BoxDecoration(color: AppColors.surfaceHigh, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
                        child: const Center(child: Text('Reset', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600))),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: GestureDetector(
                      onTap: () {
                        widget.onApply(CatalogFilters(
                          sort: widget.filters.sort,
                          nsfw: _nsfw,
                          nsfl: _nsfl,
                          tagIds: widget.filters.tagIds,
                          tagNames: widget.filters.tagNames,
                          minTokens: _minTokens,
                          maxTokens: _maxTokens,
                        ));
                        Navigator.pop(context);
                      },
                      child: Container(
                        height: 44,
                        decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(12)),
                        child: const Center(child: Text('Apply', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _toggleTile(String label, bool value, ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: [
        Text(label, style: const TextStyle(color: AppColors.textPrimary, fontSize: 15)),
        const Spacer(),
        Switch(value: value, onChanged: onChanged, activeThumbColor: AppColors.accent),
      ]),
    );
  }

  Widget _tokenField(String label, int value, ValueChanged<int> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
        const SizedBox(height: 4),
        SizedBox(
          height: 36,
          child: TextField(
            controller: TextEditingController(text: '$value'),
            keyboardType: TextInputType.number,
            style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
            decoration: InputDecoration(
              filled: true,
              fillColor: AppColors.background,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            ),
            onSubmitted: (v) { final p = int.tryParse(v); if (p != null) onChanged(p); },
          ),
        ),
      ],
    );
  }
}

// ─── Preview Sheet ───────────────────────────────────────────────────────

class _PreviewSheet extends ConsumerStatefulWidget {
  final CatalogItem item;
  const _PreviewSheet({required this.item});

  @override
  ConsumerState<_PreviewSheet> createState() => _PreviewSheetState();
}

class _PreviewSheetState extends ConsumerState<_PreviewSheet> {
  bool _loading = false;
  bool _importing = false;
  DownloadedCharacter? _downloaded;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchCharacter();
  }

  Future<void> _fetchCharacter() async {
    setState(() { _loading = true; _error = null; });
    try {
      final state = ref.read(catalogProvider);
      final provider = state.activeProvider;
      DownloadedCharacter result;
      switch (provider) {
        case CatalogProvider.janitor:
          result = await janitorFetchCharacter(widget.item.id);
        case CatalogProvider.janny:
          result = await jannyFetchCharacter(widget.item.id, widget.item.slug);
        case CatalogProvider.datacat:
          result = await datacatGetCharacter(widget.item.id);
        case CatalogProvider.chub:
          result = await chubGetCharacter(widget.item.fullPath ?? widget.item.id);
      }
      if (mounted) setState(() { _downloaded = result; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surfaceHigh,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(width: 36, height: 4, decoration: BoxDecoration(color: AppColors.inactiveTab.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(2))),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
                  : _error != null
                      ? _buildError()
                      : _downloaded != null
                          ? _buildPreview(scrollController)
                          : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 48, color: AppColors.textSecondary),
            const SizedBox(height: 16),
            Text(_error ?? 'Unknown error', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: _fetchCharacter,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(12)),
                child: const Text('Retry', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview(ScrollController controller) {
    final char = _downloaded!.charData;
    return Stack(
      children: [
        ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    width: 120,
                    height: 160,
                    child: _downloaded!.avatarUrl != null
                        ? CachedNetworkImage(imageUrl: _downloaded!.avatarUrl!, fit: BoxFit.cover, errorWidget: (_, _, _) => _avatarPlaceholder())
                        : _avatarPlaceholder(),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(char.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                      if (char.creator.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text('by @${char.creator}', style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                      ],
                      if (char.tags.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: char.tags.take(6).map((t) {
                            final isNsfw = t.toUpperCase() == 'NSFW';
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: isNsfw ? Colors.red.withValues(alpha: 0.2) : AppColors.accent.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(t, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: isNsfw ? Colors.redAccent : AppColors.accent)),
                            );
                          }).toList(),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (char.creatorNotes.isNotEmpty) ...[
              _sectionTitle('Creator Notes'),
              const SizedBox(height: 4),
              Text(char.creatorNotes, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4)),
              const SizedBox(height: 16),
            ],
            if (char.description.isNotEmpty) ...[
              _sectionTitle('Description'),
              const SizedBox(height: 4),
              Text(char.description, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4)),
              const SizedBox(height: 16),
            ],
            if (char.scenario.isNotEmpty) ...[
              _sectionTitle('Scenario'),
              const SizedBox(height: 4),
              Text(char.scenario, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4)),
              const SizedBox(height: 16),
            ],
            if (char.firstMes.isNotEmpty) ...[
              _sectionTitle('First Message'),
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(12)),
                child: Text(char.firstMes, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, height: 1.4)),
              ),
              const SizedBox(height: 16),
            ],
          ],
        ),
        Positioned(
          bottom: 16,
          left: 16,
          right: 16,
          child: _ImportButton(importing: _importing, onTap: _doImport),
        ),
      ],
    );
  }

  Widget _avatarPlaceholder() {
    return Container(
      color: AppColors.accent.withValues(alpha: 0.2),
      child: Center(
        child: Text(
          _downloaded!.charData.name.isNotEmpty ? _downloaded!.charData.name[0].toUpperCase() : '?',
          style: const TextStyle(fontSize: 40, color: AppColors.accent, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Text(title, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w700));
  }

  Future<void> _doImport() async {
    if (_downloaded == null || _importing) return;
    setState(() => _importing = true);
    try {
      await ref.read(catalogProvider.notifier).importCharacter(_downloaded!);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Imported ${_downloaded!.charData.name}'), backgroundColor: AppColors.accent));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _importing = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Import failed: $e')));
      }
    }
  }
}

class _ImportButton extends StatelessWidget {
  final bool importing;
  final VoidCallback onTap;

  const _ImportButton({required this.importing, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: importing ? null : onTap,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: importing ? AppColors.accent.withValues(alpha: 0.5) : AppColors.accent,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Center(
          child: importing
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
              : const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.download_rounded, color: Colors.white, size: 22),
                    SizedBox(width: 8),
                    Text('Import Character', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                  ],
                ),
        ),
      ),
    );
  }
}
