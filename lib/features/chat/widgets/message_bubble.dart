import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/state/character_provider.dart';
import '../chat_provider.dart';
import '../../settings/app_settings_provider.dart';
import '../../../shared/widgets/pencil_animation.dart';

class MessageBubble extends ConsumerWidget {
  final String content;
  final bool isUser;
  final bool isSystem;
  final bool isStreaming;
  final bool isTyping;
  final String? reasoning;
  final String? genTime;
  final int? tokens;
  final bool isHidden;
  final bool isError;
  final int messageIndex;
  final bool isLast;
  final bool isGenerating;
  final String charId;

  const MessageBubble({
    super.key,
    required this.content,
    required this.isUser,
    this.isSystem = false,
    this.isStreaming = false,
    this.isTyping = false,
    this.reasoning,
    this.genTime,
    this.tokens,
    this.isHidden = false,
    this.isError = false,
    required this.messageIndex,
    required this.isLast,
    required this.isGenerating,
    required this.charId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final appSettings = ref.watch(appSettingsProvider).value;
    final layoutMode = appSettings?.chatLayout ?? 'default';
    final isStandard = layoutMode == 'default';

    final chars = ref.watch(charactersProvider).value ?? [];
    final character = chars.where((c) => c.id == charId).firstOrNull;

    Color bg;
    Alignment alignment;
    if (isStandard) {
      bg = Colors.transparent;
      alignment = Alignment.centerLeft;
    } else {
      if (isUser) {
        bg = scheme.primary;
        alignment = Alignment.centerRight;
      } else if (isSystem) {
        bg = scheme.surfaceContainerLow;
        alignment = Alignment.center;
      } else {
        bg = scheme.surfaceContainerHighest;
        alignment = Alignment.centerLeft;
      }
    }

    String displayName = isUser ? 'User' : (character?.name ?? 'Character');
    String avatarLetter = displayName.isNotEmpty
        ? displayName[0].toUpperCase()
        : '?';

    FileImage? avatarImage;
    if (!isUser &&
        character?.avatarPath != null &&
        character!.avatarPath!.isNotEmpty) {
      avatarImage = FileImage(File(character.avatarPath!));
    }

    Widget bubble = Align(
      alignment: alignment,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: isStandard
              ? double.infinity
              : MediaQuery.of(context).size.width * 0.88,
        ),
        margin: EdgeInsets.symmetric(
          horizontal: isStandard ? 16 : 12,
          vertical: isStandard ? 8 : 4,
        ),
        padding: isStandard
            ? const EdgeInsets.all(0)
            : const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: isStandard
              ? BorderRadius.zero
              : BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isStandard && !isSystem) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 12,
                    backgroundColor: isUser
                        ? scheme.primary
                        : scheme.surfaceContainerHighest,
                    backgroundImage: avatarImage,
                    child: avatarImage == null
                        ? Text(
                            avatarLetter,
                            style: TextStyle(
                              fontSize: 12,
                              color: isUser
                                  ? scheme.onPrimary
                                  : scheme.onSurface,
                              fontWeight: FontWeight.bold,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    displayName,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            if (reasoning != null && reasoning!.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.psychology,
                          size: 14,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Reasoning',
                          style: TextStyle(
                            fontSize: 11,
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      reasoning!,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
            if (isTyping && content.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PencilAnimation(
                      size: 16,
                      color: (isStandard || !isUser)
                          ? scheme.primary
                          : scheme.onPrimary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Generating...',
                      style: TextStyle(
                        fontSize: 14,
                        fontStyle: FontStyle.italic,
                        color: (isStandard || !isUser)
                            ? scheme.onSurfaceVariant
                            : scheme.onPrimary,
                      ),
                    ),
                  ],
                ),
              )
            else
              MarkdownBody(
                data: content,
                styleSheet: MarkdownStyleSheet(
                  p: TextStyle(
                    color: (isStandard || !isUser)
                        ? scheme.onSurface
                        : scheme.onPrimary,
                  ),
                ),
              ),
            if (isStreaming)
              Text(
                '...',
                style: TextStyle(
                  color: (isStandard || !isUser)
                      ? scheme.onSurfaceVariant
                      : scheme.onPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            if (!isSystem && !isStreaming) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  if (genTime != null) ...[
                    Icon(
                      Icons.access_time,
                      size: 12,
                      color: (isStandard || !isUser)
                          ? scheme.onSurfaceVariant
                          : scheme.onPrimary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      genTime!,
                      style: TextStyle(
                        fontSize: 12,
                        color: (isStandard || !isUser)
                            ? scheme.onSurfaceVariant
                            : scheme.onPrimary,
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  if (tokens != null && tokens! > 0) ...[
                    Icon(
                      Icons.description_outlined,
                      size: 12,
                      color: (isStandard || !isUser)
                          ? scheme.onSurfaceVariant
                          : scheme.onPrimary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${tokens}t',
                      style: TextStyle(
                        fontSize: 12,
                        color: (isStandard || !isUser)
                            ? scheme.onSurfaceVariant
                            : scheme.onPrimary,
                      ),
                    ),
                  ],
                  const Spacer(),
                  InkWell(
                    onTap: () => _showContextMenu(context, ref),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: isStandard
                            ? scheme.surfaceContainerHighest
                            : (isUser
                                  ? Colors.transparent
                                  : scheme.surfaceContainerHighest),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.menu,
                        size: 16,
                        color: (isStandard || !isUser)
                            ? scheme.onSurfaceVariant
                            : scheme.onPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );

    Widget bubbleWidget = isHidden
        ? Opacity(opacity: 0.5, child: bubble)
        : bubble;
    if (isSystem || isStreaming) return bubbleWidget;

    return GestureDetector(
      onLongPress: () => _showContextMenu(context, ref),
      child: bubbleWidget,
    );
  }

  void _showContextMenu(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(chatProvider(charId).notifier);

    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isTyping) ...[
                ListTile(
                  leading: const Icon(Icons.stop_circle, color: Colors.orange),
                  title: const Text(
                    'Stop Generating',
                    style: TextStyle(color: Colors.orange),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    notifier.abortGeneration();
                  },
                ),
              ] else ...[
                ListTile(
                  leading: const Icon(Icons.copy),
                  title: const Text('Copy'),
                  onTap: isGenerating && isLast
                      ? null
                      : () {
                          Clipboard.setData(ClipboardData(text: content));
                          Navigator.pop(ctx);
                        },
                  enabled: !(isGenerating && isLast),
                ),
                if (!isError)
                  ListTile(
                    leading: const Icon(Icons.edit),
                    title: const Text('Edit'),
                    onTap: isGenerating && isLast
                        ? null
                        : () {
                            Navigator.pop(ctx);
                            _showEditDialog(context, ref);
                          },
                    enabled: !(isGenerating && isLast),
                  ),
                if ((!isUser && isLast && !isGenerating) || isError)
                  ListTile(
                    leading: const Icon(Icons.refresh),
                    title: const Text('Regenerate'),
                    onTap: () {
                      Navigator.pop(ctx);
                      notifier.regenerateLastAssistant();
                    },
                  ),
                if (isGenerating && isLast)
                  ListTile(
                    leading: const Icon(
                      Icons.stop_circle,
                      color: Colors.orange,
                    ),
                    title: const Text(
                      'Stop Generating',
                      style: TextStyle(color: Colors.orange),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      notifier.abortGeneration();
                    },
                  ),
                if (!isError)
                  ListTile(
                    leading: const Icon(Icons.call_split),
                    title: const Text('Branch'),
                    onTap: isGenerating && isLast
                        ? null
                        : () {
                            Navigator.pop(ctx);
                            notifier.branchSession(messageIndex);
                          },
                    enabled: !(isGenerating && isLast),
                  ),
                ListTile(
                  leading: Icon(
                    isHidden ? Icons.visibility : Icons.visibility_off,
                  ),
                  title: Text(isHidden ? 'Unhide' : 'Hide'),
                  onTap: () {
                    Navigator.pop(ctx);
                    notifier.toggleMessageHidden(messageIndex);
                  },
                ),
                if (isLast && !isGenerating)
                  ListTile(
                    leading: const Icon(Icons.delete, color: Colors.red),
                    title: const Text(
                      'Delete',
                      style: TextStyle(color: Colors.red),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      notifier.deleteMessage(messageIndex);
                    },
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showEditDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController(text: content);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Message'),
        content: TextField(
          controller: controller,
          maxLines: 8,
          minLines: 3,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final newText = controller.text.trim();
              if (newText.isNotEmpty) {
                ref
                    .read(chatProvider(charId).notifier)
                    .editMessage(messageIndex, newText);
              }
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
