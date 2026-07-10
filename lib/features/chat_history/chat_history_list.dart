import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/theme/app_colors.dart';
import '../../shared/utils/avatar_image.dart';
import '../../shared/widgets/glass_surface.dart';
import '../../shared/widgets/glaze_bottom_sheet.dart';
import '../../core/state/character_provider.dart' show avatarVersionProvider;
import '../chat/chat_actions_service.dart';
import '../chat/chat_provider.dart';
import '../settings/app_settings_provider.dart';
import 'chat_history_provider.dart';
import 'widgets/message_preview_text.dart';

class ChatHistoryList extends ConsumerStatefulWidget {
  final bool collapsed;
  final String searchQuery;

  /// Top padding applied inside the scroll view so content can scroll *behind*
  /// a translucent shell header instead of being clipped by it.
  final double topPadding;

  const ChatHistoryList({
    super.key,
    this.collapsed = false,
    this.searchQuery = '',
    this.topPadding = 0,
  });

  @override
  ConsumerState<ChatHistoryList> createState() => _ChatHistoryListState();
}

class _ChatHistoryListState extends ConsumerState<ChatHistoryList> {
  final Set<String> _expandedCharIds = {};

  /// Avatar paths already warmed so we don't re-precache on every rebuild.
  final Set<String> _precachedAvatars = {};

  /// Decode + cache each distinct avatar ahead of scrolling so rows don't
  /// pop in while the image decodes on first appearance.
  void _precacheAvatars(List<ChatSessionInfo> sessions) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final s in sessions) {
        final path = s.avatarPath;
        if (path == null || path.isEmpty) continue;
        if (!_precachedAvatars.add(path)) continue;
        precacheGlazeAvatar(context, path);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final sessionsAsync = ref.watch(chatHistoryProvider);
    final settingsAsync = ref.watch(appSettingsProvider);

    return sessionsAsync.when(
      loading: () => Center(
        child: CircularProgressIndicator(color: context.cs.primary),
      ),
      error: (e, _) => Center(child: Text('${'title_error'.tr()}: $e')),
      data: (list) {
        _precacheAvatars(list);
        final settings = settingsAsync.value ?? const AppSettings();
        var filtered = list;
        if (widget.searchQuery.isNotEmpty) {
          final q = widget.searchQuery.toLowerCase();
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
          return _buildGroupedList(filtered);
        }

        return ListView.builder(
          padding: EdgeInsets.only(top: widget.topPadding, bottom: 20),
          itemCount: filtered.length + 1,
          itemBuilder: (_, i) {
            if (i == 0) return _buildCountHeader(filtered.length);
            return _SessionTile(
              info: filtered[i - 1],
              collapsed: widget.collapsed,
            );
          },
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: EdgeInsets.only(top: widget.topPadding),
      child: Center(
      child: widget.collapsed
          ? Icon(
              Icons.chat_bubble_outline,
              size: 24,
              color: context.cs.onSurfaceVariant.withValues(alpha: 0.5),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.chat_bubble_outline,
                  size: 48,
                  color: context.cs.onSurfaceVariant.withValues(alpha: 0.5),
                ),
                const SizedBox(height: 12),
                Text(
                  'no_dialogs'.tr(),
                  style: TextStyle(
                    fontSize: 12,
                    color: context.cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
      ),
    );
  }

  Widget _buildGroupedList(List<ChatSessionInfo> sessions) {
    final groupsMap = <String, List<ChatSessionInfo>>{};
    for (final s in sessions) {
      groupsMap.putIfAbsent(s.characterId, () => []).add(s);
    }

    final sortedGroups = groupsMap.entries.toList()
      ..sort(
        (a, b) => b.value.first.lastMessageTime.compareTo(
          a.value.first.lastMessageTime,
        ),
      );

    return ListView.builder(
      padding: EdgeInsets.only(top: widget.topPadding, bottom: 20),
      itemCount: sortedGroups.length + 1,
      itemBuilder: (_, i) {
        if (i == 0) return _buildCountHeader(sessions.length);
        final entry = sortedGroups[i - 1];
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

  Widget _buildCountHeader(int count) {
    if (widget.collapsed) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Text(
        '$count ${'count_chats'.plural(count)}',
        style: TextStyle(
          fontSize: 11,
          color: context.cs.onSurfaceVariant,
        ),
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
    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, -0.04), end: Offset.zero).animate(
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
              alignment: AlignmentDirectional.topStart,
              child: SlideTransition(
                position: _slideAnimation,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: GlassSurface(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (int i = 0; i < widget.sessions.length; i++) ...[
                          if (i > 0)
                            Divider(
                              height: 1,
                              thickness: 0.5,
                              color: Colors.white.withValues(alpha: 0.08),
                              indent: 12,
                              endIndent: 12,
                            ),
                          _SessionTile(
                            info: widget.sessions[i],
                            isGrouped: true,
                          ),
                        ],
                      ],
                    ),
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

class _SessionTile extends ConsumerWidget {
  final ChatSessionInfo info;
  final bool isGrouped;
  final bool collapsed;

  const _SessionTile({
    required this.info,
    this.isGrouped = false,
    this.collapsed = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (collapsed) return _buildCollapsedTile(context, ref);
    if (isGrouped) return _buildGroupedTile(context, ref);
    return _buildFullTile(context, ref);
  }

  Widget _buildCollapsedTile(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () =>
          context.go('/chat/${info.characterId}?session=${info.sessionIndex}'),
      child: Tooltip(
        message: info.characterName,
        preferBelow: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: _buildAvatar(context, ref, size: 36),
        ),
      ),
    );
  }

  Widget _buildFullTile(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () =>
          context.go('/chat/${info.characterId}?session=${info.sessionIndex}'),
      onLongPress: () => _showSessionActions(context, ref),
      child: Container(
        height: 72,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            _buildAvatar(context, ref),
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
                      _buildChip(context),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    info.sessionName?.isNotEmpty == true
                        ? info.sessionName!
                        : 'session_name'.tr(namedArgs: {
                            'id': (info.sessionIndex + 1).toString(),
                          }),
                    style: TextStyle(
                      fontSize: 12,
                      color: context.cs.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  MessagePreviewText(
                    raw: info.lastMessage,
                    style: TextStyle(
                      fontSize: 13,
                      height: 16 / 13,
                      color: context.cs.onSurfaceVariant,
                    ),
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
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.go(
        '/chat/${info.characterId}?session=${info.sessionIndex}',
      ),
      onLongPress: () => _showSessionActions(context, ref),
      child: Padding(
        padding: const EdgeInsets.all(12),
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
                        : 'session_name'.tr(namedArgs: {
                            'id': (info.sessionIndex + 1).toString(),
                          }),
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
                _buildChip(context),
              ],
            ),
            const SizedBox(height: 4),
            MessagePreviewText(
              raw: info.lastMessage,
              style: TextStyle(
                fontSize: 12,
                color: context.cs.onSurfaceVariant,
              ),
              maxLines: 2,
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime() {
    if (info.lastMessageTime == 0) return '';
    return formatTimeAgo(info.lastMessageTime);
  }

  void _showRenameDialog(BuildContext context, WidgetRef ref) {
    final currentName = info.sessionName?.isNotEmpty == true
        ? info.sessionName!
        : 'session_name'
            .tr(namedArgs: {'id': (info.sessionIndex + 1).toString()});
    GlazeBottomSheet.show<void>(
      context,
      title: 'Rename Session',
      input: BottomSheetInput(
        placeholder: 'Session name',
        value: currentName,
        confirmLabel: 'action_rename'.tr(),
        onConfirm: (val) {
          Navigator.of(context, rootNavigator: true).pop();
          if (val.trim().isNotEmpty) {
            ref
                .read(chatHistoryProvider.notifier)
                .renameSession(info.sessionId, val.trim());
            ref.invalidate(chatProvider(info.characterId));
          }
        },
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref) {
    GlazeBottomSheet.show<void>(
      context,
      title: 'action_delete_session'.tr(),
      bigInfo: BottomSheetBigInfo(
        icon: Icons.delete_outline,
        description:
            '${'action_delete_session'.tr()} \u2014 ${info.characterName}? ${'chat_clear_confirm'.tr()}',
      ),
      items: [
        BottomSheetItem(
          label: 'btn_delete'.tr(),
          isDestructive: true,
          centered: true,
          onTap: () {
            Navigator.of(context, rootNavigator: true).pop();
            ref
                .read(chatHistoryProvider.notifier)
                .deleteSession(info.sessionId);
          },
        ),
        BottomSheetItem(
          label: 'btn_cancel'.tr(),
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
          label: 'action_export_chat'.tr(),
          onTap: () => Navigator.of(context, rootNavigator: true).pop('export'),
        ),
        BottomSheetItem(
          icon: Icons.drive_file_rename_outline,
          label: 'action_rename'.tr(),
          onTap: () => Navigator.of(context, rootNavigator: true).pop('rename'),
        ),
        BottomSheetItem(
          icon: Icons.delete_outline,
          label: 'action_delete'.tr(),
          isDestructive: true,
          onTap: () => Navigator.of(context, rootNavigator: true).pop('delete'),
        ),
      ],
    ).then((result) {
      if (!context.mounted) return;
      switch (result) {
        case 'export':
          ref
              .read(chatActionsServiceProvider)
              .exportSessionUI(
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

  Widget _buildAvatar(BuildContext context, WidgetRef ref, {double size = 48}) {
    ref.watch(avatarVersionProvider);
    final image = glazeAvatarImage(info.avatarPath);
    if (image != null) {
      return ClipOval(
        child: SizedBox.square(
          dimension: size,
          child: Image(
            image: image,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (ctx, e, st) => _defaultAvatar(context, size),
          ),
        ),
      );
    }
    return _defaultAvatar(context, size);
  }

  Widget _defaultAvatar(BuildContext context, double size) => CircleAvatar(
    radius: size / 2,
    backgroundColor: context.cs.primary,
    child: Text(
      info.characterName.isNotEmpty ? info.characterName[0].toUpperCase() : '?',
      style: const TextStyle(color: Colors.black, fontSize: 18),
    ),
  );

  Widget _buildChip(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.mail_outline,
            size: 12,
            color: context.cs.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
          Text(
            '${info.messageCount} ${'count_messages'.plural(info.messageCount)}${info.lastMessageTime > 0 ? ' · ${_formatTime()}' : ''}',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: context.cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
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
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: () => _showGroupActions(context, ref, latest),
      child: Container(
        height: 72,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            _buildAvatar(context, ref, latest),
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
                        'count_sessions_format'.plural(sessions.length),
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
                  MessagePreviewText(
                    raw: latest.lastMessage,
                    style: TextStyle(
                      fontSize: 13,
                      height: 16 / 13,
                      color: context.cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar(
    BuildContext context,
    WidgetRef ref,
    ChatSessionInfo info,
  ) {
    ref.watch(avatarVersionProvider);
    final image = glazeAvatarImage(info.avatarPath);
    if (image != null) {
      return ClipOval(
        child: SizedBox.square(
          dimension: 48,
          child: Image(
            image: image,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (ctx, e, st) => _defaultGroupAvatar(context, info),
          ),
        ),
      );
    }
    return _defaultGroupAvatar(context, info);
  }

  Widget _defaultGroupAvatar(BuildContext context, ChatSessionInfo info) =>
      CircleAvatar(
        radius: 24,
        backgroundColor: context.cs.primary,
        child: Text(
          info.characterName.isNotEmpty
              ? info.characterName[0].toUpperCase()
              : '?',
          style: const TextStyle(color: Colors.black, fontSize: 18),
        ),
      );

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
    BuildContext context,
    WidgetRef ref,
    ChatSessionInfo info,
  ) {
    GlazeBottomSheet.show<String>(
      context,
      title: info.characterName,
      items: [
        BottomSheetItem(
          icon: Icons.add_comment_outlined,
          label: 'action_new_session'.tr(),
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
        ref.read(chatProvider(info.characterId).notifier).createNewSession();
        context.go('/chat/${info.characterId}');
      } else if (result == 'edit') {
        context.push('/character/${info.characterId}/edit');
      }
    });
  }
}

String formatTimeAgo(int epochMs) {
  final now = DateTime.now();
  final diff = now.difference(
    DateTime.fromMillisecondsSinceEpoch(epochMs),
  );
  if (diff.inMinutes < 1) return 'now';
  if (diff.inHours < 1) return '${diff.inMinutes}m';
  if (diff.inDays < 1) return '${diff.inHours}h';
  if (diff.inDays < 7) return '${diff.inDays}d';
  return '${diff.inDays ~/ 7}w';
}
