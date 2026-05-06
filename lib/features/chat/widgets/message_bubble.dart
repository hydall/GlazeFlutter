import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/llm/regex_service.dart';
import '../../../core/models/character.dart';
import '../../../core/models/persona.dart';
import '../../../core/state/active_selection_provider.dart';
import '../../../core/state/character_provider.dart';
import '../../../core/state/db_provider.dart';
import '../../../shared/widgets/pencil_animation.dart';
import '../../settings/app_settings_provider.dart';
import 'message_actions.dart';

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
  final int totalMessages;
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
    required this.totalMessages,
    required this.isLast,
    required this.isGenerating,
    required this.charId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final appSettings = ref.watch(appSettingsProvider).value;
    final isStandard = (appSettings?.chatLayout ?? 'default') == 'default';

    final chars = ref.watch(charactersProvider).value ?? [];
    final character = chars.where((c) => c.id == charId).firstOrNull;

    final regexScripts = ref.watch(activeRegexesProvider).value ?? [];
    final placement = isUser ? 1 : 2;
    final depth = totalMessages > 0 ? totalMessages - 1 - messageIndex : null;
    final regexCtx = RegexApplyContext(
      char: character,
      persona: null,
      depth: depth,
      totalMessages: totalMessages,
    );
    final displayContent = regexScripts.isEmpty
        ? content
        : applyRegexes(content, placement, 1, regexScripts, regexCtx);

    final style = _BubbleStyle.resolve(scheme: scheme, isStandard: isStandard, isUser: isUser, isSystem: isSystem);

    String displayName = isUser ? 'User' : (character?.name ?? 'Character');
    String avatarLetter = displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';

    FileImage? avatarImage;
    if (!isUser && character?.avatarPath != null && character!.avatarPath!.isNotEmpty) {
      avatarImage = FileImage(File(character.avatarPath!));
    }

    final textColor = style.textColor;

    Widget bubble = Align(
      alignment: style.alignment,
      child: Container(
        constraints: BoxConstraints(maxWidth: isStandard ? double.infinity : MediaQuery.of(context).size.width * 0.88),
        margin: EdgeInsets.symmetric(horizontal: isStandard ? 16 : 12, vertical: isStandard ? 8 : 4),
        padding: isStandard ? const EdgeInsets.all(0) : const EdgeInsets.all(12),
        decoration: BoxDecoration(color: style.bg, borderRadius: isStandard ? BorderRadius.zero : BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isStandard && !isSystem) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 12,
                    backgroundColor: isUser ? scheme.primary : scheme.surfaceContainerHighest,
                    backgroundImage: avatarImage,
                    child: avatarImage == null ? Text(avatarLetter, style: TextStyle(fontSize: 12, color: isUser ? scheme.onPrimary : scheme.onSurface, fontWeight: FontWeight.bold)) : null,
                  ),
                  const SizedBox(width: 8),
                  Text(displayName, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: scheme.onSurfaceVariant)),
                ],
              ),
              const SizedBox(height: 8),
            ],
            if (reasoning != null && reasoning!.isNotEmpty)
              _ReasoningBlock(reasoning: reasoning!, scheme: scheme),
            if (isTyping && content.isEmpty)
              _TypingIndicator(textColor: textColor, scheme: scheme)
            else
              MarkdownBody(data: displayContent, styleSheet: MarkdownStyleSheet(p: TextStyle(color: textColor))),
            if (isStreaming)
              Text('...', style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
            if (!isSystem && !isStreaming) ...[
              const SizedBox(height: 6),
              _MetadataRow(
                genTime: genTime,
                tokens: tokens,
                textColor: textColor,
                isStandard: isStandard,
                isUser: isUser,
                scheme: scheme,
                onMenuTap: () => showMessageContextMenu(
                  context: context, ref: ref, charId: charId, content: content,
                  messageIndex: messageIndex, isUser: isUser, isTyping: isTyping,
                  isError: isError, isLast: isLast, isGenerating: isGenerating, isHidden: isHidden,
                ),
              ),
            ],
          ],
        ),
      ),
    );

    Widget bubbleWidget = isHidden ? Opacity(opacity: 0.5, child: bubble) : bubble;
    if (isSystem || isStreaming) return bubbleWidget;

    return GestureDetector(
      onLongPress: () => showMessageContextMenu(
        context: context, ref: ref, charId: charId, content: content,
        messageIndex: messageIndex, isUser: isUser, isTyping: isTyping,
        isError: isError, isLast: isLast, isGenerating: isGenerating, isHidden: isHidden,
      ),
      child: bubbleWidget,
    );
  }
}

class _BubbleStyle {
  final Color bg;
  final Alignment alignment;
  final Color textColor;

  const _BubbleStyle({required this.bg, required this.alignment, required this.textColor});

  factory _BubbleStyle.resolve({
    required ColorScheme scheme,
    required bool isStandard,
    required bool isUser,
    required bool isSystem,
  }) {
    if (isStandard) {
      return _BubbleStyle(bg: Colors.transparent, alignment: Alignment.centerLeft, textColor: scheme.onSurface);
    }
    if (isUser) {
      return _BubbleStyle(bg: scheme.primary, alignment: Alignment.centerRight, textColor: scheme.onPrimary);
    }
    if (isSystem) {
      return _BubbleStyle(bg: scheme.surfaceContainerLow, alignment: Alignment.center, textColor: scheme.onSurface);
    }
    return _BubbleStyle(bg: scheme.surfaceContainerHighest, alignment: Alignment.centerLeft, textColor: scheme.onSurface);
  }
}

class _ReasoningBlock extends StatelessWidget {
  final String reasoning;
  final ColorScheme scheme;
  const _ReasoningBlock({required this.reasoning, required this.scheme});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: scheme.surfaceContainerLow, borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.psychology, size: 14, color: scheme.onSurfaceVariant),
            const SizedBox(width: 4),
            Text('Reasoning', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 4),
          Text(reasoning, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant, fontStyle: FontStyle.italic)),
        ],
      ),
    );
  }
}

class _TypingIndicator extends StatelessWidget {
  final Color textColor;
  final ColorScheme scheme;
  const _TypingIndicator({required this.textColor, required this.scheme});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PencilAnimation(size: 16, color: scheme.primary),
          const SizedBox(width: 8),
          Text('Generating...', style: TextStyle(fontSize: 14, fontStyle: FontStyle.italic, color: textColor)),
        ],
      ),
    );
  }
}

class _MetadataRow extends StatelessWidget {
  final String? genTime;
  final int? tokens;
  final Color textColor;
  final bool isStandard;
  final bool isUser;
  final ColorScheme scheme;
  final VoidCallback onMenuTap;

  const _MetadataRow({
    required this.genTime,
    required this.tokens,
    required this.textColor,
    required this.isStandard,
    required this.isUser,
    required this.scheme,
    required this.onMenuTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (genTime != null) ...[
          Icon(Icons.access_time, size: 12, color: textColor),
          const SizedBox(width: 4),
          Text(genTime!, style: TextStyle(fontSize: 12, color: textColor)),
          const SizedBox(width: 12),
        ],
        if (tokens != null && tokens! > 0) ...[
          Icon(Icons.description_outlined, size: 12, color: textColor),
          const SizedBox(width: 4),
          Text('${tokens}t', style: TextStyle(fontSize: 12, color: textColor)),
        ],
        const Spacer(),
        InkWell(
          onTap: onMenuTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: isStandard ? scheme.surfaceContainerHighest : (isUser ? Colors.transparent : scheme.surfaceContainerHighest),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.menu, size: 16, color: textColor),
          ),
        ),
      ],
    );
  }
}
