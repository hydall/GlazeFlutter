import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/models/character.dart';
import '../../core/services/character_book_converter.dart';
import '../../core/services/character_importer.dart';
import '../../core/state/character_provider.dart';
import '../../core/state/db_provider.dart';
import '../../shared/shell/nav_height_provider.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/widgets/glaze_bottom_sheet.dart';
import '../../shared/widgets/glaze_scaffold.dart';
import '../../shared/widgets/glaze_tab_bar.dart';
import '../../shared/widgets/glaze_toast.dart';
import '../catalog/widgets/widgets.dart';
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
  bool _showCatalog = false;
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final characters = ref.watch(charactersProvider);

    final navHeight = ref.watch(navHeightProvider);

    final topPad = MediaQuery.of(context).padding.top + 74.0;

    return Scaffold(
      backgroundColor: context.colors.background,
      body: Stack(
        children: [
          Positioned.fill(
            child: _showCatalog
                ? CatalogGrid(
                    topPadding: topPad,
                    bottomPadding: navHeight + 20,
                    tabBar: _buildTabBar(),
                  )
                : characters.when(
                    loading: () => Center(
                      child: CircularProgressIndicator(color: context.colors.accent),
                    ),
                    error: (e, _) => Center(
                      child: Text(
                        'Error: $e',
                        style: TextStyle(color: context.colors.textSecondary),
                      ),
                    ),
                    data: (chars) {
                      if (chars.isEmpty) {
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
                      var filtered = chars;
                      if (_searchQuery.isNotEmpty) {
                        final q = _searchQuery.toLowerCase();
                        filtered = filtered
                            .where(
                              (c) =>
                                  c.fav || c.name.toLowerCase().contains(q),
                            )
                            .toList();
                      }
                      final sorted = _sortChars(filtered);
                      return CharacterGrid(
                        characters: sorted,
                        sortBy: _sortBy,
                        sortDir: _sortDir,
                        topPadding: topPad,
                        bottomPadding: navHeight + 20,
                        tabBar: _buildTabBar(),
                        onSortDirToggle: () => setState(() {
                          _sortDir = _sortDir == SortDir.asc
                              ? SortDir.desc
                              : SortDir.asc;
                        }),
                        onSortTypeChanged: (t) => setState(() => _sortBy = t),
                      );
                    },
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
                      title: 'Characters',
                      actions: [
                        SizedBox(
                          width: 44,
                          height: 44,
                          child: IconButton(
                            icon: const Icon(Icons.search_rounded, size: 22),
                            color: context.colors.accent,
                            onPressed: () async {
                              final query = await showSearch<String>(
                                context: context,
                                delegate: _CharacterSearchDelegate(ref),
                              );
                              if (query != null)
                                setState(() => _searchQuery = query);
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (!_showCatalog)
            Positioned(
              right: 16,
              bottom: navHeight + 16,
              child: _AddButton(onTap: () => _showAddSheet(context, ref)),
            ),
        ],
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
        activeIndex: _showCatalog ? 1 : 0,
        onChanged: (i) => setState(() => _showCatalog = i == 1),
      ),
    );
  }

  List<Character> _sortChars(List<Character> chars) {
    final list = List<Character>.from(chars);
    list.sort((a, b) {
      if (a.fav != b.fav) return a.fav ? -1 : 1;
      final cmp = switch (_sortBy) {
        SortType.name => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        SortType.date => a.updatedAt.compareTo(b.updatedAt),
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
          label: 'Add new',
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
            showDialog(
              context: context,
              builder: (_) => const ImportUrlDialog(),
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
              onTap: () =>
                  Navigator.of(context, rootNavigator: true).pop(_ImportSource.gallery),
            ),
            BottomSheetItem(
              icon: Icons.folder_open,
              label: 'From Files',
              onTap: () =>
                  Navigator.of(context, rootNavigator: true).pop(_ImportSource.files),
            ),
          ],
        );
        if (source == null) return;
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
    final lorebookRepo = ref.read(lorebookRepoProvider);
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
          await lorebookRepo.put(lorebook);
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
      allowedExtensions: Platform.isIOS ? null : ['png', 'json', 'charx', 'zip'],
      allowMultiple: true,
    );
    if (!context.mounted) return;
    if (result == null || result.files.isEmpty) return;

    final importer = await ref.read(characterImporterProvider.future);
    final notifier = ref.read(charactersProvider.notifier);
    final lorebookRepo = ref.read(lorebookRepoProvider);
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
          await lorebookRepo.put(lorebook);
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

class _CharacterSearchDelegate extends SearchDelegate<String> {
  final WidgetRef ref;
  _CharacterSearchDelegate(this.ref);

  @override
  ThemeData appBarTheme(BuildContext context) => Theme.of(context).copyWith(
    appBarTheme: AppBarTheme(backgroundColor: context.colors.background),
  );

  @override
  List<Widget> buildActions(BuildContext context) => [
    IconButton(icon: const Icon(Icons.clear), onPressed: () => query = ''),
  ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
    icon: const Icon(Icons.arrow_back),
    onPressed: () => close(context, ''),
  );

  @override
  Widget buildResults(BuildContext context) => _buildList(context);

  @override
  Widget buildSuggestions(BuildContext context) => _buildList(context);

  Widget _buildList(BuildContext context) {
    final chars = ref.read(charactersProvider).valueOrNull ?? [];
    final q = query.toLowerCase();
    final filtered = chars
        .where((c) => c.fav || c.name.toLowerCase().contains(q))
        .toList()
      ..sort((a, b) {
        if (a.fav != b.fav) return a.fav ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

    if (filtered.isEmpty) {
      return Center(
        child: Text(
          'No characters found',
          style: TextStyle(color: context.colors.textSecondary),
        ),
      );
    }

    return ListView.builder(
      itemCount: filtered.length,
      itemBuilder: (ctx, i) {
        final c = filtered[i];
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: context.colors.accent.withValues(alpha: 0.15),
            backgroundImage: c.avatarPath != null
                ? FileImage(File(c.avatarPath!))
                : null,
            child: c.avatarPath == null
                ? Text(
                    c.name[0].toUpperCase(),
                    style: TextStyle(color: context.colors.accent),
                  )
                : null,
          ),
          title: Text(
            c.name,
            style: TextStyle(color: context.colors.textPrimary),
          ),
          subtitle: c.description != null
              ? Text(
                  c.description!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.colors.textSecondary,
                    fontSize: 12,
                  ),
                )
              : null,
          onTap: () => close(ctx, c.name),
        );
      },
    );
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
          color: context.colors.accent,
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
