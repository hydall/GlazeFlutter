import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/llm/regex_service.dart';
import '../../../core/llm/tokenizer.dart';
import '../../../core/state/active_selection_provider.dart';
import '../../../core/state/character_provider.dart';
import '../../../shared/widgets/pencil_animation.dart';
import '../../image_gen/widgets/image_content_renderer.dart';
import '../../settings/app_settings_provider.dart';
import '../chat_provider.dart';
import 'message_actions.dart';

class Message extends ConsumerWidget {
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
  final List<String> swipes;
  final int swipeId;
  final Map<String, dynamic> memoryCoverage;

  const Message({
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
    this.swipes = const [],
    this.swipeId = 0,
    this.memoryCoverage = const {},
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
    final effectiveTokens = (tokens != null && tokens! > 0)
        ? tokens
        : (isUser && content.isNotEmpty ? estimateTokens(content) : null);

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
                  if (messageIndex >= 0) ...[
                    const SizedBox(width: 6),
                    Text('#${messageIndex + 1}', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant.withValues(alpha: 0.55))),
                  ],
                ],
              ),
              const SizedBox(height: 8),
            ],
            if (reasoning != null && reasoning!.isNotEmpty)
              _ReasoningBlock(reasoning: reasoning!, scheme: scheme),
            if (isTyping && content.isEmpty)
              _TypingIndicator(textColor: textColor, scheme: scheme)
            else if (ImageContentRenderer.hasImageMarkers(displayContent))
              ImageContentRenderer(content: displayContent, textColor: textColor)
            else
              MarkdownBody(data: displayContent, styleSheet: MarkdownStyleSheet(p: TextStyle(color: textColor))),
            if (isStreaming)
              Text('...', style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
            if (!isSystem && !isStreaming) ...[
              const SizedBox(height: 6),
              _MetadataRow(
                genTime: genTime,
                tokens: effectiveTokens,
                textColor: textColor,
                isStandard: isStandard,
                isUser: isUser,
                scheme: scheme,
                messageIndex: messageIndex,
                onMenuTap: () => showMessageContextMenu(
                  context: context, ref: ref, charId: charId, content: content,
                  messageIndex: messageIndex, isUser: isUser, isTyping: isTyping,
                  isError: isError, isLast: isLast, isGenerating: isGenerating, isHidden: isHidden,
                  totalMessages: totalMessages,
                ),
                swipeCount: swipes.length,
                swipeId: swipeId,
                onSwipeLeft: swipeId > 0
                    ? () => ref.read(chatProvider(charId).notifier).setSwipe(messageIndex, swipeId - 1)
                    : null,
                onSwipeRight: swipeId < swipes.length - 1
                    ? () => ref.read(chatProvider(charId).notifier).setSwipe(messageIndex, swipeId + 1)
                    : null,
                memoryEntryCount: memoryCoverage.length,
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
        totalMessages: totalMessages,
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

class _ReasoningBlock extends StatefulWidget {
  final String reasoning;
  final ColorScheme scheme;
  const _ReasoningBlock({required this.reasoning, required this.scheme});

  @override
  State<_ReasoningBlock> createState() => _ReasoningBlockState();
}

class _ReasoningBlockState extends State<_ReasoningBlock> {
  bool _collapsed = true;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(color: widget.scheme.surfaceContainerLow, borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _collapsed = !_collapsed),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Icon(Icons.psychology, size: 14, color: widget.scheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text('Reasoning', style: TextStyle(fontSize: 11, color: widget.scheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  AnimatedRotation(
                    turns: _collapsed ? -0.25 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(Icons.expand_more, size: 16, color: widget.scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            child: _collapsed
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    child: Text(
                      widget.reasoning,
                      style: TextStyle(fontSize: 12, color: widget.scheme.onSurfaceVariant, fontStyle: FontStyle.italic),
                    ),
                  ),
          ),
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
  final int messageIndex;
  final int swipeCount;
  final int swipeId;
  final VoidCallback? onSwipeLeft;
  final VoidCallback? onSwipeRight;
  final int memoryEntryCount;

  const _MetadataRow({
    required this.genTime,
    required this.tokens,
    required this.textColor,
    required this.isStandard,
    required this.isUser,
    required this.scheme,
    required this.onMenuTap,
    required this.messageIndex,
    this.swipeCount = 1,
    this.swipeId = 0,
    this.onSwipeLeft,
    this.onSwipeRight,
    this.memoryEntryCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Left: metadata stats
        Expanded(
          child: Row(
            children: [
              if (!isStandard && messageIndex >= 0) ...[
                Text('#${messageIndex + 1}', style: TextStyle(fontSize: 11, color: textColor.withValues(alpha: 0.55))),
                const SizedBox(width: 8),
              ],
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
              if (memoryEntryCount > 0) ...[
                const SizedBox(width: 8),
                Icon(Icons.auto_stories, size: 12, color: textColor.withValues(alpha: 0.7)),
                const SizedBox(width: 4),
                Text('$memoryEntryCount mem', style: TextStyle(fontSize: 11, color: textColor.withValues(alpha: 0.7))),
              ],
            ],
          ),
        ),
        // Center: swipe switcher
        if (swipeCount > 1)
          Container(
            height: 22,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.15)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _swipeBtn(Icons.chevron_left, onSwipeLeft),
                SizedBox(
                  width: 28,
                  child: Text(
                    '${swipeId + 1}/$swipeCount',
                    style: TextStyle(fontSize: 11, color: textColor.withValues(alpha: 0.8)),
                    textAlign: TextAlign.center,
                  ),
                ),
                _swipeBtn(Icons.chevron_right, onSwipeRight),
              ],
            ),
          ),
        // Right: action button
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: InkWell(
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
          ),
        ),
      ],
    );
  }

  Widget _swipeBtn(IconData icon, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 20,
        height: 20,
        child: Center(
          child: Icon(icon, size: 16, color: textColor.withValues(alpha: onTap != null ? 0.7 : 0.25)),
        ),
      ),
    );
  }
}
