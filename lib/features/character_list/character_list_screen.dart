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
                      onPressed: () {},
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
                ? const Center(
                    child: Text('Catalog — coming soon',
                        style: TextStyle(color: AppColors.textSecondary)),
                  )
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
                      final sorted = _sortChars(chars);
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
          ? null
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

      final importer = ref.read(characterImporterProvider);
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
