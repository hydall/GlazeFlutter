import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/state/character_provider.dart';
import '../../../shared/theme/app_colors.dart';
import '../picks_models.dart';
import '../picks_provider.dart';
import 'picks_detail_launcher.dart';

class PicksGrid extends ConsumerWidget {
  final double topPadding;
  final double bottomPadding;
  final Widget? tabBar;
  final void Function(String title, String? description, bool canGoBack, VoidCallback? onBack)? onFolderChanged;

  const PicksGrid({
    super.key,
    this.topPadding = 0,
    this.bottomPadding = 16,
    this.tabBar,
    this.onFolderChanged,
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
        onFolderChanged: onFolderChanged,
      ),
    );
  }
}

class _PicksFolderView extends StatefulWidget {
  final List<PicksFolder> folders;
  final double topPadding;
  final double bottomPadding;
  final Widget? tabBar;
  final void Function(String title, String? description, bool canGoBack, VoidCallback? onBack)? onFolderChanged;

  const _PicksFolderView({
    required this.folders,
    this.topPadding = 0,
    this.bottomPadding = 16,
    this.tabBar,
    this.onFolderChanged,
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _notifyFolderChanged());
  }

  void _notifyFolderChanged() {
    if (!mounted || widget.onFolderChanged == null) return;
    final folder = _currentFolder;
    if (folder != null) {
      widget.onFolderChanged!(
        folder.name,
        folder.description,
        _path.isNotEmpty,
        () {
          if (mounted) _navigateBack();
        },
      );
    } else {
      widget.onFolderChanged!(
        'Our Picks',
        null,
        false,
        null,
      );
    }
  }

  bool _isBackTransition = false;

  void _navigateInto(String folderId) {
    setState(() {
      _isBackTransition = false;
      _path = [..._path, folderId];
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _notifyFolderChanged());
  }

  void _navigateBack() {
    if (_path.isEmpty) return;
    setState(() {
      _isBackTransition = true;
      _path = _path.sublist(0, _path.length - 1);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _notifyFolderChanged());
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      reverseDuration: const Duration(milliseconds: 280),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        final isIncoming = child.key == ValueKey(_path.join('/'));
        
        Offset beginOffset;
        if (_isBackTransition) {
          beginOffset = isIncoming ? const Offset(-0.15, 0.0) : const Offset(0.2, 0.0);
        } else {
          beginOffset = isIncoming ? const Offset(0.2, 0.0) : const Offset(-0.15, 0.0);
        }

        final slide = Tween<Offset>(
          begin: beginOffset,
          end: Offset.zero,
        ).animate(animation);

        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: slide,
            child: child,
          ),
        );
      },
      child: CustomScrollView(
        key: ValueKey(_path.join('/')),
        slivers: [
          if (widget.topPadding > 0)
            SliverToBoxAdapter(child: SizedBox(height: widget.topPadding)),
          if (widget.tabBar != null)
            SliverToBoxAdapter(child: widget.tabBar!),
          if (_currentFolder?.description != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
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
                  childAspectRatio: 2 / 3.2,
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
      ),
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
  bool _pressed = false;
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
    final scale = _pressed ? 0.96 : (_hovered ? 1.01 : 1.0);
    final dy = _hovered && !_pressed ? -4.0 : 0.0;
    final shadowAlpha = _hovered ? 0.3 : 0.1;
    final shadowColor = Colors.black.withValues(alpha: shadowAlpha);

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      builder: (_, t, child) => Opacity(
        opacity: t,
        child: Transform.scale(
          scale: 0.9 + 0.1 * t,
          child: child,
        ),
      ),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutBack,
            transform: Matrix4.identity()
              ..translateByDouble(0.0, dy, 0.0, 1.0)
              ..scaleByDouble(scale, scale, 1.0, 1.0),
            transformAlignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: shadowColor,
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
                  AnimatedScale(
                    scale: _hovered ? 1.05 : 1.0,
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeOut,
                    child: widget.folder.imageUrl != null
                        ? CachedNetworkImage(
                            imageUrl: widget.folder.imageUrl!,
                            fit: BoxFit.cover,
                            errorWidget: (_, _, _) => _folderGradient(context),
                          )
                        : _buildFolderBackground(context),
                  ),
                  const Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    height: 150,
                    child: _PicksBottomGradient(),
                  ),
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: _FolderCardInfo(folder: widget.folder),
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.05),
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
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
    final shadowAlpha = _hovered ? 0.3 : 0.1;
    final shadowColor = Colors.black.withValues(alpha: shadowAlpha);

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      builder: (_, t, child) => Opacity(
        opacity: t,
        child: Transform.scale(
          scale: 0.9 + 0.1 * t,
          child: child,
        ),
      ),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: _openDetail,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutBack,
            transform: Matrix4.identity()
              ..translateByDouble(0.0, dy, 0.0, 1.0)
              ..scaleByDouble(scale, scale, 1.0, 1.0),
            transformAlignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: shadowColor,
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
                  AnimatedScale(
                    scale: _hovered ? 1.05 : 1.0,
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeOut,
                    child: _buildPlaceholder(),
                  ),
                  const Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    height: 150,
                    child: _PicksBottomGradient(),
                  ),
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: _PicksCharacterCardInfo(char: char),
                  ),
                  if (imported && !needsUpdate)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.9),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check_rounded,
                          size: 14,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  if (imported && needsUpdate)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.9),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.refresh_rounded,
                          size: 14,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.05),
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
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

  void _openDetail() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PicksDetailLauncher(
        character: char,
        imageUrl: _imageUrl,
        relativePath: _relativePath,
      ),
    );
  }
}

class _PicksBottomGradient extends StatelessWidget {
  const _PicksBottomGradient();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Color(0xF2000000), Color(0x99000000), Colors.transparent],
          stops: [0.0, 0.5, 1.0],
        ),
      ),
    );
  }
}

class _FolderCardInfo extends StatelessWidget {
  final PicksFolder folder;

  const _FolderCardInfo({required this.folder});

  @override
  Widget build(BuildContext context) {
    final desc = folder.description;
    final count = folder.characters.length +
        folder.subfolders.fold<int>(0, (sum, sf) => sum + sf.characters.length);

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Icon(
                  folder.subfolders.isNotEmpty
                      ? Icons.folder_special_rounded
                      : Icons.folder_rounded,
                  size: 14,
                  color: Colors.white,
                  shadows: const [Shadow(blurRadius: 2, color: Colors.black54)],
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  folder.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: Colors.white,
                    shadows: [
                      Shadow(blurRadius: 4, color: Colors.black54),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            desc ?? '$count character${count == 1 ? '' : 's'}',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              color: Colors.white.withValues(alpha: 0.75),
              height: 1.3,
              shadows: const [Shadow(blurRadius: 4, color: Colors.black87)],
            ),
          ),
          if (desc != null) ...[
            const SizedBox(height: 2),
            Text(
              '$count character${count == 1 ? '' : 's'}',
              style: TextStyle(
                fontSize: 10,
                color: Colors.white.withValues(alpha: 0.55),
                shadows: const [Shadow(blurRadius: 4, color: Colors.black87)],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PicksCharacterCardInfo extends StatelessWidget {
  final PicksCharacter char;

  const _PicksCharacterCardInfo({required this.char});

  @override
  Widget build(BuildContext context) {
    final desc = char.description;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  char.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: Colors.white,
                    shadows: [
                      Shadow(blurRadius: 4, color: Colors.black54),
                    ],
                  ),
                ),
              ),
            ],
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
                shadows: const [Shadow(blurRadius: 4, color: Colors.black87)],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
