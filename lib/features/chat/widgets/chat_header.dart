import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/character.dart';

import '../../../core/state/character_provider.dart' show avatarVersionProvider;
import '../../../shared/theme/app_colors.dart';

class ChatHeader extends ConsumerWidget {
  final Character character;
  final String sessionName;
  final int currentSessionIndex;

  const ChatHeader({
    super.key,
    required this.character,
    required this.sessionName,
    this.currentSessionIndex = 0,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(avatarVersionProvider);
    Color avatarColor = context.cs.primary;
    if (character.color != null && character.color!.isNotEmpty) {
      try {
        final String c = character.color!.replaceFirst('#', '');
        avatarColor = Color(int.parse('FF$c', radix: 16));
      } catch (_) {}
    }

    final String initial = character.name.isNotEmpty
        ? character.name[0].toUpperCase()
        : '?';

    Widget avatar;
    if (character.avatarPath != null && character.avatarPath!.isNotEmpty) {
      avatar = CircleAvatar(
        radius: 17,
        backgroundImage: FileImage(File(character.avatarPath!)),
        onBackgroundImageError: (_, _) {},
        backgroundColor: avatarColor.withValues(alpha: 0.2),
        child: const SizedBox.shrink(),
      );
    } else {
      avatar = Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: avatarColor.withValues(alpha: 0.2),
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Text(
            initial,
            style: TextStyle(
              fontSize: 16,
              color: avatarColor,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        avatar,
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                character.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: context.cs.onSurface,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                sessionName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: context.cs.onSurfaceVariant,
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

}
