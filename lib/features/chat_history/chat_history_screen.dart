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
import '../settings/app_settings_provider.dart';
import 'chat_history_provider.dart';

class ChatHistoryScreen extends ConsumerStatefulWidget {
  const ChatHistoryScreen({super.key});

  @override
  ConsumerState<ChatHistoryScreen> createState() => _ChatHistoryScreenState();
}

class _ChatHistoryScreenState extends ConsumerState<ChatHistoryScreen> {
  String _searchQuery = '';
  final Set<String> _expandedCharIds = {};

  @override
  Widget build(BuildContext context) {
    final sessionsAsync = ref.watch(chatHistoryProvider);
    final settingsAsync = ref.watch(appSettingsProvider);

    final topPad = MediaQuery.of(context).padding.top +
        66.0 +
        (_searchQuery.isNotEmpty ? 32.0 : 0.0);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          Positioned.fill(
            child: sessionsAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: AppColors.accent),
              ),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (list) {
                final settings = settingsAsync.valueOrNull ?? const AppSettings();
                var filtered = list;
                if (_searchQuery.isNotEmpty) {
                  final q = _searchQuery.toLowerCase();
                  filtered = list
                      .where(
                        (s) =>
                            s.characterName.toLowerCase().contains(q) ||
                            (s.sessionName?.toLowerCase().contains(q) ?? false) ||
                            s.lastMessage.toLowerCase().contains(q),
                      )
                      .toList();
                }

                if (filtered.isEmpty) {
                  return _buildEmptyState();
                }

                if (settings.groupDialogs) {
                  return _buildGroupedList(filtered, topPad);
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
          _buildAppBar(topPad),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
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

  Widget _buildGroupedList(List<ChatSessionInfo> sessions, double topPad) {
    // Group by characterId
    final groupsMap = <String, List<ChatSessionInfo>>{};
    for (final s in sessions) {
      groupsMap.putIfAbsent(s.characterId, () => []).add(s);
    }

    final sortedGroups = groupsMap.entries.toList()
      ..sort((a, b) => b.value.first.lastMessageTime
          .compareTo(a.value.first.lastMessageTime));

    final displayItems = <_DisplayItem>[];
    for (final entry in sortedGroups) {
      final charSessions = entry.value;
      displayItems.add(_DisplayItem.header(charSessions));
      if (_expandedCharIds.contains(entry.key)) {
        for (final s in charSessions) {
          displayItems.add(_DisplayItem.session(s));
        }
      }
    }

    return ListView.builder(
      padding: EdgeInsets.only(
        top: topPad,
        bottom: ref.watch(navHeightProvider) + 20,
      ),
      itemCount: displayItems.length,
      itemBuilder: (_, i) {
        final item = displayItems[i];
        if (item.isHeader) {
          final group = item.group!;
          final charId = group.first.characterId;
          final isExpanded = _expandedCharIds.contains(charId);
          return _GroupHeader(
            sessions: group,
            isExpanded: isExpanded,
            onTap: () {
              setState(() {
                if (isExpanded) {
                  _expandedCharIds.remove(charId);
                } else {
                  _expandedCharIds.add(charId);
                }
              });
            },
          );
        } else {
          return _SessionTile(info: item.session!, isGrouped: true);
        }
      },
    );
  }

  Widget _buildAppBar(double topPad) {
    return Positioned(
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
    );
  }
}

class _DisplayItem {
  final List<ChatSessionInfo>? group;
  final ChatSessionInfo? session;
  final bool isHeader;

  _DisplayItem.header(this.group)
      : session = null,
        isHeader = true;
  _DisplayItem.session(this.session)
      : group = null,
        isHeader = false;
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
              (s.sessionName?.toLowerCase().contains(q) ?? false) ||
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
  final bool isGrouped;

  const _SessionTile({
    required this.info,
    this.isGrouped = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (isGrouped) {
      return _buildGroupedTile(context, ref);
    }

    return InkWell(
      onTap: () => context
          .go('/chat/${info.characterId}?session=${info.sessionIndex}'),
      onLongPress: () => _showSessionActions(context, ref),
      child: Container(
        height: 72,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            _buildAvatar(),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          info.characterName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 16,
                            color: AppColors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _buildTime(),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    stripHtml(info.lastMessage).replaceAll('\n', ' '),
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupedTile(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: InkWell(
        onTap: () => context
            .go('/chat/${info.characterId}?session=${info.sessionIndex}'),
        onLongPress: () => _showSessionActions(context, ref),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.02),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      info.sessionName?.isNotEmpty == true
                          ? info.sessionName!
                          : 'Session #${info.sessionIndex}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.description_outlined,
                          size: 12,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${info.messageCount} messages${info.lastMessageTime > 0 ? ' · ${_formatTime()}' : ''}',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                stripHtml(info.lastMessage).replaceAll('\n', ' '),
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime() {
    if (info.lastMessageTime == 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(info.lastMessageTime);
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inMinutes < 1) return 'now';
    if (diff.inHours < 1) return '${diff.inMinutes}m';
    if (diff.inDays < 1) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${dt.day}/${dt.month}';
  }

  void _confirmDelete(BuildContext context, WidgetRef ref) {
    GlazeBottomSheet.show(
      context,
      title: 'Delete Chat',
      bigInfo: BottomSheetBigInfo(
        icon: Icons.delete_outline,
        description: 'Delete chat with ${info.characterName}? This cannot be undone.',
      ),
      items: [
        BottomSheetItem(
          label: 'Delete',
          isDestructive: true,
          centered: true,
          onTap: () {
            Navigator.pop(context);
            ref.read(chatHistoryProvider.notifier).deleteSession(info.sessionId);
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
          onTap: () {
            Navigator.of(context).pop(); // Pops Actions Sheet
            _confirmDelete(context, ref);
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

  Widget _buildTime() {
    final text = _formatTime();
    if (text.isEmpty) return const SizedBox.shrink();

    return Text(
      text,
      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
    );
  }
}

class _GroupHeader extends ConsumerWidget {
  final List<ChatSessionInfo> sessions;
  final bool isExpanded;
  final VoidCallback onTap;

  const _GroupHeader({
    required this.sessions,
    required this.isExpanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final latest = sessions.first;
    return InkWell(
      onTap: onTap,
      onLongPress: () => _showGroupActions(context, ref, latest),
      child: Container(
        height: 72,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            _buildAvatar(latest),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          latest.characterName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 16,
                            color: AppColors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _buildTime(latest),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${sessions.length} sessions',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      Icon(
                        isExpanded
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        color: AppColors.textSecondary,
                        size: 20,
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    stripHtml(latest.lastMessage).replaceAll('\n', ' '),
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar(ChatSessionInfo info) {
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

  Widget _buildTime(ChatSessionInfo info) {
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

  void _showGroupActions(
      BuildContext context, WidgetRef ref, ChatSessionInfo info) {
    GlazeBottomSheet.show(
      context,
      title: info.characterName,
      items: [
        BottomSheetItem(
          icon: Icons.add_comment_outlined,
          label: 'New Session',
          onTap: () {
            Navigator.of(context).pop();
            ref
                .read(chatProvider(info.characterId).notifier)
                .createNewSession();
            context.go('/chat/${info.characterId}');
          },
        ),
        BottomSheetItem(
          icon: Icons.edit_note_rounded,
          label: 'Edit Character',
          onTap: () {
            Navigator.of(context).pop();
            context.push('/characters/${info.characterId}/edit');
          },
        ),
      ],
    );
  }
}
