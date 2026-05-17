import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/character.dart';
import '../../../core/services/character_book_converter.dart';
import '../../../core/services/character_importer.dart';
import '../../../core/state/character_provider.dart';
import '../../../core/state/db_provider.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/widgets/glaze_toast.dart';
import '../picks_models.dart';
import '../picks_provider.dart';

class PicksGrid extends ConsumerWidget {
  final double topPadding;
  final double bottomPadding;
  final Widget? tabBar;

  const PicksGrid({
    super.key,
    this.topPadding = 0,
    this.bottomPadding = 16,
    this.tabBar,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final indexAsync = ref.watch(picksIndexProvider);

    return indexAsync.when(
      loading: () => CustomScrollView(
        slivers: [
          if (topPadding > 0)
            SliverToBoxAdapter(child: SizedBox(height: topPadding)),
          if (tabBar != null) SliverToBoxAdapter(child: tabBar!),
          const SliverFillRemaining(
            child: Center(child: CircularProgressIndicator()),
          ),
        ],
      ),
      error: (e, _) => CustomScrollView(
        slivers: [
          if (topPadding > 0)
            SliverToBoxAdapter(child: SizedBox(height: topPadding)),
          if (tabBar != null) SliverToBoxAdapter(child: tabBar!),
          SliverFillRemaining(
            child: Center(
              child: Text(
                'Failed to load picks',
                style: TextStyle(color: context.cs.onSurfaceVariant),
              ),
            ),
          ),
        ],
      ),
      data: (index) => _PicksFolderView(
        folders: index.folders,
        topPadding: topPadding,
        bottomPadding: bottomPadding,
        tabBar: tabBar,
      ),
    );
  }
}

class _PicksFolderView extends StatefulWidget {
  final List<PicksFolder> folders;
  final double topPadding;
  final double bottomPadding;
  final Widget? tabBar;

  const _PicksFolderView({
    required this.folders,
    this.topPadding = 0,
    this.bottomPadding = 16,
    this.tabBar,
  });

  @override
  State<_PicksFolderView> createState() => _PicksFolderViewState();
}

class _PicksFolderViewState extends State<_PicksFolderView> {
  List<String> _path = [];

  List<PicksFolder> get _currentFolders {
    List<PicksFolder> current = widget.folders;
    for (final segment in _path) {
      final match = current.firstWhere((f) => f.id == segment);
      if (match.subfolders.isNotEmpty) {
        current = match.subfolders;
      } else {
        return [];
      }
    }
    return current;
  }

  PicksFolder? get _currentFolder {
    if (_path.isEmpty) return null;
    PicksFolder? folder;
    List<PicksFolder> current = widget.folders;
    for (final segment in _path) {
      folder = current.firstWhere((f) => f.id == segment);
      current = folder.subfolders;
    }
    return folder;
  }

  bool get _hasSubfolders => _currentFolders.isNotEmpty;

  List<PicksCharacter> get _currentCharacters {
    final folder = _currentFolder;
    if (folder == null) return [];
    return folder.characters;
  }

  void _navigateInto(String folderId) {
    setState(() => _path = [..._path, folderId]);
  }

  void _navigateBack() {
    if (_path.isEmpty) return;
    setState(() => _path = _path.sublist(0, _path.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        if (widget.topPadding > 0)
          SliverToBoxAdapter(child: SizedBox(height: widget.topPadding)),
        if (widget.tabBar != null)
          SliverToBoxAdapter(child: widget.tabBar!),
        if (_path.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: _navigateBack,
                    child: Icon(
                      Icons.arrow_back_rounded,
                      color: context.cs.primary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _currentFolder?.name ?? '',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: context.cs.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (_currentFolder?.description != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Text(
                _currentFolder!.description!,
                style: TextStyle(
                  fontSize: 13,
                  color: context.cs.onSurfaceVariant,
                ),
              ),
            ),
          ),
        if (_hasSubfolders)
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              16,
              _path.isEmpty ? 12 : 8,
              16,
              0,
            ),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.6,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final folder = _currentFolders[index];
                  return _FolderCard(
                    folder: folder,
                    path: _path,
                    onTap: () => _navigateInto(folder.id),
                  );
                },
                childCount: _currentFolders.length,
              ),
            ),
          ),
        if (_currentCharacters.isNotEmpty)
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              16,
              _hasSubfolders ? 8 : 12,
              16,
              widget.bottomPadding,
            ),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 2 / 3.2,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final char = _currentCharacters[index];
                  return _PicksCharacterCard(
                    character: char,
                    path: _path,
                  );
                },
                childCount: _currentCharacters.length,
              ),
            ),
          ),
        if (_currentCharacters.isEmpty &&
            !_hasSubfolders &&
            _path.isNotEmpty)
          SliverFillRemaining(
            child: Center(
              child: Text(
                'Coming soon',
                style: TextStyle(color: context.cs.onSurfaceVariant),
              ),
            ),
          ),
      ],
    );
  }
}

class _FolderCard extends StatefulWidget {
  final PicksFolder folder;
  final List<String> path;
  final VoidCallback onTap;

  const _FolderCard({required this.folder, required this.path, required this.onTap});

  @override
  State<_FolderCard> createState() => _FolderCardState();
}

class _FolderCardState extends State<_FolderCard> {
  bool _hovered = false;
  late final List<PicksCharacter> _shuffledChars;

  @override
  void initState() {
    super.initState();
    final allChars = widget.folder.characters.isNotEmpty
        ? widget.folder.characters
        : widget.folder.subfolders.expand((sf) => sf.characters).toList();
    _shuffledChars = List.of(allChars)..shuffle(Random());
  }

  @override
  Widget build(BuildContext context) {
    final folder = widget.folder;
    final dy = _hovered ? -2.0 : 0.0;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          transform: Matrix4.identity()..translateByDouble(0.0, dy, 0.0, 1.0),
          transformAlignment: Alignment.center,
          decoration: BoxDecoration(
            color: context.cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: context.cs.primary.withValues(alpha: 0.15),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: _hovered ? 0.2 : 0.05),
                blurRadius: _hovered ? 16 : 4,
                offset: Offset(0, _hovered ? 8 : 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              children: [
                Positioned.fill(
                  child: folder.imageUrl != null
                      ? CachedNetworkImage(
                          imageUrl: folder.imageUrl!,
                          fit: BoxFit.cover,
                          errorWidget: (_, _, _) =>
                              _folderGradient(context),
                        )
                      : _buildFolderBackground(context),
                ),
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.75),
                          Colors.black.withValues(alpha: 0.2),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.5, 1.0],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Icon(
                        folder.subfolders.isNotEmpty
                            ? Icons.folder_special_rounded
                            : Icons.folder_rounded,
                        color: Colors.white.withValues(alpha: 0.9),
                        size: 28,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        folder.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      if (folder.description != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          folder.description!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.75),
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Builder(builder: (context) {
                        final count = folder.characters.length +
                            folder.subfolders.fold<int>(
                                0, (sum, sf) => sum + sf.characters.length);
                        return Text(
                          '$count character${count == 1 ? '' : 's'}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.white.withValues(alpha: 0.6),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFolderBackground(BuildContext context) {
    if (_shuffledChars.isEmpty) {
      return _folderGradient(context);
    }

    final previews = _shuffledChars.take(3).toList();
    if (previews.length == 1) {
      return CachedNetworkImage(
        imageUrl: _charImageUrl(previews[0]),
        fit: BoxFit.cover,
        placeholder: (_, _) => _folderGradient(context),
        errorWidget: (_, _, _) => _folderGradient(context),
      );
    }

    return Row(
      children: previews.asMap().entries.map((entry) {
        final i = entry.key;
        final c = entry.value;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(left: i > 0 ? 2 : 0),
            child: CachedNetworkImage(
              imageUrl: _charImageUrl(c),
              fit: BoxFit.cover,
              placeholder: (_, _) => _folderGradient(context),
              errorWidget: (_, _, _) => _folderGradient(context),
            ),
          ),
        );
      }).toList(),
    );
  }

  String _charImageUrl(PicksCharacter c) {
    final parts = <String>[...widget.path, widget.folder.id];
    final base = '$kPicksBaseUrl/${parts.join('/')}';
    return '$base/${Uri.encodeComponent(c.fileName ?? '${c.id}.png')}';
  }
}

Widget _folderGradient(BuildContext context) {
  return Container(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          context.cs.primary.withValues(alpha: 0.08),
          context.cs.surfaceContainerHighest,
        ],
      ),
    ),
  );
}

class _PicksCharacterCard extends ConsumerStatefulWidget {
  final PicksCharacter character;
  final List<String> path;

  const _PicksCharacterCard({
    required this.character,
    required this.path,
  });

  @override
  ConsumerState<_PicksCharacterCard> createState() =>
      _PicksCharacterCardState();
}

class _PicksCharacterCardState extends ConsumerState<_PicksCharacterCard> {
  bool _hovered = false;
  bool _pressed = false;
  bool _importing = false;

  PicksCharacter get char => widget.character;

  String get _relativePath {
    final base = widget.path.join('/');
    return '$base/${char.fileName ?? '${char.id}.png'}';
  }

  String get _imageUrl {
    final base = widget.path.join('/');
    final name = char.fileName ?? '${char.id}.png';
    final segs = name.split('/');
    final encoded = segs.map(Uri.encodeComponent).join('/');
    return '$kPicksBaseUrl/$base/$encoded';
  }

  bool get _isImported {
    final chars = ref.read(charactersProvider).valueOrNull ?? [];
    return chars.any((c) => c.picksHash == char.hash && c.name == char.name);
  }

  bool get _needsUpdate {
    if (char.hash == null) return false;
    final chars = ref.read(charactersProvider).valueOrNull ?? [];
    final existing = chars.where((c) => c.name == char.name && c.picksHash != null);
    return existing.any((c) => c.picksHash != char.hash);
  }

  @override
  Widget build(BuildContext context) {
    final scale = _pressed ? 0.96 : (_hovered ? 1.01 : 1.0);
    final dy = _hovered && !_pressed ? -4.0 : 0.0;
    final imported = _isImported;
    final needsUpdate = _needsUpdate;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: _importing ? null : _importCharacter,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          transform: Matrix4.identity()
            ..translateByDouble(0.0, dy, 0.0, 1.0)
            ..scaleByDouble(scale, scale, 1.0, 1.0),
          transformAlignment: Alignment.center,
          decoration: BoxDecoration(
            color: context.cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: needsUpdate
                  ? context.cs.primary.withValues(alpha: 0.5)
                  : Colors.white.withValues(alpha: 0.05),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: _hovered ? 0.3 : 0.1),
                blurRadius: _hovered ? 24 : 6,
                offset: Offset(0, _hovered ? 12 : 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              fit: StackFit.expand,
              children: [
                _buildPlaceholder(),
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.7),
                      ],
                      stops: const [0.5, 1.0],
                    ),
                  ),
                ),
                if (_importing)
                  Container(
                    color: Colors.black.withValues(alpha: 0.4),
                    child: Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: context.cs.primary,
                        ),
                      ),
                    ),
                  ),
                if (imported && !_importing)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: needsUpdate
                            ? Colors.orange.withValues(alpha: 0.9)
                            : Colors.green.withValues(alpha: 0.9),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        needsUpdate ? Icons.refresh_rounded : Icons.check_rounded,
                        size: 14,
                        color: Colors.white,
                      ),
                    ),
                  ),
                Positioned(
                  left: 10,
                  right: 10,
                  bottom: 10,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        char.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      if (char.description != null)
                        Text(
                          char.description!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.white.withValues(alpha: 0.7),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return CachedNetworkImage(
      imageUrl: _imageUrl,
      fit: BoxFit.cover,
      placeholder: (_, _) => _buildLetterPlaceholder(),
      errorWidget: (_, _, _) => _buildLetterPlaceholder(),
    );
  }

  Widget _buildLetterPlaceholder() {
    return Container(
      color: context.cs.surfaceContainerHighest,
      child: Center(
        child: Text(
          char.name[0].toUpperCase(),
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w700,
            color: context.cs.primary.withValues(alpha: 0.3),
          ),
        ),
      ),
    );
  }

  Future<void> _importCharacter() async {
    setState(() => _importing = true);
    try {
      final pngBytes = await fetchPicksCharacterPng(_relativePath);
      final bytes = Uint8List.fromList(pngBytes);
      final importer = await ref.read(characterImporterProvider.future);
      final result = await importer.importFromBytes(bytes, '${char.id}.png');

      final existingChars = ref.read(charactersProvider).valueOrNull ?? [];
      final existing = existingChars.where(
        (c) => c.picksHash != null && c.name == char.name,
      );

      Character characterWithHash;
      if (existing.isNotEmpty) {
        final old = existing.first;
        characterWithHash = result.character.copyWith(
          id: old.id,
          picksHash: char.hash,
        );
      } else {
        characterWithHash = result.character.copyWith(picksHash: char.hash);
      }

      await ref.read(charactersProvider.notifier).add(characterWithHash);

      if (result.characterBookData != null) {
        final lorebookRepo = ref.read(lorebookRepoProvider);
        final converted = convertCharacterBook(
          result.characterBookData!,
          characterWithHash.id,
        );
        await lorebookRepo.put(converted);
      }

      if (mounted) {
        final wasUpdate = existing.isNotEmpty;
        GlazeToast.show(context, '${wasUpdate ? 'Updated' : 'Imported'} ${char.name}');
      }
    } catch (e) {
      if (mounted) {
        GlazeToast.error(context, 'Import failed: ', e);
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }
}
