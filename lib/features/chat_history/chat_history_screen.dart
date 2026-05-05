import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/chat_message.dart';
import '../../core/state/db_provider.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/widgets/glaze_scaffold.dart';

final chatHistoryProvider =
    AsyncNotifierProvider<ChatHistoryNotifier, List<ChatSessionInfo>>(
        ChatHistoryNotifier.new);

class ChatHistoryNotifier extends AsyncNotifier<List<ChatSessionInfo>> {
  @override
  Future<List<ChatSessionInfo>> build() async {
    final chatRepo = ref.read(chatRepoProvider);
    final charRepo = ref.read(characterRepoProvider);
    final allSessions = await chatRepo.getAllSessions();
    final result = <ChatSessionInfo>[];

    for (final session in allSessions) {
      final char = await charRepo.getById(session.characterId);
      final lastMsg =
          session.messages.isNotEmpty ? session.messages.last : null;
      result.add(ChatSessionInfo(
        sessionId: session.id,
        characterId: session.characterId,
        characterName: char?.name ?? 'Unknown',
        avatarPath: char?.avatarPath,
        lastMessage: lastMsg?.content ?? '',
        lastMessageTime: lastMsg?.timestamp ?? 0,
        messageCount: session.messages.length,
      ));
    }

    result.sort((a, b) => b.lastMessageTime.compareTo(a.lastMessageTime));
    return result;
  }

  Future<void> deleteSession(String sessionId) async {
    await ref.read(chatRepoProvider).delete(sessionId);
    ref.invalidateSelf();
  }

  Future<void> clearChat(String sessionId) async {
    final chatRepo = ref.read(chatRepoProvider);
    final sessions = await chatRepo.getAllSessions();
    final session =
        sessions.firstWhere((s) => s.id == sessionId,
            orElse: () => ChatSession(
                id: sessionId, characterId: '', sessionIndex: 0));
    final cleared = session.copyWith(messages: []);
    await chatRepo.put(cleared);
    ref.invalidateSelf();
  }
}

class ChatSessionInfo {
  final String sessionId;
  final String characterId;
  final String characterName;
  final String? avatarPath;
  final String lastMessage;
  final int lastMessageTime;
  final int messageCount;

  const ChatSessionInfo({
    required this.sessionId,
    required this.characterId,
    required this.characterName,
    this.avatarPath,
    required this.lastMessage,
    required this.lastMessageTime,
    required this.messageCount,
  });
}

class ChatHistoryScreen extends ConsumerWidget {
  const ChatHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(chatHistoryProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: GlazeAppBar(title: 'Chats'),
            ),
          ),
          Expanded(
            child: sessions.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: AppColors.accent),
              ),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (list) {
                if (list.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.chat_bubble_outline,
                            size: 64,
                            color: AppColors.textSecondary.withValues(alpha: 0.5)),
                        const SizedBox(height: 16),
                        const Text('No chats yet',
                            style: TextStyle(color: AppColors.textSecondary)),
                        const SizedBox(height: 20),
                        GlazePillButton(
                          icon: Icons.person_search_rounded,
                          label: 'Browse Characters',
                          onTap: () => context.go('/characters'),
                        ),
                      ],
                    ),
                  );
                }
                return ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (_, i) => _SessionTile(info: list[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionTile extends ConsumerWidget {
  final ChatSessionInfo info;
  const _SessionTile({required this.info});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Dismissible(
      key: ValueKey(info.sessionId),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Colors.red,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (_) => _confirmDelete(context),
      onDismissed: (_) =>
          ref.read(chatHistoryProvider.notifier).deleteSession(info.sessionId),
      child: ListTile(
        leading: _buildAvatar(),
        title: Text(info.characterName),
        subtitle: Text(
          info.lastMessage,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: _buildTrailing(context),
        onTap: () => context.go('/chat/${info.characterId}'),
      ),
    );
  }

  Future<bool> _confirmDelete(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Chat'),
        content: Text(
            'Delete chat with ${info.characterName}? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    return result ?? false;
  }

  Widget _buildAvatar() {
    if (info.avatarPath != null && info.avatarPath!.isNotEmpty) {
      return CircleAvatar(
        backgroundImage: FileImage(File(info.avatarPath!)),
        onBackgroundImageError: (_, __) {},
      );
    }
    return CircleAvatar(
      backgroundColor: AppColors.accent,
      child: Text(
        info.characterName.isNotEmpty
            ? info.characterName[0].toUpperCase()
            : '?',
        style: const TextStyle(color: Colors.black),
      ),
    );
  }

  Widget _buildTrailing(BuildContext context) {
    if (info.lastMessageTime == 0) return const SizedBox.shrink();
    final dt = DateTime.fromMillisecondsSinceEpoch(info.lastMessageTime);
    final now = DateTime.now();
    final diff = now.difference(dt);

    String text;
    if (diff.inMinutes < 1) {
      text = 'now';
    } else if (diff.inHours < 1) {
      text = '${diff.inMinutes}m';
    } else if (diff.inDays < 1) {
      text = '${diff.inHours}h';
    } else if (diff.inDays < 7) {
      text = '${diff.inDays}d';
    } else {
      text = '${dt.day}/${dt.month}';
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(text,
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        const SizedBox(height: 2),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text('${info.messageCount}',
              style: const TextStyle(fontSize: 10, color: AppColors.accent)),
        ),
      ],
    );
  }
}
