import 'dart:io';

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Pinned via dependency_overrides to keep Windows builds green; see docs/BUILD_NOTES.md.
// ignore: depend_on_referenced_packages
import 'package:path_provider/path_provider.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/character.dart';
import '../../../core/services/character_book_converter.dart';
import '../../../core/services/character_exporter.dart';
import '../../../core/services/file_export_service.dart';
import '../../../core/state/character_provider.dart';
import '../../../core/state/lorebook_provider.dart';
import '../../../core/utils/platform_paths.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/widgets/glaze_bottom_sheet.dart';
import '../../../shared/widgets/glaze_toast.dart';
import '../character_detail_screen.dart';
import '../../../core/llm/tokenizer.dart' as tok;

class CharacterCard extends ConsumerStatefulWidget {
  final Character character;
  final Duration entryDelay;
  const CharacterCard({super.key, required this.character, this.entryDelay = Duration.zero});

  @override
  ConsumerState<CharacterCard> createState() => _CharacterCardState();
}

class _CharacterCardState extends ConsumerState<CharacterCard>
    with SingleTickerProviderStateMixin {
  bool _pressed = false;
  bool _hovered = false;
  int _tokenCount = 0;
  late final AnimationController _entryCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<double> _scaleAnim;

  Character get character => widget.character;

  @override
  void initState() {
    super.initState();
    _tokenCount = _getCharTokens(widget.character);
    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    final curve = CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut);
    _fadeAnim = curve;
    _scaleAnim = Tween<double>(begin: 0.9, end: 1.0).animate(curve);
    if (widget.entryDelay > Duration.zero) {
      Future.delayed(widget.entryDelay, () {
        if (mounted) _entryCtrl.forward();
      });
    } else {
      _entryCtrl.forward();
    }
  }

  @override
  void didUpdateWidget(CharacterCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.character != widget.character) {
      _tokenCount = _getCharTokens(widget.character);
    }
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    super.dispose();
  }

  int _getCharTokens(Character char) {
    var text = char.name;
    if (char.description != null) text += '\n${char.description}';
    if (char.personality != null) text += '\n${char.personality}';
    if (char.scenario != null) text += '\n${char.scenario}';
    if (char.firstMes != null) text += '\n${char.firstMes}';
    if (char.mesExample != null) text += '\n${char.mesExample}';
    return tok.estimateTokens(text);
  }

  @override
  Widget build(BuildContext context) {
    final scale = _pressed ? 0.96 : (_hovered ? 1.01 : 1.0);
    final dy = _hovered && !_pressed ? -4.0 : 0.0;
    final isFav = character.fav;
    final shadowAlpha = _hovered
        ? (isFav ? 0.25 : 0.3)
        : 0.1;
    final shadowColor = isFav && _hovered
        ? const Color(0xFFFF6B6B).withValues(alpha: shadowAlpha)
        : Colors.black.withValues(alpha: shadowAlpha);

    return FadeTransition(
      opacity: _fadeAnim,
      child: ScaleTransition(
        scale: _scaleAnim,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: () => _showDetailSheet(context),
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          onLongPress: () => _showActions(context, ref),
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
                    child: _buildImage(),
                  ),
                  const Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    height: 150,
                    child: _BottomGradient(),
                  ),
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: _CardInfo(character: character),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: _CardMenuButton(
                      character: character,
                      onTap: () => _showActions(context, ref),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.white.withValues(
                            alpha: _hovered ? 0.4 : 0.15,
                          ),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.description_rounded,
                            size: 12,
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$_tokenCount',
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
                  Positioned.fill(
                    child: IgnorePointer(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isFav
                                ? const Color(0xFFFF6B6B)
                                : Colors.white.withValues(alpha: 0.15),
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
      ),
    );
  }

  Widget _buildImage() {
    if (character.avatarPath != null && character.avatarPath!.isNotEmpty) {
      final mq = MediaQuery.of(context);
      final cacheW = (mq.size.width * mq.devicePixelRatio / 2).ceil();
      return Image.file(
        File(resolveGlazeFilePath(character.avatarPath!)!),
        fit: BoxFit.cover,
        cacheWidth: cacheW,
        filterQuality: FilterQuality.high,
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
    return context.cs.primary;
  }

  void _showDetailSheet(BuildContext context) async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CharacterDetailScreen(charId: character.id),
    );
    if (result != null && result.isNotEmpty && context.mounted) {
      context.go(result);
    }
  }

  void _showActions(BuildContext context, WidgetRef ref) {
    GlazeBottomSheet.show<void>(
      context,
      items: [
        BottomSheetItem(
          icon: Icons.share_rounded,
          label: 'Export',
          onTap: () {
            Navigator.of(context, rootNavigator: true).pop();
            _showExportOptions(context);
          },
        ),
        BottomSheetItem(
          icon: Icons.edit_rounded,
          label: 'Edit',
          onTap: () {
            Navigator.of(context, rootNavigator: true).pop();
            context.push('/character/${character.id}/edit');
          },
        ),
        BottomSheetItem(
          icon: Icons.favorite,
          label: character.fav ? 'Remove from Favorites' : 'Add to Favorites',
          onTap: () {
            Navigator.of(context, rootNavigator: true).pop();
            ref
                .read(charactersProvider.notifier)
                .add(character.copyWith(fav: !character.fav));
          },
        ),
        BottomSheetItem(
          icon: Icons.delete_rounded,
          label: 'Remove',
          isDestructive: true,
          onTap: () {
            Navigator.of(context, rootNavigator: true).pop();
            _confirmDelete(context, ref);
          },
        ),
      ],
    );
  }

  void _showExportOptions(BuildContext context) {
    GlazeBottomSheet.show<void>(
      context,
      title: 'Export ${character.name}',
      items: [
        BottomSheetItem(
          icon: Icons.image_outlined,
          label: 'Export as PNG',
          onTap: () {
            Navigator.of(context, rootNavigator: true).pop();
            _export(context, 'png');
          },
        ),
        BottomSheetItem(
          icon: Icons.code_rounded,
          label: 'Export as JSON',
          onTap: () {
            Navigator.of(context, rootNavigator: true).pop();
            _export(context, 'json');
          },
        ),
        BottomSheetItem(
          icon: Icons.folder_zip_rounded,
          label: 'Export as ZIP',
          onTap: () {
            Navigator.of(context, rootNavigator: true).pop();
            _export(context, 'zip');
          },
        ),
      ],
    );
  }

  Future<void> _export(BuildContext context, String format) async {
    try {
      final tmpDir = await getTemporaryDirectory();
      final outputDir = tmpDir.path;

      final lorebooks = ref.read(lorebooksProvider).value ?? [];
      final charLorebooks = lorebooks.where((lb) =>
          lb.activationScope == 'character' && lb.activationTargetId == character.id);
      Map<String, dynamic>? characterBookData;
      if (charLorebooks.isNotEmpty) {
        final merged = <String, dynamic>{'name': charLorebooks.first.name, 'entries': <Map<String, dynamic>>[]};
        for (final lb in charLorebooks) {
          final bookJson = lorebookToCharacterBookJson(lb);
          (merged['entries'] as List<dynamic>).addAll(bookJson['entries'] as Iterable<dynamic>);
          if (lb != charLorebooks.first) merged['name'] = '${merged['name']}, ${lb.name}';
        }
        characterBookData = merged;
      }

      final safeName = (character.name.isEmpty ? 'character' : character.name)
          .replaceAll(RegExp(r'[/\\?%*:|"<>\.]'), '-')
          .trim();

      if (format == 'png') {
        Uint8List? avatarBytes;
        if (character.avatarPath != null &&
            File(resolveGlazeFilePath(character.avatarPath!)!).existsSync()) {
          avatarBytes = await File(resolveGlazeFilePath(character.avatarPath!)!).readAsBytes();
        } else {
          avatarBytes = generatePlaceholderAvatar(character.name);
        }

        final result = await exportCharacterAsPng(
          character: character,
          avatarBytes: avatarBytes,
          outputDir: outputDir,
          includeCharacterBook: true,
          characterBookData: characterBookData,
        );
        final bytes = await File(result.filePath).readAsBytes();
        final savedPath = await FileExportService.exportBytes(
          bytes: bytes,
          filename: '$safeName.png',
          subfolder: 'characters',
        );
        if (context.mounted) {
          GlazeToast.show(context, 'Exported PNG to $savedPath');
        }
      } else if (format == 'zip') {
        Uint8List avatarBytes;
        if (character.avatarPath != null &&
            File(resolveGlazeFilePath(character.avatarPath!)!).existsSync()) {
          avatarBytes = await File(resolveGlazeFilePath(character.avatarPath!)!).readAsBytes();
        } else {
          avatarBytes = generatePlaceholderAvatar(character.name);
        }

        final galleryEntries = character.gallery;
        final galleryBytesList = <Uint8List>[];
        for (final entry in galleryEntries) {
          final file = File(entry.imagePath);
          if (await file.exists()) {
            galleryBytesList.add(await file.readAsBytes());
          } else {
            galleryBytesList.add(Uint8List(0));
          }
        }
        final validGallery = <int>[];
        for (int i = 0; i < galleryEntries.length; i++) {
          if (galleryBytesList[i].isNotEmpty) validGallery.add(i);
        }
        final filteredEntries = validGallery.map((i) => galleryEntries[i]).toList();
        final filteredBytes = validGallery.map((i) => galleryBytesList[i]).toList();

        final result = await exportCharacterAsZip(
          character: character,
          avatarBytes: avatarBytes,
          outputDir: outputDir,
          characterBookData: characterBookData,
          gallery: filteredEntries,
          galleryBytes: filteredBytes,
        );
        final bytes = await File(result.filePath).readAsBytes();
        final savedPath = await FileExportService.exportBytes(
          bytes: bytes,
          filename: '$safeName.zip',
          subfolder: 'characters',
        );
        if (context.mounted) {
          GlazeToast.show(context, 'Exported ZIP to $savedPath');
        }
      } else {
        final result = await exportCharacterAsJson(
          character: character,
          outputDir: outputDir,
          includeCharacterBook: true,
          characterBookData: characterBookData,
        );
        final jsonStr = await File(result.filePath).readAsString();
        final savedPath = await FileExportService.export(
          data: jsonStr,
          filename: '$safeName.json',
          subfolder: 'characters',
        );
        if (context.mounted) {
          GlazeToast.show(context, 'Exported JSON to $savedPath');
        }
      }
    } catch (e) {
      if (context.mounted) {
        GlazeToast.error(context, 'Export failed: ', e);
      }
    }
  }


  void _confirmDelete(BuildContext context, WidgetRef ref) {
    GlazeBottomSheet.show<void>(
      context,
      title: 'Delete Character',
      bigInfo: BottomSheetBigInfo(
        icon: Icons.delete_outline,
        description: 'Delete ${character.name}? This cannot be undone.',
      ),
      items: [
        BottomSheetItem(
          label: 'Delete',
          isDestructive: true,
          centered: true,
          onTap: () async {
            Navigator.of(context, rootNavigator: true).pop();
            await ref.read(charactersProvider.notifier).remove(character.id);
          },
        ),
        BottomSheetItem(
          label: 'Cancel',
          centered: true,
          onTap: () => Navigator.pop(context),
        ),
      ],
    );
  }
}

class _BottomGradient extends StatelessWidget {
  const _BottomGradient();

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

class _CardInfo extends StatelessWidget {
  final Character character;

  const _CardInfo({required this.character});

  @override
  Widget build(BuildContext context) {
    final desc = character.scenario?.isNotEmpty == true
        ? character.scenario!
        : character.description;
    final isFav = character.fav;
    const favColor = Color(0xFFFF6B6B);

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isFav) ...[
                const Padding(
                  padding: EdgeInsets.only(top: 3),
                  child: Icon(
                    Icons.favorite,
                    size: 14,
                    color: favColor,
                    shadows: [Shadow(blurRadius: 2, color: Colors.black54)],
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  character.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: isFav ? favColor : Colors.white,
                    shadows: const [
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



class _CardMenuButton extends StatelessWidget {
  final Character character;
  final VoidCallback onTap;

  const _CardMenuButton({required this.character, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
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
    );
  }
}
