import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/services/character_book_converter.dart';
import '../../../core/state/db_provider.dart';
import '../../../core/state/lorebook_provider.dart';
import '../../../core/state/shared_prefs_provider.dart';
import 'catalog_models.dart';
import 'services/datacat_provider.dart';
import 'services/janitor_provider.dart';
import 'services/janitor_public_lorebook.dart';
import 'services/janny_provider.dart';
import 'services/chub_provider.dart';
import 'third_party_providers_provider.dart';

const _pageSize = 24;
const _providerKey = 'gz_catalog_provider';
// Legacy global filters key. Filters are now stored per provider under
// '${_filtersKey}_<provider>'; this bare key is only read as a one-time
// fallback so a user's existing selection survives the migration.
const _filtersKey = 'gz_catalog_filters';
const _sortKey = 'gz_catalog_sort';

String _filtersKeyFor(CatalogProvider p) => '${_filtersKey}_${p.name}';

const providerSortDefaults = <CatalogProvider, String>{
  CatalogProvider.janitor: 'trending',
  CatalogProvider.janny: 'newest',
  CatalogProvider.datacat: 'recent',
  CatalogProvider.chub: 'popular',
};

class CatalogState {
  final List<CatalogItem> results;
  final bool loading;
  final String? error;
  final int page;
  final bool hasMore;
  final String query;
  final int total;
  final CatalogProvider activeProvider;
  final CatalogFilters filters;

  const CatalogState({
    this.results = const [],
    this.loading = false,
    this.error,
    this.page = 1,
    this.hasMore = true,
    this.query = '',
    this.total = 0,
    this.activeProvider = CatalogProvider.janitor,
    this.filters = const CatalogFilters(),
  });

  CatalogState copyWith({
    List<CatalogItem>? results,
    bool? loading,
    String? error,
    int? page,
    bool? hasMore,
    String? query,
    int? total,
    CatalogProvider? activeProvider,
    CatalogFilters? filters,
  }) {
    return CatalogState(
      results: results ?? this.results,
      loading: loading ?? this.loading,
      error: error,
      page: page ?? this.page,
      hasMore: hasMore ?? this.hasMore,
      query: query ?? this.query,
      total: total ?? this.total,
      activeProvider: activeProvider ?? this.activeProvider,
      filters: filters ?? this.filters,
    );
  }
}

class CatalogNotifier extends StateNotifier<CatalogState> {
  final Ref _ref;

  CatalogNotifier(this._ref) : super(const CatalogState()) {
    _loadSavedState();
    // If the active provider gets disabled on the Third-Party providers screen,
    // fall back to an enabled one so the catalog never shows a hidden source.
    _ref.listen<List<CatalogProvider>>(enabledCatalogProvidersProvider, (
      _,
      enabled,
    ) {
      // Empty means every provider is disabled — the catalog is hidden, so
      // leave the active provider as-is (it'll be corrected when one is
      // re-enabled).
      if (enabled.isNotEmpty && !enabled.contains(state.activeProvider)) {
        setProvider(enabled.first);
      }
    });
  }

  Future<void> _loadSavedState() async {
    final prefs = await _ref.read(sharedPreferencesProvider.future);
    final savedProvider = prefs.getString(_providerKey) ?? 'janitor';
    final provider = CatalogProvider.values.firstWhere(
      (p) => p.name == savedProvider,
      orElse: () => CatalogProvider.janitor,
    );
    final savedSort =
        prefs.getString('${_sortKey}_${provider.name}') ??
        providerSortDefaults[provider]!;
    final savedFilters = _loadFilters(
      prefs,
      provider,
      allowLegacyFallback: true,
    );

    state = state.copyWith(
      activeProvider: provider,
      filters: savedFilters.copyWith(sort: savedSort),
    );
    await search(reset: true);
  }

  /// Loads the saved filters for [provider]. Each provider keeps its own tags,
  /// NSFL flag and token range, since the available tags/filters differ per
  /// provider. When [allowLegacyFallback] is set and no per-provider entry
  /// exists, the pre-migration global filters are used once (only for the
  /// provider that was active when they were saved).
  CatalogFilters _loadFilters(
    SharedPreferences prefs,
    CatalogProvider provider, {
    bool allowLegacyFallback = false,
  }) {
    try {
      var saved = prefs.getString(_filtersKeyFor(provider));
      if (saved == null && allowLegacyFallback) {
        saved = prefs.getString(_filtersKey);
      }
      if (saved != null) {
        final json = jsonDecode(saved) as Map<String, dynamic>;
        return CatalogFilters(
          nsfw: json['nsfw'] as bool? ?? false,
          nsfl: json['nsfl'] as bool? ?? false,
          tagIds: (json['tagIds'] as List?)?.cast<int>() ?? [],
          tagNames: (json['tagNames'] as List?)?.cast<String>() ?? [],
          minTokens: json['minTokens'] as int? ?? 29,
          maxTokens: json['maxTokens'] as int? ?? 100000,
        );
      }
    } catch (_) {}
    return const CatalogFilters();
  }

  Future<void> _saveState() async {
    final prefs = await _ref.read(sharedPreferencesProvider.future);
    await prefs.setString(_providerKey, state.activeProvider.name);
    await prefs.setString(
      '${_sortKey}_${state.activeProvider.name}',
      state.filters.sort,
    );
    await prefs.setString(
      _filtersKeyFor(state.activeProvider),
      jsonEncode({
        'nsfw': state.filters.nsfw,
        'nsfl': state.filters.nsfl,
        'tagIds': state.filters.tagIds,
        'tagNames': state.filters.tagNames,
        'minTokens': state.filters.minTokens,
        'maxTokens': state.filters.maxTokens,
      }),
    );
  }

  Future<void> setProvider(CatalogProvider provider) async {
    if (provider == state.activeProvider) return;
    final prefs = await _ref.read(sharedPreferencesProvider.future);
    // Each provider carries its own filters (tags, NSFL, token range), so
    // restore this provider's saved selection instead of leaking the previous
    // provider's filters. Sort likewise falls back to the provider default.
    final savedSort =
        prefs.getString('${_sortKey}_${provider.name}') ??
        providerSortDefaults[provider] ??
        'trending';
    final savedFilters = _loadFilters(prefs, provider);
    state = state.copyWith(
      activeProvider: provider,
      filters: savedFilters.copyWith(sort: savedSort),
    );
    _saveState();
    search(reset: true);
  }

  void setSort(String sort) {
    state = state.copyWith(filters: state.filters.copyWith(sort: sort));
    _saveState();
    search(reset: true);
  }

  void setFilters(CatalogFilters filters) {
    state = state.copyWith(filters: filters);
    _saveState();
    search(reset: true);
  }

  void setQuery(String query) {
    state = state.copyWith(query: query);
  }

  Future<void> search({bool reset = false}) async {
    if (state.loading) return;

    if (reset) {
      state = state.copyWith(page: 1, results: [], hasMore: true, error: null);
    }

    if (!state.hasMore) return;

    state = state.copyWith(loading: true, error: null);

    try {
      final provider = state.activeProvider;
      if (provider == CatalogProvider.janitor ||
          provider == CatalogProvider.janny) {
        unawaited(fetchJanitorTags().catchError((_) => <CatalogTag>[]));
      }

      final result = await _fetchFromProvider(provider);

      final items = result.characters;
      state = state.copyWith(
        results: reset ? items : [...state.results, ...items],
        total: result.total,
        hasMore:
            result.hasMore ??
            (items.isNotEmpty &&
                (state.results.length + items.length) < (result.total)),
        page: state.page + 1,
        loading: false,
      );
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  Future<CatalogSearchResult> _fetchFromProvider(
    CatalogProvider provider,
  ) async {
    switch (provider) {
      case CatalogProvider.janitor:
        return janitorSearch(
          query: state.query,
          page: state.page,
          filters: state.filters,
        );
      case CatalogProvider.janny:
        return jannySearch(
          query: state.query,
          page: state.page,
          filters: state.filters,
        );
      case CatalogProvider.datacat:
        await datacatEnsureSession();
        if (state.query.isNotEmpty) {
          return datacatSearch(
            query: state.query,
            page: state.page,
            limit: _pageSize,
            filters: state.filters,
          );
        }
        return datacatBrowse(
          page: state.page,
          limit: _pageSize,
          filters: state.filters,
        );
      case CatalogProvider.chub:
        return chubSearch(
          query: state.query,
          page: state.page,
          limit: _pageSize,
          filters: state.filters,
        );
    }
  }

  Future<void> loadMore() async {
    await search(reset: false);
  }

  Future<String> importCharacter(
    DownloadedCharacter downloaded, {
    String? sourceUrl,
    bool attachLorebooks = false,
    Map<String, dynamic>? janitorMeta,
  }) async {
    final charRepo = _ref.read(characterRepoProvider);
    final imageStorage = await _ref.read(imageStorageProvider.future);
    final lorebooks = _ref.read(lorebooksProvider.notifier);

    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final charData = downloaded.charData;

    String? avatarPath;
    if (downloaded.avatarUrl != null) {
      try {
        final bytes = await _fetchImageBytes(downloaded.avatarUrl!);
        avatarPath = await imageStorage.saveAvatar(id, bytes);
      } catch (_) {}
    }

    await charRepo.createCharacterFromCatalog(
      id: id,
      name: charData.name,
      description: charData.description,
      personality: charData.personality,
      scenario: charData.scenario,
      firstMes: charData.firstMes,
      mesExample: charData.mesExample,
      creatorNotes: charData.creatorNotes,
      systemPrompt: charData.systemPrompt,
      postHistoryInstructions: charData.postHistoryInstructions,
      alternateGreetings: charData.alternateGreetings,
      tags: charData.tags,
      creator: charData.creator,
      creatorId: charData.creatorId,
      avatarPath: avatarPath,
      sourceUrl: sourceUrl,
    );

    if (charData.characterBook is Map) {
      final book = Map<String, dynamic>.from(charData.characterBook as Map);
      final lorebook = convertCharacterBook(book, id);
      debugPrint(
        '[character_import] catalog saving_lorebook id=${lorebook.id} '
        'name=${lorebook.name} entries=${lorebook.entries.length} '
        'character=$id',
      );
      await lorebooks.put(lorebook);
    } else {
      debugPrint(
        '[character_import] catalog no_lorebook character=$id '
        'book_type=${charData.characterBook.runtimeType}',
      );
    }

    // When the user opted to import the character *with* its attached lorebooks,
    // download the character's public (JSON) lorebooks and save them scoped to
    // the new character. Private/closed and advanced (JS) lorebooks can't be
    // pulled whole — those still go through the Lorebooks tab's Extract/Build
    // flow. A lorebook failure never blocks the character import.
    if (attachLorebooks && janitorMeta != null) {
      try {
        final books = await fetchPublicLorebooks(janitorMeta);
        for (final book in books) {
          if (!book.accessible || book.entryCount == 0) continue;
          final lorebook = book.toLorebook(characterId: id);
          debugPrint(
            '[character_import] catalog saving_attached_lorebook '
            'id=${lorebook.id} name=${lorebook.name} '
            'entries=${lorebook.entries.length} character=$id',
          );
          await lorebooks.put(lorebook);
        }
      } catch (e) {
        debugPrint(
          '[character_import] attach_lorebooks_failed character=$id error=$e',
        );
      }
    }

    return id;
  }

  Future<Uint8List> _fetchImageBytes(String url) async {
    final dio = Dio();
    final res = await dio.get<List<int>>(
      url,
      options: Options(responseType: ResponseType.bytes),
    );
    return Uint8List.fromList(res.data ?? []);
  }

  void resetFilters() {
    final defaultSort =
        providerSortDefaults[state.activeProvider] ?? 'trending';
    state = state.copyWith(filters: CatalogFilters(sort: defaultSort));
    _saveState();
    search(reset: true);
  }
}

final catalogProvider = StateNotifierProvider<CatalogNotifier, CatalogState>((
  ref,
) {
  return CatalogNotifier(ref);
});
