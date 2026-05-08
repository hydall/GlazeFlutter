import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/llm/tokenizer.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/character.dart';
import '../../../core/state/character_provider.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/widgets/glaze_bottom_sheet.dart';
import '../character_detail_screen.dart';

class CharacterCard extends ConsumerWidget {
  final Character character;
  const CharacterCard({super.key, required this.character});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () => _showDetailSheet(context),
      onLongPress: () => _showActions(context, ref),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildImage(),
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
              left: 8,
              child: _TokenBadge(character: character),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: _CardMenuButton(
                character: character,
                onTap: () => _showActions(context, ref),
              ),
            ),
            if (character.fav)
              Positioned(
                top: 8,
                left: 8,
                child: Padding(
                  padding: const EdgeInsets.only(top: 22),
                  child: Icon(
                    Icons.star,
                    size: 14,
                    color: Colors.amber.withValues(alpha: 0.9),
                  ),
                ),
              ),
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

  void _showDetailSheet(BuildContext context) {
    GlazeBottomSheet.show(
      context,
      locked: true,
      child: CharacterDetailScreen(charId: character.id),
    );
  }

  void _showActions(BuildContext context, WidgetRef ref) {
    GlazeBottomSheet.show(
      context,
      items: [
        BottomSheetItem(
          icon: character.fav ? Icons.star : Icons.star_border,
          label: character.fav ? 'Unfavorite' : 'Favorite',
          onTap: () {
            Navigator.of(context, rootNavigator: true).pop();
            ref
                .read(charactersProvider.notifier)
                .add(character.copyWith(fav: !character.fav));
          },
        ),
        BottomSheetItem(
          icon: Icons.info_outline_rounded,
          label: 'View Info',
          onTap: () {
            Navigator.of(context, rootNavigator: true).pop();
            _showDetailSheet(context);
          },
        ),
        BottomSheetItem(
          icon: Icons.edit_rounded,
          label: 'Edit',
          onTap: () {
            Navigator.of(context, rootNavigator: true).pop();
            context.go('/character/${character.id}/edit');
          },
        ),
        BottomSheetItem(
          icon: Icons.delete_outline_rounded,
          label: 'Delete',
          isDestructive: true,
          onTap: () {
            Navigator.of(context, rootNavigator: true).pop();
            _confirmDelete(context, ref);
          },
        ),
      ],
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceHigh,
        title: const Text(
          'Delete Character',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: Text(
          'Delete ${character.name}? This cannot be undone.',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(charactersProvider.notifier).remove(character.id);
            },
            child: const Text(
              'Delete',
              style: TextStyle(color: Color(0xFFFF4444)),
            ),
          ),
        ],
      ),
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

    return Padding(
      padding: const EdgeInsets.all(12),
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
                shadows: const [Shadow(blurRadius: 4, color: Colors.black87)],
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

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.description_outlined,
            size: 11,
            color: Colors.white70,
          ),
          const SizedBox(width: 4),
          Text(
            '$_cachedTokenCount',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  int get _cachedTokenCount {
    return estimateTokens([
      character.name,
      character.description,
      character.personality,
      character.scenario,
      character.firstMes,
      character.mesExample,
    ].whereType<String>().join('\n'));
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
