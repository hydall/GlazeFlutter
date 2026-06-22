import 'dart:async';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import 'package:go_router/go_router.dart';

import '../../core/db/repositories/character_repo.dart';
import '../../core/services/character_book_converter.dart';
import '../../core/services/character_export_helper.dart';
import '../../core/services/character_importer.dart';
import '../../core/state/character_folder_provider.dart';
import '../../core/state/character_provider.dart';
import '../../core/state/db_provider.dart';
import '../../core/state/lorebook_provider.dart';
import '../../shared/shell/nav_height_provider.dart';
import '../../shared/shell/shell_header_provider.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/widgets/glass_surface.dart';
import '../../shared/widgets/glaze_bottom_sheet.dart';
import '../../shared/widgets/glaze_tab_bar.dart';
import '../../shared/widgets/glaze_error_dialog.dart';
import '../../shared/widgets/glaze_toast.dart';
import '../catalog/catalog_provider.dart';
import '../catalog/widgets/widgets.dart';
import '../character_gallery/gallery_provider.dart';
import '../picks/widgets/picks_grid.dart';
import '../settings/app_settings_provider.dart';
import 'character_sort.dart';
import 'character_detail_screen.dart';
import 'character_selection_provider.dart';
import 'filtered_characters_provider.dart';
import 'widgets/widgets.dart';

class CharacterListScreen extends ConsumerStatefulWidget {
  final String? initialCharacterId;

  const CharacterListScreen({super.key, this.initialCharacterId});

  @override
  ConsumerState<CharacterListScreen> createState() =>
      _CharacterListScreenState();
}

class _CharacterListScreenState extends ConsumerState<CharacterListScreen>
    with ShellHeaderMixin {
  SortType _sortBy = SortType.date;
  SortDir _sortDir = SortDir.desc;
  int _tabIndex = 0;
  String _searchQuery = '';
  CharacterListFilters _filters = const CharacterListFilters();
  String? _currentFolderId;
  String _picksTitle = 'Our Picks';
  bool _picksCanGoBack = false;
  VoidCallback? _picksGoBackFn;

  // Inline header search (mirrors the Vue header: the loupe swaps the title for
  // an input field that filters the current view in place — My Characters
  // locally, Discover via the shared catalogProvider query).
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  bool _searchExpanded = false;
  Timer? _catalogDebounce;
  String? _lastOpenedInitialCharacterId;
  bool _openingInitialCharacter = false;

  // The tabs row floats below the shell header like a second header. Its
  // hide-on-scroll state lives in [shellHeaderHiddenProvider] so it travels in
  // step with the shell header. This constant is the block it occupies (its top
  // padding + the bar itself) so content can reserve room.
  static const double _kTabBarBlock = 52.0;

  // Owns the scroll position of whichever list view is currently shown (the
  // grids attach via PrimaryScrollController), so tapping the active tab can
  // animate it back to the top.
  final ScrollController _listScrollController = ScrollController();

  @override
  void dispose() {
    _catalogDebounce?.cancel();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    _listScrollController.dispose();
    super.dispose();
  }

  /// Hides the floating tabs row while scrolling down, reveals it scrolling up.
  /// Mirrors the chat header's behaviour ([_onScrollDirection] there).
  bool _onScrollNotification(ScrollNotification n) {
    if (n is UserScrollNotification && n.metrics.axis == Axis.vertical) {
      final notifier = ref.read(
        shellHeaderHiddenProvider(headerBranchIndex).notifier,
      );
      if (n.direction == ScrollDirection.reverse && !notifier.state) {
        notifier.state = true;
      } else if (n.direction == ScrollDirection.forward && notifier.state) {
        notifier.state = false;
      }
    }
    return false;
  }

  /// Forces the shell header + tabs row back into view (e.g. after navigating
  /// between views, where staying hidden would be jarring).
  void _showHeader() {
    final notifier = ref.read(
      shellHeaderHiddenProvider(headerBranchIndex).notifier,
    );
    if (notifier.state) notifier.state = false;
  }

  /// Animates the active list back to the top. Guarded so it never reads a
  /// position while two scroll views are briefly attached during a tab switch.
  void _scrollToTop() {
    if (!_listScrollController.hasClients) return;
    if (_listScrollController.positions.length != 1) return;
    _listScrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  int get headerBranchIndex => 1;

  @override
  ShellHeaderConfig buildShellHeader() {
    final inFolder = _tabIndex == 0 && _currentFolderId != null;
    final inPicks = inFolder && _currentFolderId == kPicksFolderId;
    final inSearch = _searchExpanded && !inPicks;
    final folderTitle = inFolder ? _folderName(_currentFolderId!) : null;
    return ShellHeaderConfig(
      title: inSearch
          ? null
          : (inPicks
                ? _picksTitle
                : (folderTitle ?? 'header_characters'.tr())),
      titleWidget: inSearch ? _buildSearchField(context) : null,
      showBack: inFolder,
      onBack: inPicks
          ? (_picksCanGoBack && _picksGoBackFn != null
                ? _picksGoBackFn
                : () {
                    _showHeader();
                    setState(() => _currentFolderId = null);
                    refreshShellHeader();
                  })
          : inFolder
          ? () {
              _showHeader();
              setState(() => _currentFolderId = null);
              refreshShellHeader();
            }
          : null,
      actions: inPicks
          ? null
          : [
              SizedBox(
                width: 44,
                height: 44,
                child: IconButton(
                  icon: Icon(
                    _searchExpanded
                        ? Icons.close_rounded
                        : Icons.search_rounded,
                    size: 22,
                  ),
                  color: context.cs.primary,
                  onPressed: _searchExpanded ? _closeSearch : _openSearch,
                ),
              ),
            ],
      // The tabs ride inside the header (only at the top level) so they hide and
      // reveal as a single unit with it — one animation, not two.
      below: inFolder ? null : _buildTabBar(),
    );
  }

  void _openSearch() {
    setState(() => _searchExpanded = true);
    refreshShellHeader();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _searchFocus.requestFocus(),
    );
  }

  void _closeSearch() {
    _catalogDebounce?.cancel();
    _searchCtrl.clear();
    setState(() {
      _searchExpanded = false;
      _searchQuery = '';
    });
    refreshShellHeader();
    // Reset the catalog query so the Discover grid returns to its default feed.
    if (ref.read(catalogProvider).query.isNotEmpty) {
      final notifier = ref.read(catalogProvider.notifier);
      notifier.setQuery('');
      notifier.search(reset: true);
    }
  }

  void _onSearchChanged(String value) {
    if (_tabIndex == 1) {
      // Discover: debounce the provider query (same 400ms as the Vue header).
      _catalogDebounce?.cancel();
      _catalogDebounce = Timer(const Duration(milliseconds: 400), () {
        final notifier = ref.read(catalogProvider.notifier);
        notifier.setQuery(value.trim());
        notifier.search(reset: true);
      });
    } else {
      // My Characters: local filter, live.
      setState(() => _searchQuery = value);
    }
  }

  /// Re-applies the current search text to whichever tab just became active, so
  /// switching tabs mid-search keeps results consistent.
  void _applySearchForActiveTab() {
    final text = _searchCtrl.text;
    if (_tabIndex == 1) {
      _catalogDebounce?.cancel();
      final notifier = ref.read(catalogProvider.notifier);
      notifier.setQuery(text.trim());
      notifier.search(reset: true);
    } else {
      _searchQuery = text;
    }
  }

  CharacterSortField get _sortField => switch (_sortBy) {
    SortType.name => CharacterSortField.name,
    SortType.date => CharacterSortField.date,
    SortType.lastChat => CharacterSortField.lastChat,
  };

  CharacterSortDir get _sortDirEnum =>
      _sortDir == SortDir.asc ? CharacterSortDir.asc : CharacterSortDir.desc;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _maybeOpenInitialCharacter();
  }

  @override
  void didUpdateWidget(covariant CharacterListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialCharacterId != widget.initialCharacterId) {
      _openingInitialCharacter = false;
      _maybeOpenInitialCharacter();
    }
  }

  void _maybeOpenInitialCharacter() {
    final charId = widget.initialCharacterId;
    if (charId == null ||
        charId.isEmpty ||
        _openingInitialCharacter ||
        _lastOpenedInitialCharacterId == charId) {
      return;
    }

    _openingInitialCharacter = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (_tabIndex != 0 || _searchExpanded) {
        _catalogDebounce?.cancel();
        setState(() {
          _tabIndex = 0;
          _searchExpanded = false;
        });
        refreshShellHeader();
        await Future<void>.delayed(const Duration(milliseconds: 250));
        if (!mounted) return;
      }

      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!mounted) return;
      _lastOpenedInitialCharacterId = charId;

      final result = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        useRootNavigator: true,
        backgroundColor: Colors.transparent,
        builder: (_) => CharacterDetailScreen(charId: charId),
      );

      if (!mounted) return;
      _openingInitialCharacter = false;

      final uri = GoRouterState.of(context).uri;
      if (uri.path == '/characters' &&
          uri.queryParameters.containsKey('open')) {
        context.go('/characters');
      }

      if (result != null && result.isNotEmpty && mounted) {
        context.go(result);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final navHeight = ref.watch(navHeightProvider);
    final selection = ref.watch(characterSelectionProvider);

    final topPad = MediaQuery.of(context).padding.top + 74.0;
    // The tabs ride inside the shell header (its `below` slot) only at the top
    // level; inside a folder the header shows a back button instead. Reserve the
    // extra room for the tabs row when it's present so content clears it.
    final showTabBar = !(_tabIndex == 0 && _currentFolderId != null);
    final contentTopPad = showTabBar ? topPad + _kTabBarBlock : topPad;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(
            child: NotificationListener<ScrollNotification>(
              onNotification: _onScrollNotification,
              child: PrimaryScrollController(
                controller: _listScrollController,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 350),
                  reverseDuration: const Duration(milliseconds: 300),
                  switchInCurve: Curves.easeOutQuart,
                  switchOutCurve: Curves.easeInQuart,
                  transitionBuilder: (child, animation) {
                    final slide =
                        Tween<Offset>(
                          begin: const Offset(0.0, 0.06),
                          end: Offset.zero,
                        ).animate(
                          CurvedAnimation(
                            parent: animation,
                            curve: Curves.easeOutBack,
                          ),
                        );
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(position: slide, child: child),
                    );
                  },
                  child: _tabIndex == 1
                      ? CatalogGrid(
                          key: const ValueKey('catalog_grid'),
                          topPadding: contentTopPad,
                          bottomPadding: navHeight + 20,
                        )
                      : KeyedSubtree(
                          key: const ValueKey('my_characters'),
                          child: _buildMyCharacters(
                            context,
                            contentTopPad,
                            navHeight,
                          ),
                        ),
                ),
              ),
            ),
          ),
          if (_tabIndex == 0 && _currentFolderId != kPicksFolderId)
            selection.active
                ? Positioned(
                    left: 16,
                    right: 16,
                    bottom: navHeight + 16,
                    child: _SelectionBar(
                      count: selection.count,
                      onCancel: () => ref
                          .read(characterSelectionProvider.notifier)
                          .clear(),
                      onMore: () => _showSelectionActions(context, selection),
                    ),
                  )
                : Positioned(
                    right: 16,
                    bottom: navHeight + 16,
                    child: _AddButton(onTap: () => _showAddSheet(context, ref)),
                  ),
        ],
      ),
    );
  }

  String? _folderName(String id) {
    if (id == kPicksFolderId) return _picksTitle;
    if (id == kFavoritesFolderId) return 'folder_favorites'.tr();
    final folders = ref.read(characterFoldersProvider).value;
    return folders?.where((f) => f.id == id).firstOrNull?.name;
  }

  Widget _buildMyCharacters(
    BuildContext context,
    double topPad,
    double navHeight,
  ) {
    if (_currentFolderId != null) {
      return _buildFolderContents(context, topPad, navHeight);
    }

    final specialsVisible = _searchQuery.isEmpty && !_filters.isActive;
    final showOurPicks =
        specialsVisible &&
        (ref.watch(appSettingsProvider).value?.showOurPicks ?? true);
    final hasFavorites = ref
        .watch(charactersProvider)
        .maybeWhen(
          data: (chars) => chars.any((c) => c.fav),
          orElse: () => false,
        );
    final showFavorites = specialsVisible && hasFavorites;

    if (_searchQuery.isNotEmpty || _filters.isActive) {
      return _buildFilteredResults(context, topPad, navHeight);
    }

    final key = InfiniteCharactersKey(
      sort: _sortField,
      dir: _sortDirEnum,
      showHidden: ref.watch(revealHiddenCharactersProvider),
    );
    final infinite = ref.watch(infiniteCharactersProvider(key));

    return infinite.when(
      loading: () =>
          Center(child: CircularProgressIndicator(color: context.cs.primary)),
      error: (e, _) => Center(
        child: Text(
          '${'title_error'.tr()}: $e',
          style: TextStyle(color: context.cs.onSurfaceVariant),
        ),
      ),
      data: (state) {
        if (state.totalCount == 0 && !showOurPicks) {
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: SizedBox(height: topPad)),
              SliverFillRemaining(
                child: EmptyCharacterState(
                  onImport: () => _importCharacter(context, ref),
                ),
              ),
            ],
          );
        }
        return NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n.metrics.axis != Axis.vertical) return false;
            if (state.hasMore &&
                !state.isLoadingMore &&
                n.metrics.extentAfter < 600) {
              ref.read(infiniteCharactersProvider(key).notifier).loadMore();
            }
            return false;
          },
          child: CharacterGrid(
            characters: state.items,
            totalCount: state.totalCount,
            sortBy: _sortBy,
            sortDir: _sortDir,
            topPadding: topPad,
            bottomPadding: navHeight + 20,
            filterCount: _filters.activeCount,
            onFilterTap: () => _showCharacterFilterSheet(context),
            // The grid only holds the loaded page; let the dice draw from the
            // full unfiltered library instead of just the rendered cards.
            randomPool: () => ref.read(filteredCharactersProvider(_query())),
            headerSliver: SliverToBoxAdapter(
              child: CharacterFoldersSection(
                onOpenFolder: (id) {
                  setState(() => _currentFolderId = id);
                  refreshShellHeader();
                },
                showFavorites: showFavorites,
                onOpenFavorites: () {
                  setState(() => _currentFolderId = kFavoritesFolderId);
                  refreshShellHeader();
                },
                showOurPicks: showOurPicks,
                onOpenPicks: () {
                  setState(() => _currentFolderId = kPicksFolderId);
                  refreshShellHeader();
                },
                onHidePicks: () {
                  final s = ref.read(appSettingsProvider).value;
                  if (s != null) {
                    ref
                        .read(appSettingsProvider.notifier)
                        .save(s.copyWith(showOurPicks: false));
                    GlazeToast.show(context, 'our_picks_hidden_toast'.tr());
                  }
                },
              ),
            ),
            onSortDirToggle: () => setState(() {
              _sortDir = _sortDir == SortDir.asc ? SortDir.desc : SortDir.asc;
            }),
            onSortTypeChanged: (t) => setState(() => _sortBy = t),
            isLoadingMore: state.isLoadingMore,
            hasMore: state.hasMore,
          ),
        );
      },
    );
  }

  /// Builds the query for [filteredCharactersProvider] from current UI state.
  ///
  /// [forceFavOnly] restricts to favorited characters regardless of the active
  /// filters — used by the virtual "Favorites" folder.
  CharacterQuery _query({String? folderId, bool forceFavOnly = false}) =>
      CharacterQuery(
        search: _searchQuery,
        favOnly: forceFavOnly || _filters.favOnly,
        tags: _filters.tagNames.toList()..sort(),
        minTokens: _filters.minTokens,
        maxTokens: _filters.maxTokens,
        hasTokenFilter: _filters.hasTokenFilter,
        sortBy: _sortBy,
        sortDir: _sortDir,
        folderId: folderId,
      );

  Widget _buildFilteredResults(
    BuildContext context,
    double topPad,
    double navHeight,
  ) {
    final chars = ref.watch(charactersProvider);
    return chars.when(
      loading: () =>
          Center(child: CircularProgressIndicator(color: context.cs.primary)),
      error: (e, _) => Center(
        child: Text(
          '${'title_error'.tr()}: $e',
          style: TextStyle(color: context.cs.onSurfaceVariant),
        ),
      ),
      data: (_) {
        // Filtering + sorting happens in the (cached) provider, not here.
        final sorted = ref.watch(filteredCharactersProvider(_query()));

        if (sorted.isEmpty) {
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: SizedBox(height: topPad)),
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'no_characters'.tr(),
                        style: TextStyle(color: context.cs.onSurfaceVariant),
                      ),
                      if (_filters.isActive)
                        TextButton(
                          onPressed: () => setState(
                            () => _filters = const CharacterListFilters(),
                          ),
                          child: Text(
                            'catalog_clear_tags'.tr(
                              namedArgs: {'count': '${_filters.activeCount}'},
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          );
        }
        return CharacterGrid(
          characters: sorted,
          totalCount: sorted.length,
          sortBy: _sortBy,
          sortDir: _sortDir,
          topPadding: topPad,
          bottomPadding: navHeight + 20,
          filterCount: _filters.activeCount,
          onFilterTap: () => _showCharacterFilterSheet(context),
          onSortDirToggle: () => setState(() {
            _sortDir = _sortDir == SortDir.asc ? SortDir.desc : SortDir.asc;
          }),
          onSortTypeChanged: (t) => setState(() => _sortBy = t),
        );
      },
    );
  }

  Widget _buildFolderContents(
    BuildContext context,
    double topPad,
    double navHeight,
  ) {
    final folderId = _currentFolderId!;
    if (folderId == kPicksFolderId) {
      return PicksGrid(
        key: const ValueKey('picks_grid'),
        topPadding: topPad,
        bottomPadding: navHeight + 20,
        onFolderChanged: (title, description, canGoBack, goBackFn) {
          setState(() {
            _picksTitle = title;
            _picksCanGoBack = canGoBack;
            _picksGoBackFn = goBackFn;
          });
          refreshShellHeader();
        },
      );
    }
    final isFavorites = folderId == kFavoritesFolderId;
    final chars = ref.watch(charactersProvider);
    return chars.when(
      loading: () =>
          Center(child: CircularProgressIndicator(color: context.cs.primary)),
      error: (e, _) => Center(
        child: Text(
          '${'title_error'.tr()}: $e',
          style: TextStyle(color: context.cs.onSurfaceVariant),
        ),
      ),
      data: (_) {
        // The Favorites folder is virtual: it filters on the `fav` flag rather
        // than folder membership, so it never passes a folderId downstream.
        final sorted = ref.watch(
          filteredCharactersProvider(
            isFavorites
                ? _query(forceFavOnly: true)
                : _query(folderId: folderId),
          ),
        );

        if (sorted.isEmpty) {
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: SizedBox(height: topPad)),
              SliverFillRemaining(
                child: Center(
                  child: Text(
                    isFavorites
                        ? 'folder_favorites_empty'.tr()
                        : 'folder_empty'.tr(),
                    style: TextStyle(color: context.cs.onSurfaceVariant),
                  ),
                ),
              ),
            ],
          );
        }
        return CharacterGrid(
          characters: sorted,
          totalCount: sorted.length,
          sortBy: _sortBy,
          sortDir: _sortDir,
          topPadding: topPad,
          bottomPadding: navHeight + 20,
          filterCount: _filters.activeCount,
          onFilterTap: () => _showCharacterFilterSheet(context),
          folderId: isFavorites ? null : folderId,
          onSortDirToggle: () => setState(() {
            _sortDir = _sortDir == SortDir.asc ? SortDir.desc : SortDir.asc;
          }),
          onSortTypeChanged: (t) => setState(() => _sortBy = t),
        );
      },
    );
  }

  void _showCharacterFilterSheet(BuildContext context) {
    final all = ref.read(charactersProvider).value ?? const [];
    final tagSet = <String>{};
    for (final c in all) {
      tagSet.addAll(c.tags);
    }
    final allTags = tagSet.toList()..sort();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CharacterFilterSheet(
        filters: _filters,
        allTags: allTags,
        onApply: (f) => setState(() => _filters = f),
      ),
    );
  }

  Widget _buildSearchField(BuildContext context) {
    return TextField(
      controller: _searchCtrl,
      focusNode: _searchFocus,
      autofocus: true,
      onChanged: _onSearchChanged,
      textInputAction: TextInputAction.search,
      cursorColor: context.cs.primary,
      style: TextStyle(color: context.cs.onSurface, fontSize: 16),
      decoration: InputDecoration(
        isDense: true,
        border: InputBorder.none,
        hintText: _tabIndex == 1
            ? 'catalog_search_placeholder'.tr()
            : 'search_characters'.tr(),
        hintStyle: TextStyle(color: context.cs.onSurfaceVariant, fontSize: 16),
      ),
    );
  }

  Widget _buildTabBar() {
    // Rendered in the shell header's `below` slot, which already supplies the
    // horizontal padding — only the gap under the app bar is needed here.
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: GlazeTabBar(
        tabs: [
          GlazeTabItem(
            label: 'tab_my_characters'.tr(),
            icon: Icons.person_rounded,
          ),
          GlazeTabItem(label: 'tab_catalog'.tr(), icon: Icons.public_rounded),
        ],
        activeIndex: _tabIndex,
        onChanged: (i) {
          // Tapping the already-active tab scrolls its list back to the top.
          if (i == _tabIndex) {
            _scrollToTop();
            _showHeader();
            return;
          }
          ref.read(characterSelectionProvider.notifier).clear();
          _showHeader();
          setState(() {
            _tabIndex = i;
            if (_searchExpanded) _applySearchForActiveTab();
          });
          refreshShellHeader();
        },
      ),
    );
  }

  Future<void> _showAddSheet(BuildContext context, WidgetRef ref) async {
    await GlazeBottomSheet.show<void>(
      context,
      title: 'Add Character',
      items: [
        BottomSheetItem(
          icon: Icons.add_rounded,
          label: 'action_create_new'.tr(),
          onTap: () {
            Navigator.of(context, rootNavigator: true).pop();
            context.push('/character/create');
          },
        ),
        BottomSheetItem(
          icon: Icons.file_open_outlined,
          label: 'action_import'.tr(),
          onTap: () {
            Navigator.of(context, rootNavigator: true).pop();
            _importCharacter(context, ref);
          },
        ),
        BottomSheetItem(
          icon: Icons.link_rounded,
          label: 'action_import_janitor'.tr(),
          onTap: () {
            Navigator.of(context, rootNavigator: true).pop();
            GlazeBottomSheet.show<void>(
              context,
              title: 'action_import_janitor'.tr(),
              child: const ImportUrlDialog(),
            );
          },
        ),
        BottomSheetItem(
          icon: Icons.create_new_folder_rounded,
          label: 'folder_new'.tr(),
          onTap: () {
            Navigator.of(context, rootNavigator: true).pop();
            _createFolder(context, ref);
          },
        ),
      ],
    );
  }

  void _createFolder(BuildContext context, WidgetRef ref) {
    GlazeBottomSheet.show<void>(
      context,
      title: 'folder_create_title'.tr(),
      child: FolderNameDialog(
        confirmLabel: 'btn_create'.tr(),
        onSubmit: (name) =>
            ref.read(characterFolderRepoProvider).create(name: name),
      ),
    );
  }

  // ── Multi-select bulk actions ────────────────────────────────────────────

  void _showSelectionActions(
    BuildContext context,
    CharacterSelectionState selection,
  ) {
    GlazeBottomSheet.show<void>(
      context,
      title: '${selection.count} ${'selected_count'.tr()}',
      items: [
        BottomSheetItem(
          icon: Icons.share_rounded,
          label: 'action_export'.tr(),
          onTap: () {
            Navigator.of(context, rootNavigator: true).pop();
            _massExport(context, selection);
          },
        ),
        BottomSheetItem(
          icon: Icons.favorite,
          label: 'action_add_fav'.tr(),
          onTap: () {
            Navigator.of(context, rootNavigator: true).pop();
            _addSelectedToFavorites(context, selection);
          },
        ),
        BottomSheetItem(
          icon: Icons.create_new_folder_outlined,
          label: 'action_add_to_folder'.tr(),
          onTap: () {
            Navigator.of(context, rootNavigator: true).pop();
            _addSelectedToFolder(context, selection);
          },
        ),
        BottomSheetItem(
          icon: Icons.delete_rounded,
          label: 'action_delete'.tr(),
          isDestructive: true,
          onTap: () {
            Navigator.of(context, rootNavigator: true).pop();
            _confirmDeleteSelected(context, selection);
          },
        ),
      ],
    );
  }

  void _massExport(BuildContext context, CharacterSelectionState selection) {
    final ids = {...selection.ids};
    GlazeBottomSheet.show<void>(
      context,
      title: 'action_export'.tr(),
      items: [
        BottomSheetItem(
          icon: Icons.image_outlined,
          label: 'label_export_png'.tr(),
          onTap: () {
            Navigator.of(context, rootNavigator: true).pop();
            _runMassExport(context, ids, 'png');
          },
        ),
        BottomSheetItem(
          icon: Icons.code_rounded,
          label: 'label_export_json'.tr(),
          onTap: () {
            Navigator.of(context, rootNavigator: true).pop();
            _runMassExport(context, ids, 'json');
          },
        ),
        BottomSheetItem(
          icon: Icons.folder_zip_rounded,
          label: 'label_export_zip'.tr(),
          onTap: () {
            Navigator.of(context, rootNavigator: true).pop();
            _runMassExport(context, ids, 'zip');
          },
        ),
      ],
    );
  }

  Future<void> _runMassExport(
    BuildContext context,
    Set<String> ids,
    String format,
  ) async {
    final all = ref.read(charactersProvider).value ?? const [];
    final chars = all.where((c) => ids.contains(c.id)).toList();
    int exported = 0;
    String? lastError;
    for (final c in chars) {
      try {
        await exportCharacterToFile(ref: ref, character: c, format: format);
        exported++;
      } catch (e) {
        lastError = '$e';
      }
    }
    if (!context.mounted) return;
    ref.read(characterSelectionProvider.notifier).clear();
    if (exported > 0) {
      GlazeToast.show(
        context,
        'Exported $exported ${'count_characters'.plural(exported)}',
      );
    } else if (lastError != null) {
      GlazeToast.show(context, lastError);
    }
  }

  Future<void> _addSelectedToFavorites(
    BuildContext context,
    CharacterSelectionState selection,
  ) async {
    final all = ref.read(charactersProvider).value ?? const [];
    final notifier = ref.read(charactersProvider.notifier);
    for (final c in all.where((c) => selection.contains(c.id))) {
      if (!c.fav) await notifier.save(c.copyWith(fav: true));
    }
    if (!context.mounted) return;
    ref.read(characterSelectionProvider.notifier).clear();
    GlazeToast.show(context, 'action_add_fav'.tr());
  }

  void _addSelectedToFolder(
    BuildContext context,
    CharacterSelectionState selection,
  ) {
    final ids = {...selection.ids};
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AddCharactersToFolderSheet(
        characterIds: ids,
        onDone: () =>
            ref.read(characterSelectionProvider.notifier).clear(),
      ),
    );
  }

  void _confirmDeleteSelected(
    BuildContext context,
    CharacterSelectionState selection,
  ) {
    final ids = {...selection.ids};
    final count = ids.length;
    GlazeBottomSheet.show<void>(
      context,
      title: 'action_delete'.tr(),
      bigInfo: BottomSheetBigInfo(
        icon: Icons.delete_outline,
        description:
            'Delete $count ${'count_characters'.plural(count)}? This cannot be undone.',
      ),
      items: [
        BottomSheetItem(
          label: 'btn_delete'.tr(),
          isDestructive: true,
          centered: true,
          onTap: () async {
            Navigator.of(context, rootNavigator: true).pop();
            final notifier = ref.read(charactersProvider.notifier);
            for (final id in ids) {
              await notifier.remove(id);
            }
            ref.read(characterSelectionProvider.notifier).clear();
          },
        ),
        BottomSheetItem(
          label: 'btn_cancel'.tr(),
          centered: true,
          onTap: () => Navigator.of(context, rootNavigator: true).pop(),
        ),
      ],
    );
  }

  Future<void> _importCharacter(BuildContext context, WidgetRef ref) async {
    try {
      if (Platform.isIOS) {
        final source = await GlazeBottomSheet.show<_ImportSource>(
          context,
          title: 'onboarding_action_import'.tr(),
          items: [
            BottomSheetItem(
              icon: Icons.photo_library,
              label: 'From Gallery',
              onTap: () => Navigator.of(
                context,
                rootNavigator: true,
              ).pop(_ImportSource.gallery),
            ),
            BottomSheetItem(
              icon: Icons.folder_open,
              label: 'From Files',
              onTap: () => Navigator.of(
                context,
                rootNavigator: true,
              ).pop(_ImportSource.files),
            ),
          ],
        );
        if (source == null) return;
        if (!context.mounted) return;
        if (source == _ImportSource.gallery) {
          await _importFromGallery(context, ref);
        } else {
          await _importFromFiles(context, ref);
        }
      } else {
        await _importFromFiles(context, ref);
      }
    } catch (e) {
      if (!context.mounted) return;
      GlazeErrorDialog.show(context, e, prefix: 'Import failed: ');
    }
  }

  Future<void> _importFromGallery(BuildContext context, WidgetRef ref) async {
    final picker = ImagePicker();
    final images = await picker.pickMultiImage();
    if (!context.mounted) return;
    if (images.isEmpty) return;

    final importer = await ref.read(characterImporterProvider.future);
    final notifier = ref.read(charactersProvider.notifier);
    final galleryService = await ref.read(galleryServiceProvider.future);
    int imported = 0;
    String? lastError;

    for (final image in images) {
      try {
        final bytes = await File(image.path).readAsBytes();
        final r = await importer.importFromBytes(bytes, image.name);
        await notifier.add(r.character);
        if (r.characterBookData != null) {
          final lorebook = convertCharacterBook(
            r.characterBookData!,
            r.character.id,
          );
          debugPrint(
            '[character_import] gallery saving_lorebook id=${lorebook.id} '
            'name=${lorebook.name} entries=${lorebook.entries.length} '
            'character=${r.character.id}',
          );
          await ref.read(lorebooksProvider.notifier).put(lorebook);
        } else {
          debugPrint(
            '[character_import] gallery no_lorebook character=${r.character.id}',
          );
        }
        if (r.galleryImages != null) {
          for (final img in r.galleryImages!) {
            await galleryService.addImageBytes(
              r.character.id,
              img.bytes,
              img.ext,
              label: img.label,
            );
          }
        }
        imported++;
      } catch (e) {
        lastError = 'Failed to import ${image.name}: $e';
      }
    }

    if (!context.mounted) return;
    if (imported > 0) {
      GlazeToast.show(
        context,
        '${'import_success'.tr()}: $imported ${'count_characters'.plural(imported)}',
      );
    } else if (lastError != null) {
      GlazeToast.show(context, lastError);
    }
  }

  Future<void> _importFromFiles(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.pickFiles(
      type: Platform.isIOS ? FileType.any : FileType.custom,
      allowedExtensions: Platform.isIOS
          ? null
          : ['png', 'json', 'charx', 'zip'],
      allowMultiple: true,
      withData: true,
    );
    if (!context.mounted) return;
    if (result == null || result.files.isEmpty) return;

    final importer = await ref.read(characterImporterProvider.future);
    final notifier = ref.read(charactersProvider.notifier);
    final galleryService = await ref.read(galleryServiceProvider.future);
    int imported = 0;
    String? lastError;

    for (final file in result.files) {
      try {
        CharacterImportResult r;
        if (file.bytes != null) {
          r = await importer.importFromBytes(file.bytes!, file.name);
        } else if (file.path != null) {
          r = await importer.importFromFile(file.path!);
        } else {
          continue;
        }
        await notifier.add(r.character);
        if (r.characterBookData != null) {
          final lorebook = convertCharacterBook(
            r.characterBookData!,
            r.character.id,
          );
          debugPrint(
            '[character_import] files saving_lorebook id=${lorebook.id} '
            'name=${lorebook.name} entries=${lorebook.entries.length} '
            'character=${r.character.id}',
          );
          await ref.read(lorebooksProvider.notifier).put(lorebook);
        } else {
          debugPrint(
            '[character_import] files no_lorebook character=${r.character.id}',
          );
        }
        if (r.galleryImages != null) {
          for (final img in r.galleryImages!) {
            await galleryService.addImageBytes(
              r.character.id,
              img.bytes,
              img.ext,
              label: img.label,
            );
          }
        }
        imported++;
      } catch (e) {
        lastError = 'Failed to import ${file.name}: $e';
      }
    }

    if (!context.mounted) return;
    if (imported > 0) {
      GlazeToast.show(
        context,
        '${'import_success'.tr()}: $imported ${'count_characters'.plural(imported)}',
      );
    } else if (lastError != null) {
      GlazeToast.show(context, lastError);
    }
  }
}

class _AddButton extends StatelessWidget {
  final VoidCallback onTap;
  const _AddButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: context.cs.primary,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.add_rounded, color: Colors.white, size: 24),
            const SizedBox(width: 8),
            Text(
              'btn_add'.tr(),
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom selection bar shown while multi-selecting characters. Mirrors the
/// chat input bar's selection mode: a glass pill with a cancel button, the
/// selected count, and a "more" button that opens the bulk-actions sheet.
class _SelectionBar extends StatelessWidget {
  final int count;
  final VoidCallback onCancel;
  final VoidCallback onMore;

  const _SelectionBar({
    required this.count,
    required this.onCancel,
    required this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      elevation: 0,
      borderRadius: BorderRadius.circular(28),
      child: GlassSurface(
        borderRadius: BorderRadius.circular(28),
        tint: context.cs.surface,
        border: Border.all(color: context.cs.primary.withValues(alpha: 0.18)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Row(
            children: [
              const SizedBox(width: 8),
              _CircleIconBtn(icon: Icons.close_rounded, onTap: onCancel),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '$count ${'selected_count'.tr()}',
                  style: TextStyle(
                    color: context.cs.onSurface,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              _CircleIconBtn(
                icon: Icons.more_horiz_rounded,
                onTap: count > 0 ? onMore : null,
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _CircleIconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _CircleIconBtn({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 40,
        height: 40,
        child: GlassSurface(
          borderRadius: BorderRadius.circular(20),
          tint: context.cs.surface,
          border: Border.all(
            color: context.cs.primary.withValues(alpha: 0.18),
          ),
          child: Center(
            child: Icon(
              icon,
              size: 20,
              color: onTap != null
                  ? context.cs.primary
                  : context.cs.onSurfaceVariant.withValues(alpha: 0.5),
            ),
          ),
        ),
      ),
    );
  }
}

enum _ImportSource { gallery, files }
