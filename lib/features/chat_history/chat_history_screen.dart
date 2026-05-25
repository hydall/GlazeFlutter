import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:go_router/go_router.dart';

import '../../core/utils/html_to_markdown.dart';
import '../../shared/shell/nav_height_provider.dart';
import '../../shared/theme/app_colors.dart';

import '../../shared/widgets/glaze_bottom_sheet.dart';
import '../../shared/widgets/glaze_scaffold.dart';
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
        16.0 +
        (_searchQuery.isNotEmpty ? 32.0 : 0.0);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(
            child: sessionsAsync.when(
              loading: () => Center(
                child: CircularProgressIndicator(color: context.cs.primary),
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
            color: context.cs.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'No chats yet',
            style: TextStyle(color: context.cs.onSurfaceVariant),
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
      ..sort((a, b) => b.value.first.lastMessageTime.compareTo(
            a.value.first.lastMessageTime,
          ));

    return ListView.builder(
      padding: EdgeInsets.only(
        top: topPad,
        bottom: ref.watch(navHeightProvider) + 20,
      ),
      itemCount: sortedGroups.length,
      itemBuilder: (_, i) {
        final entry = sortedGroups[i];
        final charId = entry.key;
        final group = [...entry.value]
          ..sort((a, b) => b.lastMessageTime.compareTo(a.lastMessageTime));
        final isExpanded = _expandedCharIds.contains(charId);
        return _ChatHistoryGroupSection(
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
                      color: context.cs.primary,
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
                    style: TextStyle(
                      color: context.cs.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => setState(() => _searchQuery = ''),
                    child: Icon(
                      Icons.close,
                      size: 16,
                      color: context.cs.onSurfaceVariant,
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

class _ChatHistoryGroupSection extends StatefulWidget {
  final List<ChatSessionInfo> sessions;
  final bool isExpanded;
  final VoidCallback onTap;

  const _ChatHistoryGroupSection({
    required this.sessions,
    required this.isExpanded,
    required this.onTap,
  });

  @override
  State<_ChatHistoryGroupSection> createState() =>
      _ChatHistoryGroupSectionState();
}

class _ChatHistoryGroupSectionState extends State<_ChatHistoryGroupSection>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _sizeAnimation;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
      reverseDuration: const Duration(milliseconds: 200),
      value: widget.isExpanded ? 1 : 0,
    );
    _sizeAnimation = CurvedAnimation(
      parent: _controller,
      curve: const Cubic(0.2, 0.8, 0.2, 1),
      reverseCurve: Curves.easeInOut,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -0.04),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Cubic(0.2, 0.8, 0.2, 1),
        reverseCurve: Curves.easeInOut,
      ),
    );
  }

  @override
  void didUpdateWidget(covariant _ChatHistoryGroupSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isExpanded != oldWidget.isExpanded) {
      if (widget.isExpanded) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _GroupHeader(
          sessions: widget.sessions,
          isExpanded: widget.isExpanded,
          onTap: widget.onTap,
        ),
        ClipRect(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: SizeTransition(
              sizeFactor: _sizeAnimation,
              axisAlignment: -1,
              child: SlideTransition(
                position: _slideAnimation,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final session in widget.sessions)
                        _SessionTile(info: session, isGrouped: true),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ChatSearchDelegate extends SearchDelegate<String> {
  final WidgetRef ref;
  _ChatSearchDelegate(this.ref);

  @override
  ThemeData appBarTheme(BuildContext context) => Theme.of(context).copyWith(
    appBarTheme: AppBarTheme(backgroundColor: context.cs.surface),
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
  Widget buildResults(BuildContext context) => _buildList(context);

  @override
  Widget buildSuggestions(BuildContext context) => _buildList(context);

  Widget _buildList(BuildContext context) {
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
      return Center(
        child: Text(
          'No chats found',
          style: TextStyle(color: context.cs.onSurfaceVariant),
        ),
      );
    }

    return ListView.builder(
      itemCount: filtered.length,
      itemBuilder: (ctx, i) {
        final s = filtered[i];
        return ListTile(
          leading: s.avatarPath != null && s.avatarPath!.isNotEmpty
              ? CircleAvatar(backgroundImage: FileImage(File(_thumbOrAvatar(s.avatarPath!))))
              : CircleAvatar(
                  backgroundColor: context.cs.primary,
                  child: Text(
                    s.characterName.isNotEmpty
                        ? s.characterName[0].toUpperCase()
                        : '?',
                    style: const TextStyle(color: Colors.black),
                  ),
                ),
          title: Text(
            s.characterName,
            style: TextStyle(color: context.cs.onSurface),
          ),
          subtitle: Text(
            stripHtml(s.lastMessage).replaceAll('\n', ' '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: context.cs.onSurfaceVariant,
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
            _buildAvatar(context),
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
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 16,
                            height: 20 / 16,
                            color: context.cs.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _buildTime(context),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    info.sessionName?.isNotEmpty == true
                        ? info.sessionName!
                        : 'Session #${info.sessionIndex + 1}',
                    style: TextStyle(
                      fontSize: 12,
                      color: context.cs.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    stripHtml(info.lastMessage).replaceAll('\n', ' '),
                    style: TextStyle(
                      fontSize: 13,
                      height: 16 / 13,
                      color: context.cs.onSurfaceVariant,
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
            color: Colors.white.withValues(alpha: 0.02),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
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
                          : 'Session #${info.sessionIndex + 1}',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: context.cs.onSurface,
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
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.description_outlined,
                          size: 12,
                          color: context.cs.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${info.messageCount} messages${info.lastMessageTime > 0 ? ' · ${_formatTime()}' : ''}',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: context.cs.onSurfaceVariant,
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
                style: TextStyle(
                  fontSize: 12,
                  color: context.cs.onSurfaceVariant,
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

  void _showRenameDialog(BuildContext context, WidgetRef ref) {
    final currentName = info.sessionName?.isNotEmpty == true
        ? info.sessionName!
        : 'Session #${info.sessionIndex + 1}';
    GlazeBottomSheet.show(
      context,
      title: 'Rename Session',
      input: BottomSheetInput(
        placeholder: 'Session name',
        value: currentName,
        confirmLabel: 'Rename',
        onConfirm: (val) {
          Navigator.of(context, rootNavigator: true).pop();
          if (val.trim().isNotEmpty) {
            ref.read(chatHistoryProvider.notifier).renameSession(info.sessionId, val.trim());
          }
        },
      ),
    );
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
            Navigator.of(context, rootNavigator: true).pop();
            ref.read(chatHistoryProvider.notifier).deleteSession(info.sessionId);
          },
        ),
        BottomSheetItem(
          label: 'Cancel',
          centered: true,
          onTap: () => Navigator.of(context, rootNavigator: true).pop(),
        ),
      ],
    );
  }

  void _showSessionActions(BuildContext context, WidgetRef ref) {
    GlazeBottomSheet.show<String>(
      context,
      title: 'Session',
      items: [
        BottomSheetItem(
          icon: Icons.upload_file,
          label: 'Export (JSONL)',
          onTap: () => Navigator.of(context, rootNavigator: true).pop('export'),
        ),
        BottomSheetItem(
          icon: Icons.drive_file_rename_outline,
          label: 'Rename',
          onTap: () => Navigator.of(context, rootNavigator: true).pop('rename'),
        ),
        BottomSheetItem(
          icon: Icons.delete_outline,
          label: 'Delete',
          isDestructive: true,
          onTap: () => Navigator.of(context, rootNavigator: true).pop('delete'),
        ),
      ],
    ).then((result) {
      if (!context.mounted) return;
      switch (result) {
        case 'export':
          ref.read(chatActionsServiceProvider).exportSessionUI(
            context,
            charId: info.characterId,
            sessionId: info.sessionId,
          );
        case 'rename':
          _showRenameDialog(context, ref);
        case 'delete':
          _confirmDelete(context, ref);
      }
    });
  }


  Widget _buildAvatar(BuildContext context) {
    if (info.avatarPath != null && info.avatarPath!.isNotEmpty) {
      return CircleAvatar(
        radius: 24,
        backgroundImage: FileImage(File(_thumbOrAvatar(info.avatarPath!))),
        onBackgroundImageError: (_, __) {},
      );
    }
    return CircleAvatar(
      radius: 24,
      backgroundColor: context.cs.primary,
      child: Text(
        info.characterName.isNotEmpty
            ? info.characterName[0].toUpperCase()
            : '?',
        style: const TextStyle(color: Colors.black, fontSize: 18),
      ),
    );
  }

  Widget _buildTime(BuildContext context) {
    final text = _formatTime();
    if (text.isEmpty) return const SizedBox.shrink();

    return Text(
      text,
      style: TextStyle(fontSize: 12, color: context.cs.onSurfaceVariant),
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
            _buildAvatar(context, latest),
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
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 16,
                            height: 20 / 16,
                            color: context.cs.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _buildTime(context, latest),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${sessions.length} sessions',
                        style: TextStyle(
                          fontSize: 12,
                          color: context.cs.onSurfaceVariant,
                        ),
                      ),
                      AnimatedRotation(
                        turns: isExpanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeInOut,
                        child: Icon(
                          Icons.keyboard_arrow_down,
                          color: context.cs.onSurfaceVariant,
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    stripHtml(latest.lastMessage).replaceAll('\n', ' '),
                    style: TextStyle(
                      fontSize: 13,
                      height: 16 / 13,
                      color: context.cs.onSurfaceVariant,
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

  Widget _buildAvatar(BuildContext context, ChatSessionInfo info) {
    if (info.avatarPath != null && info.avatarPath!.isNotEmpty) {
      return CircleAvatar(
        radius: 24,
        backgroundImage: FileImage(File(_thumbOrAvatar(info.avatarPath!))),
        onBackgroundImageError: (_, __) {},
      );
    }
    return CircleAvatar(
      radius: 24,
      backgroundColor: context.cs.primary,
      child: Text(
        info.characterName.isNotEmpty
            ? info.characterName[0].toUpperCase()
            : '?',
        style: const TextStyle(color: Colors.black, fontSize: 18),
      ),
    );
  }

  Widget _buildTime(BuildContext context, ChatSessionInfo info) {
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
      style: TextStyle(fontSize: 12, color: context.cs.onSurfaceVariant),
    );
  }

  void _showGroupActions(
      BuildContext context, WidgetRef ref, ChatSessionInfo info) {
    GlazeBottomSheet.show<String>(
      context,
      title: info.characterName,
      items: [
        BottomSheetItem(
          icon: Icons.add_comment_outlined,
          label: 'New Session',
          onTap: () => Navigator.of(context, rootNavigator: true).pop('new'),
        ),
        BottomSheetItem(
          icon: Icons.edit_note_rounded,
          label: 'Edit Character',
          onTap: () => Navigator.of(context, rootNavigator: true).pop('edit'),
        ),
      ],
    ).then((result) {
      if (!context.mounted) return;
      if (result == 'new') {
        ref
            .read(chatProvider(info.characterId).notifier)
            .createNewSession();
        context.go('/chat/${info.characterId}');
      } else if (result == 'edit') {
        context.push('/characters/${info.characterId}/edit');
      }
    });
  }
}

String _thumbOrAvatar(String avatarPath) {
  final name = p.basenameWithoutExtension(avatarPath);
  final dir = p.dirname(p.dirname(avatarPath));
  final thumb = p.join(dir, 'thumbnails', '$name.jpg');
  if (File(thumb).existsSync()) return thumb;
  return avatarPath;
}
