import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/html_to_markdown.dart';
import '../../shared/shell/nav_height_provider.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/widgets/glaze_bottom_sheet.dart';
import '../../shared/widgets/glaze_scaffold.dart';
import '../../shared/widgets/glaze_toast.dart';
import '../chat/chat_actions_service.dart';
import '../chat/chat_provider.dart';
import 'chat_history_provider.dart';

class ChatHistoryScreen extends ConsumerStatefulWidget {
  const ChatHistoryScreen({super.key});

  @override
  ConsumerState<ChatHistoryScreen> createState() => _ChatHistoryScreenState();
}

class _ChatHistoryScreenState extends ConsumerState<ChatHistoryScreen> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final sessions = ref.watch(chatHistoryProvider);

    final topPad =
        MediaQuery.of(context).padding.top +
        66.0 +
        (_searchQuery.isNotEmpty ? 32.0 : 0.0);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          Positioned.fill(
            child: sessions.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: AppColors.accent),
              ),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (list) {
                var filtered = list;
                if (_searchQuery.isNotEmpty) {
                  final q = _searchQuery.toLowerCase();
                  filtered = list
                      .where(
                        (s) =>
                            s.characterName.toLowerCase().contains(q) ||
                            s.lastMessage.toLowerCase().contains(q),
                      )
                      .toList();
                }
                if (filtered.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.chat_bubble_outline,
                          size: 64,
                          color: AppColors.textSecondary.withValues(alpha: 0.5),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'No chats yet',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
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
                  padding: EdgeInsets.only(
                    top: topPad,
                    bottom: ref.watch(navHeightProvider) + 20,
                  ),
                  itemCount: filtered.length,
                  itemBuilder: (_, i) => _SessionTile(info: filtered[i]),
                );
              },
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                    child: GlazeAppBar(
                      title: 'Chats',
                      actions: [
                        SizedBox(
                          width: 44,
                          height: 44,
                          child: IconButton(
                            icon: const Icon(Icons.search_rounded, size: 22),
                            color: AppColors.accent,
                            onPressed: () async {
                              final query = await showSearch<String>(
                                context: context,
                                delegate: _ChatSearchDelegate(ref),
                              );
                              if (query != null)
                                setState(() => _searchQuery = query);
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_searchQuery.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                    child: Row(
                      children: [
                        Text(
                          'Filter: "$_searchQuery"',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () => setState(() => _searchQuery = ''),
                          child: const Icon(
                            Icons.close,
                            size: 16,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatSearchDelegate extends SearchDelegate<String> {
  final WidgetRef ref;
  _ChatSearchDelegate(this.ref);

  @override
  ThemeData appBarTheme(BuildContext context) => Theme.of(context).copyWith(
    appBarTheme: const AppBarTheme(backgroundColor: AppColors.background),
  );

  @override
  List<Widget> buildActions(BuildContext context) => [
    IconButton(icon: const Icon(Icons.clear), onPressed: () => query = ''),
  ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
    icon: const Icon(Icons.arrow_back),
    onPressed: () => close(context, ''),
  );

  @override
  Widget buildResults(BuildContext context) => _buildList();

  @override
  Widget buildSuggestions(BuildContext context) => _buildList();

  Widget _buildList() {
    final sessions = ref.read(chatHistoryProvider).valueOrNull ?? [];
    final q = query.toLowerCase();
    final filtered = sessions
        .where(
          (s) =>
              s.characterName.toLowerCase().contains(q) ||
              s.lastMessage.toLowerCase().contains(q),
        )
        .toList();

    if (filtered.isEmpty) {
      return const Center(
        child: Text(
          'No chats found',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    }

    return ListView.builder(
      itemCount: filtered.length,
      itemBuilder: (ctx, i) {
        final s = filtered[i];
        return ListTile(
          leading: s.avatarPath != null && s.avatarPath!.isNotEmpty
              ? CircleAvatar(backgroundImage: ResizeImage(
                  FileImage(File(s.avatarPath!)),
                  width: 80,
                  height: 80,
                ))
              : CircleAvatar(
                  backgroundColor: AppColors.accent,
                  child: Text(
                    s.characterName.isNotEmpty
                        ? s.characterName[0].toUpperCase()
                        : '?',
                    style: const TextStyle(color: Colors.black),
                  ),
                ),
          title: Text(
            s.characterName,
            style: const TextStyle(color: AppColors.textPrimary),
          ),
          subtitle: Text(
            stripHtml(s.lastMessage).replaceAll('\n', ' '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
          onTap: () => close(ctx, s.characterName),
        );
      },
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
        title: Row(
          children: [
            Flexible(
              child: Text(
                info.characterName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.chat_bubble_rounded,
              size: 14,
              color: AppColors.textSecondary,
            ),
            const SizedBox(width: 4),
            Text(
              '${info.messageCount}',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 2),
            Text(
              info.sessionName?.isNotEmpty == true
                  ? info.sessionName!
                  : 'Session #${info.sessionIndex}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              stripHtml(info.lastMessage).replaceAll('\n', ' '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
          ],
        ),
        trailing: _buildTrailing(context),
        onTap: () => context.go('/chat/${info.characterId}?session=${info.sessionIndex}'),
        onLongPress: () => _showSessionActions(context, ref),
      ),
    );
  }

  Future<bool> _confirmDelete(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Chat'),
        content: Text(
          'Delete chat with ${info.characterName}? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _showSessionActions(BuildContext context, WidgetRef ref) {
    GlazeBottomSheet.show(
      context,
      title: 'Session',
      items: [
        BottomSheetItem(
          icon: Icons.upload_file,
          label: 'Export (JSONL)',
          onTap: () async {
            Navigator.of(context).pop(); // Pops Actions Sheet
            await ChatActionsService(ref).exportSessionUI(
              context,
              charId: info.characterId,
              sessionId: info.sessionId,
            );
          },
        ),
        BottomSheetItem(
          icon: Icons.delete_outline,
          label: 'Delete',
          isDestructive: true,
          onTap: () async {
            Navigator.of(context).pop(); // Pops Actions Sheet
            final confirm = await _confirmDelete(context);
            if (confirm) {
              ref.read(chatHistoryProvider.notifier).deleteSession(info.sessionId);
            }
          },
        ),
      ],
    );
  }


  Widget _buildAvatar() {
    if (info.avatarPath != null && info.avatarPath!.isNotEmpty) {
      return CircleAvatar(
        backgroundImage: ResizeImage(
          FileImage(File(info.avatarPath!)),
          width: 80,
          height: 80,
        ),
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

    return Text(
      text,
      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
    );
  }
}
