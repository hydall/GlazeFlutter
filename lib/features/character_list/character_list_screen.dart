import 'dart:async';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import 'package:go_router/go_router.dart';

import '../../core/db/repositories/character_repo.dart';
import '../../core/models/character.dart';
import '../../core/services/character_book_converter.dart';
import '../../core/services/character_importer.dart';
import '../../core/state/character_provider.dart';
import '../../core/state/db_provider.dart';
import '../../core/state/lorebook_provider.dart';
import '../../shared/shell/nav_height_provider.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/widgets/glaze_bottom_sheet.dart';
import '../../shared/widgets/glaze_scaffold.dart';
import '../../shared/widgets/glaze_tab_bar.dart';
import '../../shared/widgets/glaze_toast.dart';
import '../catalog/catalog_provider.dart';
import '../catalog/widgets/widgets.dart';
import '../character_gallery/gallery_provider.dart';
import '../picks/widgets/picks_grid.dart';
import '../settings/app_settings_provider.dart';
import 'widgets/widgets.dart';

class CharacterListScreen extends ConsumerStatefulWidget {
  const CharacterListScreen({super.key});

  @override
  ConsumerState<CharacterListScreen> createState() =>
      _CharacterListScreenState();
}

class _CharacterListScreenState extends ConsumerState<CharacterListScreen> {
  SortType _sortBy = SortType.date;
  SortDir _sortDir = SortDir.desc;
  int _tabIndex = 0;
  String _searchQuery = '';
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

  @override
  void dispose() {
    _catalogDebounce?.cancel();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _openSearch() {
    setState(() => _searchExpanded = true);
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
  Widget build(BuildContext context) {
    final navHeight = ref.watch(navHeightProvider);

    final topPad = MediaQuery.of(context).padding.top + 74.0;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(
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
              child: _tabIndex == 2
                  ? PicksGrid(
                      key: const ValueKey('picks_grid'),
                      topPadding: MediaQuery.of(context).padding.top + 76.0,
                      bottomPadding: navHeight + 20,
                      onFolderChanged:
                          (title, description, canGoBack, goBackFn) {
                            setState(() {
                              _picksTitle = title;
                              _picksCanGoBack = canGoBack;
                              _picksGoBackFn = goBackFn;
                            });
                          },
                    )
                  : _tabIndex == 1
                  ? CatalogGrid(
                      key: const ValueKey('catalog_grid'),
                      topPadding: topPad,
                      bottomPadding: navHeight + 20,
                      tabBar: _buildTabBar(),
                    )
                  : KeyedSubtree(
                      key: const ValueKey('my_characters'),
                      child: _buildMyCharacters(context, topPad, navHeight),
                    ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Column(
              children: [
                SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                    child: GlazeAppBar(
                      title: (_searchExpanded && _tabIndex != 2)
                          ? null
                          : (_tabIndex == 2 ? _picksTitle : 'Characters'),
                      titleWidget: (_searchExpanded && _tabIndex != 2)
                          ? _buildSearchField(context)
                          : null,
                      showBack: _tabIndex == 2,
                      onBack: _tabIndex == 2
                          ? (_picksCanGoBack && _picksGoBackFn != null
                                ? _picksGoBackFn
                                : () => setState(() => _tabIndex = 0))
                          : null,
                      actions: _tabIndex == 2
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
                                  onPressed: _searchExpanded
                                      ? _closeSearch
                                      : _openSearch,
                                ),
                              ),
                            ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_tabIndex == 0)
            Positioned(
              right: 16,
              bottom: navHeight + 16,
              child: _AddButton(onTap: () => _showAddSheet(context, ref)),
            ),
        ],
      ),
    );
  }

  Widget _buildMyCharacters(
    BuildContext context,
    double topPad,
    double navHeight,
  ) {
    final showOurPicks =
        _searchQuery.isEmpty &&
        (ref.watch(appSettingsProvider).value?.showOurPicks ?? true);

    if (_searchQuery.isNotEmpty) {
      return _buildSearchResults(context, topPad, navHeight);
    }

    final key = InfiniteCharactersKey(sort: _sortField, dir: _sortDirEnum);
    final infinite = ref.watch(infiniteCharactersProvider(key));

    return infinite.when(
      loading: () =>
          Center(child: CircularProgressIndicator(color: context.cs.primary)),
      error: (e, _) => Center(
        child: Text(
          'Error: $e',
          style: TextStyle(color: context.cs.onSurfaceVariant),
        ),
      ),
      data: (state) {
        if (state.totalCount == 0 && !showOurPicks) {
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: SizedBox(height: topPad)),
              SliverToBoxAdapter(child: _buildTabBar()),
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
            tabBar: _buildTabBar(),
            showOurPicksCard: showOurPicks,
            onOurPicksTap: () => setState(() => _tabIndex = 2),
            onOurPicksHide: () {
              final s = ref.read(appSettingsProvider).value;
              if (s != null) {
                ref
                    .read(appSettingsProvider.notifier)
                    .save(s.copyWith(showOurPicks: false));
                GlazeToast.show(context, 'our_picks_hidden_toast'.tr());
              }
            },
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

  Widget _buildSearchResults(
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
          'Error: $e',
          style: TextStyle(color: context.cs.onSurfaceVariant),
        ),
      ),
      data: (all) {
        final q = _searchQuery.toLowerCase();
        final filtered = all
            .where((c) => c.fav || c.name.toLowerCase().contains(q))
            .toList();
        final sorted = _sortChars(filtered);

        if (sorted.isEmpty) {
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: SizedBox(height: topPad)),
              SliverToBoxAdapter(child: _buildTabBar()),
              SliverFillRemaining(
                child: Center(
                  child: Text(
                    'No characters found',
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
          tabBar: _buildTabBar(),
          onSortDirToggle: () => setState(() {
            _sortDir = _sortDir == SortDir.asc ? SortDir.desc : SortDir.asc;
          }),
          onSortTypeChanged: (t) => setState(() => _sortBy = t),
        );
      },
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
        hintText: _tabIndex == 1 ? 'Search catalog' : 'Search characters',
        hintStyle: TextStyle(
          color: context.cs.onSurfaceVariant,
          fontSize: 16,
        ),
      ),
    );
  }

  Widget _buildTabBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: GlazeTabBar(
        tabs: const [
          GlazeTabItem(label: 'My Characters', icon: Icons.person_rounded),
          GlazeTabItem(label: 'Discover', icon: Icons.public_rounded),
        ],
        activeIndex: _tabIndex == 2 ? 0 : _tabIndex,
        onChanged: (i) => setState(() {
          _tabIndex = i;
          if (_searchExpanded) _applySearchForActiveTab();
        }),
      ),
    );
  }

  List<Character> _sortChars(List<Character> chars) {
    final list = List<Character>.from(chars);
    final effectiveSort = _sortBy == SortType.lastChat
        ? SortType.name
        : _sortBy;
    list.sort((a, b) {
      if (a.fav != b.fav) return a.fav ? -1 : 1;
      final cmp = switch (effectiveSort) {
        SortType.name => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        SortType.date => a.createdAt.compareTo(b.createdAt),
        SortType.lastChat => a.name.toLowerCase().compareTo(
          b.name.toLowerCase(),
        ),
      };
      if (cmp != 0) return _sortDir == SortDir.desc ? -cmp : cmp;
      return a.id.compareTo(b.id);
    });
    return list;
  }

  Future<void> _showAddSheet(BuildContext context, WidgetRef ref) async {
    await GlazeBottomSheet.show<void>(
      context,
      title: 'Add Character',
      items: [
        BottomSheetItem(
          icon: Icons.add_rounded,
          label: 'Add New',
          onTap: () {
            Navigator.of(context, rootNavigator: true).pop();
            context.push('/character/create');
          },
        ),
        BottomSheetItem(
          icon: Icons.file_open_outlined,
          label: 'Import from File',
          onTap: () {
            Navigator.of(context, rootNavigator: true).pop();
            _importCharacter(context, ref);
          },
        ),
        BottomSheetItem(
          icon: Icons.link_rounded,
          label: 'Import from URL',
          onTap: () {
            Navigator.of(context, rootNavigator: true).pop();
            GlazeBottomSheet.show<void>(
              context,
              title: 'Import by URL',
              child: const ImportUrlDialog(),
            );
          },
        ),
      ],
    );
  }

  Future<void> _importCharacter(BuildContext context, WidgetRef ref) async {
    try {
      if (Platform.isIOS) {
        final source = await GlazeBottomSheet.show<_ImportSource>(
          context,
          title: 'Import',
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
      GlazeToast.error(context, 'Import failed: ', e);
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
          debugPrint('[character_import] gallery no_lorebook character=${r.character.id}');
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
        'Imported $imported character${imported > 1 ? "s" : ""}',
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
          debugPrint('[character_import] files no_lorebook character=${r.character.id}');
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
        'Imported $imported character${imported > 1 ? "s" : ""}',
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
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_rounded, color: Colors.white, size: 24),
            SizedBox(width: 8),
            Text(
              'Add',
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

enum _ImportSource { gallery, files }
