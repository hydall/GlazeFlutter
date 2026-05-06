import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/chat_message.dart';
import '../../core/db/repositories/chat_repo.dart' show SessionMetadata;
import '../../core/db/repositories/character_repo.dart' show CharacterRepo;
import '../../core/state/db_provider.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/widgets/glaze_scaffold.dart';

final chatHistoryProvider =
    AsyncNotifierProvider<ChatHistoryNotifier, List<ChatSessionInfo>>(
        ChatHistoryNotifier.new);

class ChatHistoryNotifier extends AsyncNotifier<List<ChatSessionInfo>> {
  StreamSubscription? _sub;

  @override
  Future<List<ChatSessionInfo>> build() async {
    _sub?.cancel();
    final chatRepo = ref.read(chatRepoProvider);
    final charRepo = ref.read(characterRepoProvider);

    _sub = chatRepo.watchAllSessionMetadata().listen((allMeta) {
      _updateFromMetadata(allMeta, charRepo);
    });
    ref.onDispose(() => _sub?.cancel());

    final allMeta = await chatRepo.getAllSessionMetadata();
    return _buildFromMetadata(allMeta, charRepo);
  }

  Future<List<ChatSessionInfo>> _buildFromMetadata(
    List<SessionMetadata> allMeta,
    CharacterRepo charRepo,
  ) async {
    final charIds = allMeta.map((m) => m.characterId).toSet();
    final charMap = await charRepo.getByIds(charIds);

    final result = allMeta.map((m) {
      final char = charMap[m.characterId];
      return ChatSessionInfo(
        sessionId: m.sessionId,
        characterId: m.characterId,
        characterName: char?.name ?? 'Unknown',
        avatarPath: char?.avatarPath,
        lastMessage: m.lastMessageContent,
        lastMessageTime: m.lastMessageTimestamp,
        messageCount: m.messageCount,
      );
    }).toList();

    result.sort((a, b) => b.lastMessageTime.compareTo(a.lastMessageTime));
    return result;
  }

  Future<void> _updateFromMetadata(
    List<SessionMetadata> allMeta,
    CharacterRepo charRepo,
  ) async {
    final data = await _buildFromMetadata(allMeta, charRepo);
    state = AsyncData(data);
  }

  Future<void> deleteSession(String sessionId) async {
    await ref.read(chatRepoProvider).delete(sessionId);
  }

  Future<void> clearChat(String sessionId) async {
    final chatRepo = ref.read(chatRepoProvider);
    final sessions = await chatRepo.getAllSessionMetadata();
    final meta = sessions.where((s) => s.sessionId == sessionId).firstOrNull;
    if (meta == null) return;

    final clearedSession = ChatSession(
      id: sessionId,
      characterId: meta.characterId,
      sessionIndex: meta.sessionIndex,
      messages: [],
    );
    await chatRepo.put(clearedSession);
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

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: GlazeAppBar(
                title: 'Chats',
                actions: [
                  SizedBox(
                    width: 44, height: 44,
                    child: IconButton(
                      icon: const Icon(Icons.search_rounded, size: 22),
                      color: AppColors.accent,
                      onPressed: () async {
                        final query = await showSearch<String>(
                          context: context,
                          delegate: _ChatSearchDelegate(ref),
                        );
                        if (query != null) setState(() => _searchQuery = query);
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
                  Text('Filter: "$_searchQuery"', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => setState(() => _searchQuery = ''),
                    child: const Icon(Icons.close, size: 16, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          Expanded(
            child: sessions.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: AppColors.accent),
              ),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (list) {
                var filtered = list;
                if (_searchQuery.isNotEmpty) {
                  final q = _searchQuery.toLowerCase();
                  filtered = list.where((s) =>
                    s.characterName.toLowerCase().contains(q) ||
                    s.lastMessage.toLowerCase().contains(q),
                  ).toList();
                }
                if (filtered.isEmpty) {
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
                  itemCount: filtered.length,
                  itemBuilder: (_, i) => _SessionTile(info: filtered[i]),
                );
              },
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
  ThemeData appBarTheme(BuildContext context) =>
      Theme.of(context).copyWith(appBarTheme: const AppBarTheme(backgroundColor: AppColors.background));

  @override
  List<Widget> buildActions(BuildContext context) => [
    IconButton(icon: const Icon(Icons.clear), onPressed: () => query = ''),
  ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
    icon: const Icon(Icons.arrow_back), onPressed: () => close(context, ''),
  );

  @override
  Widget buildResults(BuildContext context) => _buildList();

  @override
  Widget buildSuggestions(BuildContext context) => _buildList();

  Widget _buildList() {
    final sessions = ref.read(chatHistoryProvider).valueOrNull ?? [];
    final q = query.toLowerCase();
    final filtered = sessions.where((s) =>
      s.characterName.toLowerCase().contains(q) ||
      s.lastMessage.toLowerCase().contains(q),
    ).toList();

    if (filtered.isEmpty) {
      return const Center(child: Text('No chats found', style: TextStyle(color: AppColors.textSecondary)));
    }

    return ListView.builder(
      itemCount: filtered.length,
      itemBuilder: (ctx, i) {
        final s = filtered[i];
        return ListTile(
          leading: s.avatarPath != null && s.avatarPath!.isNotEmpty
              ? CircleAvatar(backgroundImage: FileImage(File(s.avatarPath!)))
              : CircleAvatar(
                  backgroundColor: AppColors.accent,
                  child: Text(s.characterName.isNotEmpty ? s.characterName[0].toUpperCase() : '?', style: const TextStyle(color: Colors.black)),
                ),
          title: Text(s.characterName, style: const TextStyle(color: AppColors.textPrimary)),
          subtitle: Text(s.lastMessage, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
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
