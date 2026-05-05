import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/character.dart';
import '../../core/state/character_provider.dart';
import '../../core/state/db_provider.dart';
import '../../shared/theme/app_colors.dart';

enum _SortType { name, date }
enum _SortDir { asc, desc }

class CharacterListScreen extends ConsumerStatefulWidget {
  const CharacterListScreen({super.key});

  @override
  ConsumerState<CharacterListScreen> createState() =>
      _CharacterListScreenState();
}

class _CharacterListScreenState extends ConsumerState<CharacterListScreen> {
  _SortType _sortBy = _SortType.date;
  _SortDir _sortDir = _SortDir.desc;

  @override
  Widget build(BuildContext context) {
    final characters = ref.watch(charactersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Characters'),
        actions: [
          _sortButton(),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _importCharacter(context, ref),
          ),
        ],
      ),
      body: characters.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (chars) {
          if (chars.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.person_add,
                      size: 64, color: AppColors.textSecondary),
                  const SizedBox(height: 16),
                  const Text('No characters yet'),
                  const SizedBox(height: 8),
                  FilledButton.tonal(
                    onPressed: () => _importCharacter(context, ref),
                    child: const Text('Import Character'),
                  ),
                ],
              ),
            );
          }
          final sorted = _sortChars(chars);
          return GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.78,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: sorted.length,
            itemBuilder: (_, i) =>
                _CharacterCard(character: sorted[i]),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _importCharacter(context, ref),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _sortButton() {
    return PopupMenuButton<String>(
      icon: Icon(
        _sortDir == _SortDir.asc
            ? Icons.sort_by_alpha
            : Icons.sort,
      ),
      onSelected: (value) {
        setState(() {
          if (value == 'name') {
            _sortBy = _SortType.name;
          } else if (value == 'date') {
            _sortBy = _SortType.date;
          } else if (value == 'toggle_dir') {
            _sortDir =
                _sortDir == _SortDir.asc ? _SortDir.desc : _SortDir.asc;
          }
        });
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'name',
          child: Row(children: [
            if (_sortBy == _SortType.name) const Icon(Icons.check, size: 16),
            const SizedBox(width: 8),
            const Text('Sort by Name'),
          ]),
        ),
        PopupMenuItem(
          value: 'date',
          child: Row(children: [
            if (_sortBy == _SortType.date) const Icon(Icons.check, size: 16),
            const SizedBox(width: 8),
            const Text('Sort by Date'),
          ]),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'toggle_dir',
          child: Text(_sortDir == _SortDir.asc
              ? 'Switch to Descending'
              : 'Switch to Ascending'),
        ),
      ],
    );
  }

  List<Character> _sortChars(List<Character> chars) {
    final list = List<Character>.from(chars);
    list.sort((a, b) {
      int cmp;
      switch (_sortBy) {
        case _SortType.name:
          cmp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        case _SortType.date:
          cmp = a.updatedAt.compareTo(b.updatedAt);
      }
      return _sortDir == _SortDir.desc ? -cmp : cmp;
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
      int imported = 0;
      String? lastError;

      for (final file in result.files) {
        try {
          if (file.bytes != null) {
            final importResult =
                await importer.importFromBytes(file.bytes!, file.name);
            await notifier.add(importResult.character);
            imported++;
          } else if (file.path != null) {
            final importResult =
                await importer.importFromFile(file.path!);
            await notifier.add(importResult.character);
            imported++;
          }
        } catch (e) {
          lastError = 'Failed to import ${file.name}: $e';
        }
      }

      if (context.mounted) {
        if (imported > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'Imported $imported character${imported > 1 ? 's' : ''}'),
              backgroundColor: AppColors.accent,
            ),
          );
        } else if (lastError != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(lastError)),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import failed: $e')),
        );
      }
    }
  }
}

class _CharacterCard extends ConsumerWidget {
  final Character character;
  const _CharacterCard({required this.character});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.go('/character/${character.id}'),
        onLongPress: () => _showActions(context, ref),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 3,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildAvatar(),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: _actionMenu(context, ref),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    character.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  if (character.description != null &&
                      character.description!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        character.description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11, color: AppColors.textSecondary),
                      ),
                    ),
                  Row(
                    children: [
                      if (character.tags.isNotEmpty)
                        Expanded(
                          child: Text(
                            character.tags.take(2).join(', '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 10, color: AppColors.accent),
                          ),
                        ),
                      const SizedBox(width: 4),
                      FilledButton.tonal(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 26),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          textStyle: const TextStyle(fontSize: 11),
                        ),
                        onPressed: () =>
                            context.go('/chat/${character.id}'),
                        child: const Text('Chat'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar() {
    if (character.avatarPath != null && character.avatarPath!.isNotEmpty) {
      return Container(
        color: _avatarColor().withValues(alpha: 0.08),
        child: Image.file(
          File(character.avatarPath!),
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => _buildPlaceholderAvatar(),
        ),
      );
    }
    return _buildPlaceholderAvatar();
  }

  Widget _buildPlaceholderAvatar() {
    return Container(
      color: _avatarColor().withValues(alpha: 0.15),
      child: Center(
        child: Text(
          character.name.isNotEmpty ? character.name[0].toUpperCase() : '?',
          style: TextStyle(
            fontSize: 40,
            color: _avatarColor(),
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Color _avatarColor() {
    if (character.color != null) {
      try {
        final c = character.color!.replaceFirst('#', '');
        return Color(int.parse('FF$c', radix: 16));
      } catch (_) {}
    }
    return AppColors.accent;
  }

  Widget _actionMenu(BuildContext context, WidgetRef ref) {
    return SizedBox(
      width: 28,
      height: 28,
      child: PopupMenuButton<String>(
        padding: EdgeInsets.zero,
        icon: Container(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.5),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.more_vert, size: 16, color: Colors.white),
        ),
        onSelected: (value) {
          switch (value) {
            case 'info':
              context.go('/character/${character.id}');
            case 'edit':
              context.go('/character/${character.id}/edit');
            case 'delete':
              _confirmDelete(context, ref);
          }
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'info', child: Text('View Info')),
          const PopupMenuItem(value: 'edit', child: Text('Edit')),
          const PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      ),
    );
  }

  void _showActions(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('View Info'),
              onTap: () {
                Navigator.pop(ctx);
                context.go('/character/${character.id}');
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Edit'),
              onTap: () {
                Navigator.pop(ctx);
                context.go('/character/${character.id}/edit');
              },
            ),
            ListTile(
              leading: Icon(Icons.delete, color: Theme.of(context).colorScheme.error),
              title: Text('Delete',
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
              onTap: () {
                Navigator.pop(ctx);
                _confirmDelete(context, ref);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Character'),
        content: Text('Delete ${character.name}? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(charactersProvider.notifier).remove(character.id);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
