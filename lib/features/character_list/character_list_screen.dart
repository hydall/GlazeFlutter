import 'dart:io';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/character.dart';
import '../../core/state/character_provider.dart';
import '../../core/state/db_provider.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/widgets/glaze_scaffold.dart';

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
  bool _showCatalog = false;

  @override
  Widget build(BuildContext context) {
    final characters = ref.watch(charactersProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          // ── Floating header ──────────────────────────────────────────────
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: GlazeAppBar(
                title: 'Characters',
                actions: [
                  _HeaderIconButton(
                    icon: Icons.search_rounded,
                    onTap: () {/* TODO: search */},
                  ),
                ],
              ),
            ),
          ),

          // ── Tabs row: My Characters | Catalog + Add button ───────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Row(
              children: [
                Expanded(child: _TabsRow(
                  showCatalog: _showCatalog,
                  onTabChanged: (v) => setState(() => _showCatalog = v),
                )),
                const SizedBox(width: 12),
                if (!_showCatalog)
                  GlazePillButton(
                    icon: Icons.add_rounded,
                    label: 'Add',
                    onTap: () => _importCharacter(context, ref),
                  ),
              ],
            ),
          ),

          // ── Content ──────────────────────────────────────────────────────
          Expanded(
            child: _showCatalog
                ? const _CatalogPlaceholder()
                : characters.when(
                    loading: () => const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.accent,
                      ),
                    ),
                    error: (e, _) => Center(
                      child: Text('Error: $e',
                          style: const TextStyle(
                              color: AppColors.textSecondary)),
                    ),
                    data: (chars) {
                      if (chars.isEmpty) {
                        return _EmptyState(
                          onImport: () => _importCharacter(context, ref),
                        );
                      }
                      final sorted = _sortChars(chars);
                      return _CharacterGrid(
                        characters: sorted,
                        sortBy: _sortBy,
                        sortDir: _sortDir,
                        onSortDirToggle: () => setState(() {
                          _sortDir = _sortDir == _SortDir.asc
                              ? _SortDir.desc
                              : _SortDir.asc;
                        }),
                        onSortTypeChanged: (t) =>
                            setState(() => _sortBy = t),
                      );
                    },
                  ),
          ),
        ],
      ),
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
            final r = await importer.importFromBytes(file.bytes!, file.name);
            await notifier.add(r.character);
            imported++;
          } else if (file.path != null) {
            final r = await importer.importFromFile(file.path!);
            await notifier.add(r.character);
            imported++;
          }
        } catch (e) {
          lastError = 'Failed to import ${file.name}: $e';
        }
      }

      if (!context.mounted) return;
      if (imported > 0) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text('Imported $imported character${imported > 1 ? 's' : ''}'),
          backgroundColor: AppColors.accent,
        ));
      } else if (lastError != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(lastError)));
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Import failed: $e')));
    }
  }
}

// ─── Tabs row ──────────────────────────────────────────────────────────────

class _TabsRow extends StatelessWidget {
  final bool showCatalog;
  final ValueChanged<bool> onTabChanged;

  const _TabsRow({required this.showCatalog, required this.onTabChanged});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (_, constraints) {
      final w = constraints.maxWidth;
      return Container(
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.surfaceHigh.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.glassBorder),
        ),
        child: Stack(
          children: [
            // Sliding active background
            AnimatedPositioned(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              left: showCatalog ? w / 2 : 0,
              top: 0,
              bottom: 0,
              width: w / 2,
              child: Container(
                margin: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
            // Tab buttons
            Row(
              children: [
                _Tab(
                  label: 'My Characters',
                  icon: Icons.person_rounded,
                  isActive: !showCatalog,
                  onTap: () => onTabChanged(false),
                ),
                _Tab(
                  label: 'Catalog',
                  icon: Icons.public_rounded,
                  isActive: showCatalog,
                  onTap: () => onTabChanged(true),
                ),
              ],
            ),
          ],
        ),
      );
    });
  }
}

class _Tab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;

  const _Tab({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = isActive ? AppColors.accent : AppColors.inactiveTab;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Sort controls + grid ──────────────────────────────────────────────────

class _CharacterGrid extends StatelessWidget {
  final List<Character> characters;
  final _SortType sortBy;
  final _SortDir sortDir;
  final VoidCallback onSortDirToggle;
  final ValueChanged<_SortType> onSortTypeChanged;

  const _CharacterGrid({
    required this.characters,
    required this.sortBy,
    required this.sortDir,
    required this.onSortDirToggle,
    required this.onSortTypeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        // Sort controls row
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // Sort direction circle button
                _SortDirButton(
                  isAsc: sortDir == _SortDir.asc,
                  onTap: onSortDirToggle,
                ),
                const SizedBox(width: 10),
                // Sort type pill
                _SortTypePill(
                  sortBy: sortBy,
                  onChanged: onSortTypeChanged,
                ),
              ],
            ),
          ),
        ),
        // Character count
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
            child: Text(
              '${characters.length} character${characters.length == 1 ? '' : 's'}',
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ),
        // Grid
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          sliver: SliverGrid(
            delegate: SliverChildBuilderDelegate(
              (_, i) => _CharacterCard(character: characters[i]),
              childCount: characters.length,
            ),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 180,
              childAspectRatio: 2 / 3,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Sort dir button ───────────────────────────────────────────────────────

class _SortDirButton extends StatelessWidget {
  final bool isAsc;
  final VoidCallback onTap;

  const _SortDirButton({required this.isAsc, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: AppColors.accent.withValues(alpha: 0.15),
          shape: BoxShape.circle,
          border: Border.all(
              color: AppColors.accent.withValues(alpha: 0.2)),
        ),
        child: AnimatedRotation(
          turns: isAsc ? 0.5 : 0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutBack,
          child: const Icon(
            Icons.arrow_downward_rounded,
            size: 18,
            color: AppColors.accent,
          ),
        ),
      ),
    );
  }
}

// ─── Sort type pill ────────────────────────────────────────────────────────

class _SortTypePill extends StatelessWidget {
  final _SortType sortBy;
  final ValueChanged<_SortType> onChanged;

  const _SortTypePill({required this.sortBy, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showPicker(context),
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: AppColors.accent.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: AppColors.accent.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              sortBy == _SortType.name ? 'Name' : 'Date',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.accent,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.keyboard_arrow_down_rounded,
                size: 18, color: AppColors.accent),
          ],
        ),
      ),
    );
  }

  void _showPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.inactiveTab.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            _PickerItem(
              label: 'Sort by Name',
              isActive: sortBy == _SortType.name,
              onTap: () {
                Navigator.pop(context);
                onChanged(_SortType.name);
              },
            ),
            _PickerItem(
              label: 'Sort by Date',
              isActive: sortBy == _SortType.date,
              onTap: () {
                Navigator.pop(context);
                onChanged(_SortType.date);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _PickerItem extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _PickerItem(
      {required this.label, required this.isActive, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(
        label,
        style: TextStyle(
          color: isActive ? AppColors.accent : AppColors.textPrimary,
          fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      trailing: isActive
          ? const Icon(Icons.check_rounded, color: AppColors.accent, size: 20)
          : null,
      onTap: onTap,
    );
  }
}

// ─── Header icon button ────────────────────────────────────────────────────

class _HeaderIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _HeaderIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 44,
      child: IconButton(
        icon: Icon(icon, size: 22),
        color: AppColors.accent,
        onPressed: onTap,
      ),
    );
  }
}

// ─── Character card — 2:3 full-bleed portrait ─────────────────────────────

class _CharacterCard extends ConsumerWidget {
  final Character character;
  const _CharacterCard({required this.character});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () => context.go('/character/${character.id}'),
      onLongPress: () => _showActions(context, ref),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ── Background image / placeholder ─────────────────────────
            _buildImage(),

            // ── Bottom gradient overlay ─────────────────────────────────
            const Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: 150,
              child: _BottomGradient(),
            ),

            // ── Card info at bottom ─────────────────────────────────────
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _CardInfo(character: character),
            ),

            // ── Token badge top-left ────────────────────────────────────
            Positioned(
              top: 8,
              left: 8,
              child: _TokenBadge(character: character),
            ),

            // ── 3-dot menu top-right ────────────────────────────────────
            Positioned(
              top: 6,
              right: 6,
              child: _CardMenuButton(
                character: character,
                onTap: () => _showActions(context, ref),
              ),
            ),

            // ── Border overlay (fav = red, default = barely-visible white) ──
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.05),
                    width: 2,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImage() {
    if (character.avatarPath != null && character.avatarPath!.isNotEmpty) {
      return Image.file(
        File(character.avatarPath!),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _buildPlaceholder(),
      );
    }
    return _buildPlaceholder();
  }

  Widget _buildPlaceholder() {
    return Container(
      color: _avatarColor().withValues(alpha: 0.2),
      child: Center(
        child: Text(
          character.name.isNotEmpty ? character.name[0].toUpperCase() : '?',
          style: TextStyle(
            fontSize: 48,
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

  void _showActions(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: AppColors.inactiveTab.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.info_outline_rounded,
                  color: AppColors.textPrimary),
              title: const Text('View Info',
                  style: TextStyle(color: AppColors.textPrimary)),
              onTap: () {
                Navigator.pop(ctx);
                context.go('/character/${character.id}');
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_rounded,
                  color: AppColors.textPrimary),
              title: const Text('Edit',
                  style: TextStyle(color: AppColors.textPrimary)),
              onTap: () {
                Navigator.pop(ctx);
                context.go('/character/${character.id}/edit');
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded,
                  color: Color(0xFFFF4444)),
              title: const Text('Delete',
                  style: TextStyle(color: Color(0xFFFF4444))),
              onTap: () {
                Navigator.pop(ctx);
                _confirmDelete(context, ref);
              },
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceHigh,
        title: const Text('Delete Character',
            style: TextStyle(color: AppColors.textPrimary)),
        content: Text('Delete ${character.name}? This cannot be undone.',
            style: const TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(charactersProvider.notifier).remove(character.id);
            },
            child: const Text('Delete',
                style: TextStyle(color: Color(0xFFFF4444))),
          ),
        ],
      ),
    );
  }
}

// ─── Card sub-widgets ──────────────────────────────────────────────────────

class _BottomGradient extends StatelessWidget {
  const _BottomGradient();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Color(0xF2000000), // 0.95 alpha
            Color(0x99000000), // 0.6 alpha
            Colors.transparent,
          ],
          stops: [0.0, 0.5, 1.0],
        ),
      ),
    );
  }
}

class _CardInfo extends StatelessWidget {
  final Character character;

  const _CardInfo({required this.character});

  @override
  Widget build(BuildContext context) {
    final desc = character.scenario?.isNotEmpty == true
        ? character.scenario!
        : character.description;

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            character.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: Colors.white,
              shadows: [Shadow(blurRadius: 4, color: Colors.black54)],
            ),
          ),
          if (desc != null && desc.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              desc,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: Colors.white.withValues(alpha: 0.75),
                height: 1.3,
                shadows: const [
                  Shadow(blurRadius: 4, color: Colors.black87),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TokenBadge extends StatelessWidget {
  final Character character;

  const _TokenBadge({required this.character});

  int _estimateTokens() {
    final text = [
      character.name,
      character.description,
      character.personality,
      character.scenario,
      character.firstMes,
      character.mesExample,
    ].whereType<String>().join('\n');
    return (text.length / 3.35).ceil();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.description_outlined,
                  size: 11, color: Colors.white70),
              const SizedBox(width: 4),
              Text(
                '${_estimateTokens()}',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CardMenuButton extends StatelessWidget {
  final Character character;
  final VoidCallback onTap;

  const _CardMenuButton({required this.character, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.more_vert_rounded,
              size: 18,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Empty state ───────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final VoidCallback onImport;

  const _EmptyState({required this.onImport});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.group_outlined,
              size: 64,
              color: AppColors.textSecondary.withValues(alpha: 0.5)),
          const SizedBox(height: 16),
          const Text(
            'No characters yet',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 20),
          GlazePillButton(
            icon: Icons.add_rounded,
            label: 'Import Character',
            onTap: onImport,
          ),
        ],
      ),
    );
  }
}

// ─── Catalog placeholder ───────────────────────────────────────────────────

class _CatalogPlaceholder extends StatelessWidget {
  const _CatalogPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'Catalog — coming soon',
        style: TextStyle(color: AppColors.textSecondary),
      ),
    );
  }
}
