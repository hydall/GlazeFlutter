import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

import '../../../core/models/character.dart';
import '../../../core/services/character_export_helper.dart';
import '../../../core/state/character_folder_provider.dart';
import '../../../core/state/character_provider.dart';
import '../../../core/utils/platform_paths.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/widgets/card_tag_chips.dart';
import '../../../shared/widgets/glaze_bottom_sheet.dart';
import '../../../shared/widgets/glaze_error_dialog.dart';
import '../../../shared/widgets/glaze_toast.dart';
import '../character_detail_screen.dart';
import '../../../core/llm/character_tokens.dart';
import '../character_selection_provider.dart';
import 'add_to_folder_sheet.dart';

class CharacterCard extends ConsumerStatefulWidget {
  final Character character;
  final Duration entryDelay;

  /// When the card is shown inside a folder, this is that folder's id — it
  /// enables the "Remove from folder" action.
  final String? folderId;

  const CharacterCard({
    super.key,
    required this.character,
    this.entryDelay = Duration.zero,
    this.folderId,
  });

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
  String get _displayName {
    final displayName = character.displayName?.trim();
    return (displayName != null && displayName.isNotEmpty)
        ? displayName
        : character.name;
  }

  /// Prefer the cached count persisted on import/save; fall back to a live
  /// (memoized) estimate only for rows that predate the cached column.
  int _resolveTokens(Character c) =>
      c.tokenCount > 0 ? c.tokenCount : estimateCharacterTokens(c);

  @override
  void initState() {
    super.initState();
    _tokenCount = _resolveTokens(widget.character);
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
      _tokenCount = _resolveTokens(widget.character);
    }
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectionActive =
        ref.watch(characterSelectionProvider.select((s) => s.active));
    final selected = ref.watch(
      characterSelectionProvider.select((s) => s.contains(character.id)),
    );
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
          onTap: () {
            if (selectionActive) {
              ref.read(characterSelectionProvider.notifier).toggle(character.id);
            } else {
              _showDetailSheet(context);
            }
          },
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          onLongPress: () {
            final notifier = ref.read(characterSelectionProvider.notifier);
            if (selectionActive) {
              notifier.toggle(character.id);
            } else {
              notifier.start(character.id);
            }
          },
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
                    child: _CardInfo(
                      character: character,
                      tokenCount: _tokenCount,
                    ),
                  ),
                  if (character.hidden)
                    const Positioned(top: 8, left: 8, child: _HiddenBadge()),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: selectionActive
                        ? _SelectionCheck(selected: selected)
                        : _CardMenuButton(
                            character: character,
                            onTap: () => _showActions(context, ref),
                          ),
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: selected
                                ? context.cs.primary
                                : isFav
                                    ? const Color(0xFFFF6B6B)
                                    : Colors.white.withValues(alpha: 0.15),
                            width: selected ? 3 : 2,
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
    final avatarPath = character.avatarPath;
    if (avatarPath == null || avatarPath.isEmpty) return _buildPlaceholder();
    // Prefer the pre-generated 512px thumbnail so first-scroll doesn't have to
    // decode the full-resolution PNG per card (jank + delayed pop-in). Falls
    // back to the source avatar when a thumbnail hasn't been generated yet.
    final resolved = resolveGlazeThumbnailPath(avatarPath);
    if (resolved == null) return _buildPlaceholder();
    final usingThumb = p.extension(resolved).toLowerCase() == '.jpg';
    final mq = MediaQuery.of(context);
    return Image.file(
      File(resolved),
      fit: BoxFit.cover,
      // Thumbnails are already small; only downscale the full-res fallback to
      // roughly the card's on-screen width.
      cacheWidth: usingThumb
          ? null
          : (mq.size.width * mq.devicePixelRatio / 2).ceil(),
      filterQuality: FilterQuality.high,
      errorBuilder: (_, _, _) => _buildPlaceholder(),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: _avatarColor().withValues(alpha: 0.2),
      child: Center(
        child: Text(
          _displayName.isNotEmpty ? _displayName[0].toUpperCase() : '?',
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
          label: 'action_export'.tr(),
          onTap: () {
            Navigator.of(context, rootNavigator: true).pop();
            _showExportOptions(context);
          },
        ),
        BottomSheetItem(
          icon: Icons.edit_rounded,
          label: 'action_edit'.tr(),
          onTap: () {
            Navigator.of(context, rootNavigator: true).pop();
            context.push('/character/${character.id}/edit');
          },
        ),
        BottomSheetItem(
          icon: Icons.favorite,
          label: character.fav ? 'action_remove_fav'.tr() : 'action_add_fav'.tr(),
          onTap: () {
            Navigator.of(context, rootNavigator: true).pop();
            ref
                .read(charactersProvider.notifier)
                .add(character.copyWith(fav: !character.fav));
          },
        ),
        BottomSheetItem(
          icon: character.hidden
              ? Icons.visibility_outlined
              : Icons.visibility_off_outlined,
          label: character.hidden ? 'action_unhide'.tr() : 'action_hide'.tr(),
          onTap: () {
            Navigator.of(context, rootNavigator: true).pop();
            ref
                .read(charactersProvider.notifier)
                .setHidden(character.id, !character.hidden);
            GlazeToast.show(
              context,
              character.hidden
                  ? 'char_unhidden_toast'.tr()
                  : 'char_hidden_toast'.tr(),
            );
          },
        ),
        BottomSheetItem(
          icon: Icons.create_new_folder_outlined,
          label: 'action_add_to_folder'.tr(),
          onTap: () {
            Navigator.of(context, rootNavigator: true).pop();
            showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              useRootNavigator: true,
              useSafeArea: true,
              backgroundColor: Colors.transparent,
              builder: (_) => AddToFolderSheet(characterId: character.id),
            );
          },
        ),
        if (widget.folderId != null)
          BottomSheetItem(
            icon: Icons.folder_off_outlined,
            label: 'action_remove_from_folder'.tr(),
            onTap: () {
              Navigator.of(context, rootNavigator: true).pop();
              ref
                  .read(characterFolderRepoProvider)
                  .removeMember(widget.folderId!, character.id);
            },
          ),
        BottomSheetItem(
          icon: Icons.delete_rounded,
          label: 'action_delete'.tr(),
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
      title: 'Export $_displayName',
      items: [
        BottomSheetItem(
          icon: Icons.image_outlined,
          label: 'label_export_png'.tr(),
          onTap: () {
            Navigator.of(context, rootNavigator: true).pop();
            _export(context, 'png');
          },
        ),
        BottomSheetItem(
          icon: Icons.code_rounded,
          label: 'label_export_json'.tr(),
          onTap: () {
            Navigator.of(context, rootNavigator: true).pop();
            _export(context, 'json');
          },
        ),
        BottomSheetItem(
          icon: Icons.folder_zip_rounded,
          label: 'label_export_zip'.tr(),
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
      final savedPath = await exportCharacterToFile(
        ref: ref,
        character: character,
        format: format,
      );
      if (context.mounted) {
        GlazeToast.show(
          context,
          'Exported ${format.toUpperCase()} to $savedPath',
        );
      }
    } catch (e) {
      if (context.mounted) {
        GlazeErrorDialog.show(context, e, prefix: 'Export failed: ');
      }
    }
  }


  void _confirmDelete(BuildContext context, WidgetRef ref) {
    GlazeBottomSheet.show<void>(
      context,
      title: 'action_delete_char'.tr(),
      bigInfo: BottomSheetBigInfo(
        icon: Icons.delete_outline,
        description: 'Delete $_displayName? This cannot be undone.',
      ),
      items: [
        BottomSheetItem(
          label: 'btn_delete'.tr(),
          isDestructive: true,
          centered: true,
          onTap: () async {
            Navigator.of(context, rootNavigator: true).pop();
            await ref.read(charactersProvider.notifier).remove(character.id);
          },
        ),
        BottomSheetItem(
          label: 'btn_cancel'.tr(),
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
  final int tokenCount;

  const _CardInfo({required this.character, required this.tokenCount});

  String get _displayName {
    final displayName = character.displayName?.trim();
    return (displayName != null && displayName.isNotEmpty)
        ? displayName
        : character.name;
  }

  @override
  Widget build(BuildContext context) {
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
                  _displayName,
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
          if (tokenCount > 0) ...[
            const SizedBox(height: 2),
            Text(
              '${_formatTokens(tokenCount)} tokens',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.6),
                shadows: const [Shadow(blurRadius: 4, color: Colors.black87)],
              ),
            ),
          ],
          if (character.tags.isNotEmpty) ...[
            const SizedBox(height: 8),
            CardTagChips(tags: character.tags, max: 4),
          ],
        ],
      ),
    );
  }

  String _formatTokens(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}kk';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return '$n';
  }
}



class _SelectionCheck extends StatelessWidget {
  final bool selected;

  const _SelectionCheck({required this.selected});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: selected
            ? context.cs.primary
            : Colors.black.withValues(alpha: 0.45),
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withValues(alpha: selected ? 0.9 : 0.6),
          width: 2,
        ),
      ),
      child: selected
          ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
          : null,
    );
  }
}

class _HiddenBadge extends StatelessWidget {
  const _HiddenBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.15),
          width: 1,
        ),
      ),
      child: const Icon(
        Icons.visibility_off_rounded,
        size: 18,
        color: Colors.white,
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
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.15),
            width: 1,
          ),
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
