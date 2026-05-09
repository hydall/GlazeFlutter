import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:markdown/markdown.dart' as md;

import '../../../core/llm/regex_service.dart';
import '../../../core/llm/tokenizer.dart';
import '../../../core/models/character.dart';
import '../../../core/state/active_selection_provider.dart';
import '../../../core/state/character_provider.dart';
import '../../../shared/widgets/pencil_animation.dart';
import '../../image_gen/widgets/image_content_renderer.dart';
import '../../settings/app_settings_provider.dart';
import '../chat_provider.dart';
import '../editing_message_provider.dart';
import 'message_actions.dart';

class MarkSyntax extends md.InlineSyntax {
  MarkSyntax() : super(r'==mark==(.*?)==');
  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final el = md.Element.text('mark', match[1]!);
    parser.addNode(el);
    return true;
  }
}

class ActiveMarkSyntax extends md.InlineSyntax {
  ActiveMarkSyntax() : super(r'==active==(.*?)==');
  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final el = md.Element.text('activemark', match[1]!);
    parser.addNode(el);
    return true;
  }
}

class _MarkElementBuilder extends MarkdownElementBuilder {
  final Color bgColor;
  final Color textColor;
  final GlobalKey? activeKey;
  _MarkElementBuilder(this.bgColor, this.textColor, {this.activeKey});

  @override
  Widget visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    return Container(
      key: activeKey,
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(2)),
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
      child: Text(
        element.textContent,
        style: preferredStyle?.copyWith(color: textColor) ?? TextStyle(color: textColor),
      ),
    );
  }
}

class Message extends ConsumerStatefulWidget {
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
  final int? greetingIndex;
  final Map<String, dynamic> memoryCoverage;
  final bool isSearchMatch;
  final String searchQuery;
  final int activeMatchIndex;

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
    this.greetingIndex,
    this.memoryCoverage = const {},
    this.isSearchMatch = false,
    this.searchQuery = '',
    this.activeMatchIndex = -1,
  });

  @override
  ConsumerState<Message> createState() => _MessageState();
}

class _MessageState extends ConsumerState<Message> {
  TextEditingController? _editController;
  bool _highlighted = false;
  final GlobalKey _activePhraseKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    if (widget.isSearchMatch) {
      _triggerHighlight();
    }
  }

  @override
  void didUpdateWidget(Message oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((widget.isSearchMatch && !oldWidget.isSearchMatch) ||
        (widget.activeMatchIndex != -1 && widget.activeMatchIndex != oldWidget.activeMatchIndex)) {
      _triggerHighlight();
    }
  }

  String _highlightPhrases(String content) {
    String text = content;
    
    text = text.replaceAllMapped(
      RegExp(r'(```.*?```|`[^`]*`)|"(?:(?!\n\n)[^"])*"|«(?:(?!\n\n)[^»])*»|“(?:(?!\n\n)[^”])*”|‘(?:(?!\n\n)[^’])*’|(?<!\p{L})\x27(?:(?!\n\n)[^\x27])*\x27(?!\p{L})', unicode: true, dotAll: true), 
      (match) {
        if (match[1] != null) return match[1]!;
        return '~~${match[0]}~~';
      }
    );

    if (widget.searchQuery.isEmpty || !widget.isSearchMatch) return text;
    final lowerContent = text.toLowerCase();
    final lowerQuery = widget.searchQuery.toLowerCase();
    final buffer = StringBuffer();
    int startIndex = 0;
    int currentMatchIndex = 0;
    
    while (true) {
      final idx = lowerContent.indexOf(lowerQuery, startIndex);
      if (idx == -1) {
        buffer.write(text.substring(startIndex));
        break;
      }
      buffer.write(text.substring(startIndex, idx));
      final originalText = text.substring(idx, idx + lowerQuery.length);
      if (currentMatchIndex == widget.activeMatchIndex) {
        buffer.write('==active==$originalText==');
      } else {
        buffer.write('==mark==$originalText==');
      }
      currentMatchIndex++;
      startIndex = idx + lowerQuery.length;
    }
    return buffer.toString();
  }

  void _triggerHighlight() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_activePhraseKey.currentContext != null) {
        Scrollable.ensureVisible(
          _activePhraseKey.currentContext!,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          alignment: 0.5,
        );
      } else {
        Scrollable.ensureVisible(
          context,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          alignment: 0.5,
        );
      }
      setState(() => _highlighted = true);
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _highlighted = false);
      });
    });
  }

  @override
  void dispose() {
    _editController?.dispose();
    super.dispose();
  }

  void _ensureEditController() {
    _editController ??= TextEditingController(text: widget.content);
  }

  void _disposeEditController() {
    _editController?.dispose();
    _editController = null;
  }

  void _saveEdit() {
    final text = _editController?.text.trim() ?? '';
    if (text.isNotEmpty) {
      ref.read(chatProvider(widget.charId).notifier).editMessage(widget.messageIndex, text);
    }
    ref.read(editingMessageIndexProvider(widget.charId).notifier).state = null;
  }

  void _cancelEdit() {
    ref.read(editingMessageIndexProvider(widget.charId).notifier).state = null;
  }

  @override
  Widget build(BuildContext context) {
    final content = widget.content;
    final isUser = widget.isUser;
    final isSystem = widget.isSystem;
    final isStreaming = widget.isStreaming;
    final isTyping = widget.isTyping;
    final reasoning = widget.reasoning;
    final genTime = widget.genTime;
    final tokens = widget.tokens;
    final isHidden = widget.isHidden;
    final isError = widget.isError;
    final messageIndex = widget.messageIndex;
    final totalMessages = widget.totalMessages;
    final isLast = widget.isLast;
    final isGenerating = widget.isGenerating;
    final charId = widget.charId;
    final memoryCoverage = widget.memoryCoverage;

    final scheme = Theme.of(context).colorScheme;
    final appSettings = ref.watch(appSettingsProvider).value;
    final isStandard = (appSettings?.chatLayout ?? 'default') == 'default';

    final editingIndex = ref.watch(editingMessageIndexProvider(charId));
    final isEditing = editingIndex == messageIndex && !isSystem && !isStreaming && !isTyping;
    if (isEditing) {
      _ensureEditController();
    } else if (_editController != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && ref.read(editingMessageIndexProvider(charId)) != widget.messageIndex) {
          _disposeEditController();
        }
      });
    }

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

    final quoteColor = (isUser && !isStandard) ? scheme.inversePrimary : scheme.primary;
    final asteriskColor = textColor.withValues(alpha: 0.65);

    Widget bubble = Align(
      alignment: style.alignment,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        constraints: BoxConstraints(maxWidth: isStandard ? double.infinity : MediaQuery.of(context).size.width * 0.88),
        margin: EdgeInsets.symmetric(horizontal: isStandard ? 16 : 12, vertical: isStandard ? 8 : 4),
        padding: isStandard ? const EdgeInsets.all(0) : const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _highlighted ? scheme.primary.withValues(alpha: 0.2) : style.bg,
          borderRadius: isStandard ? BorderRadius.zero : BorderRadius.circular(16)
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
            if (reasoning != null && reasoning!.isNotEmpty && !isEditing)
              _ReasoningBlock(reasoning: reasoning!, scheme: scheme),
            if (isEditing)
              _EditTextarea(controller: _editController!, textColor: textColor, scheme: scheme)
            else if (isTyping && content.isEmpty)
              _TypingIndicator(textColor: textColor, scheme: scheme)
            else if (ImageContentRenderer.hasImageMarkers(displayContent))
              ImageContentRenderer(content: displayContent, textColor: textColor)
            else if (_hasHtmlTags(displayContent))
              Html(
                data: displayContent,
                style: {
                  'body': Style(color: textColor, margin: Margins.zero, padding: HtmlPaddings.zero),
                  'p': Style(color: textColor, margin: Margins.zero),
                  'em': Style(color: asteriskColor, fontStyle: FontStyle.italic),
                  'strong': Style(color: asteriskColor, fontWeight: FontWeight.bold),
                  'blockquote': Style(color: textColor, border: Border(left: BorderSide(color: asteriskColor, width: 3))),
                },
              )
            else
              MarkdownBody(
                data: _highlightPhrases(displayContent), 
                styleSheet: MarkdownStyleSheet(
                  p: TextStyle(color: textColor),
                  em: TextStyle(color: asteriskColor, fontStyle: FontStyle.italic),
                  strong: TextStyle(color: asteriskColor, fontWeight: FontWeight.bold),
                  del: TextStyle(color: quoteColor, decoration: TextDecoration.none),
                ),
                extensionSet: md.ExtensionSet([
                  ...md.ExtensionSet.gitHubFlavored.blockSyntaxes
                ], [
                  ...md.ExtensionSet.gitHubFlavored.inlineSyntaxes,
                  MarkSyntax(),
                  ActiveMarkSyntax(),
                ]),
                builders: {
                  'mark': _MarkElementBuilder(scheme.primary.withValues(alpha: 0.3), scheme.onSurface),
                  'activemark': _MarkElementBuilder(Colors.orange.withValues(alpha: 0.6), Colors.white, activeKey: _activePhraseKey),
                },
              ),
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
                ),
                swipeCount: _switcherCount(character),
                swipeId: _switcherIndex(character),
                onSwipeLeft: isEditing ? null : _onSwitcherLeft(character),
                onSwipeRight: isEditing ? null : _onSwitcherRight(character),
                memoryEntryCount: memoryCoverage.length,
                onRegenerate: (!isEditing && ((isUser && isLast) || isError) && !isGenerating)
                    ? () => ref.read(chatProvider(charId).notifier).regenerateLastAssistant()
                    : null,
                isEditing: isEditing,
                onSaveEdit: isEditing ? _saveEdit : null,
                onCancelEdit: isEditing ? _cancelEdit : null,
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

  bool _isFirstCharGreeting(Character? character) {
    if (widget.isUser || widget.isSystem || widget.messageIndex != 0) return false;
    if (character == null) return false;
    return _greetingsCount(character) > 1 && widget.swipes.length <= 1;
  }

  int _greetingsCount(Character? character) {
    if (character == null) return 0;
    final hasFirst = (character.firstMes ?? '').isNotEmpty ? 1 : 0;
    final alts = character.alternateGreetings.where((g) => g.isNotEmpty).length;
    return hasFirst + alts;
  }

  int _switcherCount(Character? character) =>
      _isFirstCharGreeting(character) ? _greetingsCount(character) : widget.swipes.length;

  int _switcherIndex(Character? character) =>
      _isFirstCharGreeting(character) ? (widget.greetingIndex ?? 0) : widget.swipeId;

  VoidCallback? _onSwitcherLeft(Character? character) {
    if (_isFirstCharGreeting(character)) {
      return () => ref.read(chatProvider(widget.charId).notifier).setGreeting(widget.messageIndex, -1);
    }
    return widget.swipeId > 0
        ? () => ref.read(chatProvider(widget.charId).notifier).setSwipe(widget.messageIndex, widget.swipeId - 1)
        : null;
  }

  VoidCallback? _onSwitcherRight(Character? character) {
    if (_isFirstCharGreeting(character)) {
      return () => ref.read(chatProvider(widget.charId).notifier).setGreeting(widget.messageIndex, 1);
    }
    return widget.swipeId < widget.swipes.length - 1
        ? () => ref.read(chatProvider(widget.charId).notifier).setSwipe(widget.messageIndex, widget.swipeId + 1)
        : null;
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

class _ReasoningBlockState extends State<_ReasoningBlock> with SingleTickerProviderStateMixin {
  bool _collapsed = true;
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 250));
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _collapsed = !_collapsed);
    if (_collapsed) {
      _ctrl.reverse();
    } else {
      _ctrl.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(color: widget.scheme.surfaceContainerLow, borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: _toggle,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
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
          ClipRect(
            child: SizeTransition(
              sizeFactor: _anim,
              axisAlignment: -1.0,
              child: SlideTransition(
                position: Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero).animate(_anim),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  child: Text(
                    widget.reasoning,
                    style: TextStyle(fontSize: 12, color: widget.scheme.onSurfaceVariant, fontStyle: FontStyle.italic),
                  ),
                ),
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

class _EditTextarea extends StatelessWidget {
  final TextEditingController controller;
  final Color textColor;
  final ColorScheme scheme;
  const _EditTextarea({required this.controller, required this.textColor, required this.scheme});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: textColor.withValues(alpha: 0.05),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: TextField(
        controller: controller,
        autofocus: true,
        maxLines: null,
        minLines: 1,
        keyboardType: TextInputType.multiline,
        textInputAction: TextInputAction.newline,
        style: TextStyle(color: textColor, fontSize: 14),
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.all(8),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
        ),
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
  final VoidCallback? onRegenerate;
  final bool isEditing;
  final VoidCallback? onSaveEdit;
  final VoidCallback? onCancelEdit;

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
    this.onRegenerate,
    this.isEditing = false,
    this.onSaveEdit,
    this.onCancelEdit,
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
        // Center: regenerate button
        if (onRegenerate != null)
          InkWell(
            onTap: onRegenerate,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.refresh, size: 14, color: textColor),
                  const SizedBox(width: 4),
                  Text('Regenerate', style: TextStyle(fontSize: 12, color: textColor)),
                ],
              ),
            ),
          ),
        // Right: action button or edit buttons
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: isEditing
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _editCircleBtn(Icons.close, const Color(0xFFFF4444), onCancelEdit),
                      const SizedBox(width: 8),
                      _editCircleBtn(Icons.check, const Color(0xFF4CAF50), onSaveEdit),
                    ],
                  )
                : InkWell(
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

  Widget _editCircleBtn(IconData icon, Color iconColor, VoidCallback? onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh.withValues(alpha: 0.8),
          shape: BoxShape.circle,
          border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
        ),
        child: Icon(icon, size: 16, color: iconColor),
      ),
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

final _htmlTagRegex = RegExp(
  r'<(div|span|p|br|img|a|table|tr|td|th|ul|ol|li|h[1-6]|hr|pre|code|blockquote|style|font|center|b|i|u|s|em|strong|small|sub|sup|mark|details|summary|section|article|header|footer|nav|figure|figcaption|iframe)\b',
  caseSensitive: false,
);

bool _hasHtmlTags(String content) => _htmlTagRegex.hasMatch(content);
