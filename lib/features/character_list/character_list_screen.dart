import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/character.dart';
import '../../core/services/character_book_converter.dart';
import '../../core/services/character_importer.dart';
import '../../core/state/character_provider.dart';
import '../../core/state/db_provider.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/widgets/glaze_scaffold.dart';
import '../../shared/widgets/glaze_tab_bar.dart';
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

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
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
                      color: AppColors.accent,
                      onPressed: () async {
                        final query = await showSearch<String>(
                          context: context,
                          delegate: _CharacterSearchDelegate(ref),
                        );
                        if (query != null) setState(() => _searchQuery = query);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: GlazeTabBar(
              tabs: const [
                GlazeTabItem(label: 'My Characters', icon: Icons.person_rounded),
                GlazeTabItem(label: 'Discover', icon: Icons.public_rounded),
              ],
              activeIndex: _showCatalog ? 1 : 0,
              onChanged: (i) => setState(() => _showCatalog = i == 1),
            ),
          ),
          Expanded(
            child: _showCatalog
                ? const CatalogGrid()
                : characters.when(
                    loading: () => const Center(
                      child: CircularProgressIndicator(color: AppColors.accent),
                    ),
                    error: (e, _) => Center(
                      child: Text('Error: $e',
                          style: const TextStyle(color: AppColors.textSecondary)),
                    ),
                    data: (chars) {
                      if (chars.isEmpty) {
                        return EmptyCharacterState(
                          onImport: () => _importCharacter(context, ref),
                        );
                      }
                      var filtered = chars;
                      if (_searchQuery.isNotEmpty) {
                        final q = _searchQuery.toLowerCase();
                        filtered = chars.where((c) =>
                          c.name.toLowerCase().contains(q) ||
                          (c.description ?? '').toLowerCase().contains(q) ||
                          (c.creator ?? '').toLowerCase().contains(q) ||
                          c.tags.any((t) => t.toLowerCase().contains(q)),
                        ).toList();
                      }
                      final sorted = _sortChars(filtered);
                      return CharacterGrid(
                        characters: sorted,
                        sortBy: _sortBy,
                        sortDir: _sortDir,
                        onSortDirToggle: () => setState(() {
                          _sortDir =
                              _sortDir == SortDir.asc ? SortDir.desc : SortDir.asc;
                        }),
                        onSortTypeChanged: (t) => setState(() => _sortBy = t),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: _showCatalog
          ? _ImportUrlFAB(onTap: () {
              showDialog(
                context: context,
                builder: (_) => const ImportUrlDialog(),
              );
            })
          : _AddButton(onTap: () => _importCharacter(context, ref)),
    );
  }

  List<Character> _sortChars(List<Character> chars) {
    final list = List<Character>.from(chars);
    list.sort((a, b) {
      final cmp = switch (_sortBy) {
        SortType.name => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        SortType.date => a.updatedAt.compareTo(b.updatedAt),
      };
      return _sortDir == SortDir.desc ? -cmp : cmp;
    });
    return list;
  }

  Future<void> _importCharacter(BuildContext context, WidgetRef ref) async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['png', 'json', 'charx', 'zip'],
        allowMultiple: true,
      );
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
            final lorebook = convertCharacterBook(r.characterBookData!, r.character.id);
            await lorebookRepo.put(lorebook);
          }
          imported++;
        } catch (e) {
          lastError = 'Failed to import ${file.name}: $e';
        }
      }

      if (!context.mounted) return;
      if (imported > 0) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Imported $imported character${imported > 1 ? 's' : ''}'),
          backgroundColor: AppColors.accent,
        ));
      } else if (lastError != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(lastError)));
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Import failed: $e')));
    }
  }
}

class _CharacterSearchDelegate extends SearchDelegate<String> {
  final WidgetRef ref;
  _CharacterSearchDelegate(this.ref);

  @override
  ThemeData appBarTheme(BuildContext context) =>
      Theme.of(context).copyWith(appBarTheme: const AppBarTheme(backgroundColor: AppColors.background));

  @override
  List<Widget> buildActions(BuildContext context) => [
    IconButton(icon: const Icon(Icons.clear), onPressed: () => query = ''),
  ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
    icon: const Icon(Icons.arrow_back), onPressed: () => close(context, ''),
  );

  @override
  Widget buildResults(BuildContext context) => _buildList();

  @override
  Widget buildSuggestions(BuildContext context) => _buildList();

  Widget _buildList() {
    final chars = ref.read(charactersProvider).valueOrNull ?? [];
    final q = query.toLowerCase();
    final filtered = chars.where((c) =>
      c.name.toLowerCase().contains(q) ||
      (c.description ?? '').toLowerCase().contains(q) ||
      (c.creator ?? '').toLowerCase().contains(q) ||
      c.tags.any((t) => t.toLowerCase().contains(q)),
    ).toList();

    if (filtered.isEmpty) {
      return const Center(child: Text('No characters found', style: TextStyle(color: AppColors.textSecondary)));
    }

    return ListView.builder(
      itemCount: filtered.length,
      itemBuilder: (ctx, i) {
        final c = filtered[i];
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: AppColors.accent.withValues(alpha: 0.15),
            backgroundImage: c.avatarPath != null ? FileImage(File(c.avatarPath!)) : null,
            child: c.avatarPath == null ? Text(c.name[0].toUpperCase(), style: const TextStyle(color: AppColors.accent)) : null,
          ),
          title: Text(c.name, style: const TextStyle(color: AppColors.textPrimary)),
          subtitle: c.description != null ? Text(c.description!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)) : null,
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
          color: AppColors.accent,
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
            Text('Add',
                style: TextStyle(
                    color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}

class _ImportUrlFAB extends StatelessWidget {
  final VoidCallback onTap;
  const _ImportUrlFAB({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: AppColors.accent,
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
            Icon(Icons.link_rounded, color: Colors.white, size: 22),
            SizedBox(width: 8),
            Text('Import URL',
                style: TextStyle(
                    color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}
