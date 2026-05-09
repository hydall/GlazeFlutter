import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:gpt_markdown/custom_widgets/markdown_config.dart';

import '../../../core/llm/regex_service.dart';
import '../../../core/llm/tokenizer.dart';
import '../../../core/models/character.dart';
import '../../../core/state/active_selection_provider.dart';
import '../../../core/state/character_provider.dart';
import '../../../core/utils/html_to_markdown.dart';
import '../../../features/personas/persona_list_provider.dart';
import '../../../shared/widgets/pencil_animation.dart';
import '../../image_gen/widgets/image_content_renderer.dart';
import '../../settings/app_settings_provider.dart';
import '../chat_provider.dart';
import '../editing_message_provider.dart';
import 'message_actions.dart';

Color? _parseHexColor(String hex) {
  var h = hex.replaceFirst('#', '');
  if (h.length == 3) h = '${h[0]}${h[0]}${h[1]}${h[1]}${h[2]}${h[2]}';
  if (h.length == 4) h = '${h[0]}${h[0]}${h[1]}${h[1]}${h[2]}${h[2]}${h[3]}${h[3]}';
  if (h.length == 6) h = 'ff$h';
  if (h.length != 8) return null;
  final value = int.tryParse(h, radix: 16);
  if (value == null) return null;
  return Color(value);
}

class HtmlColorMd extends InlineMd {
  @override
  RegExp get exp => RegExp(r'==hc:(#[0-9a-fA-F]{3,8})==(.+?)==');

  @override
  InlineSpan span(BuildContext context, String text, GptMarkdownConfig config) {
    final match = exp.firstMatch(text);
    final colorHex = match?[1] ?? '#ffffff';
    final content = match?[2] ?? '';
    final color = _parseHexColor(colorHex) ?? (config.style?.color ?? Colors.white);
    return TextSpan(
      children: MarkdownComponent.generate(context, content, config.copyWith(
        style: (config.style ?? const TextStyle()).copyWith(color: color),
      ), false),
      style: (config.style ?? const TextStyle()).copyWith(color: color),
    );
  }
}

class MarkMd extends InlineMd {
  final Color textColor;

  MarkMd({required this.textColor});

  @override
  RegExp get exp => RegExp(r'==mark==(.+?)==');

  @override
  InlineSpan span(BuildContext context, String text, GptMarkdownConfig config) {
    final match = exp.firstMatch(text);
    final content = match?[1] ?? '';
    final markStyle = (config.style ?? const TextStyle()).copyWith(color: textColor);
    return TextSpan(
      children: MarkdownComponent.generate(context, content, config.copyWith(style: markStyle), false),
      style: markStyle,
    );
  }
}

class ActiveMarkMd extends InlineMd {
  final GlobalKey? activeKey;

  ActiveMarkMd({this.activeKey});

  @override
  RegExp get exp => RegExp(r'==active==(.+?)==');

  @override
  InlineSpan span(BuildContext context, String text, GptMarkdownConfig config) {
    final match = exp.firstMatch(text);
    final content = match?[1] ?? '';
    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: KeyedSubtree(
        key: activeKey,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF44336).withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(4),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
          child: Text.rich(
            TextSpan(
              children: MarkdownComponent.generate(context, content, config, false),
              style: (config.style ?? const TextStyle()).copyWith(color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}

class DetailsSummaryMd extends BlockMd {
  @override
  String get expString => r'<details[^>]*>\s*<summary[^>]*>(.*?)</summary>(.*?)</details>';

  @override
  Widget build(BuildContext context, String text, GptMarkdownConfig config) {
    final fullMatch = RegExp(r'<details[^>]*>\s*<summary[^>]*>(.*?)</summary>(.*?)</details>', dotAll: true).firstMatch(text);
    final summary = fullMatch?[1]?.trim() ?? 'Details';
    final body = fullMatch?[2]?.trim() ?? '';
    return _DetailsBlock(summary: summary, body: body, config: config);
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
    if (content.contains('==hc:')) return content;

    String text = content;
    text = text.replaceAllMapped(
      RegExp(r'(```.*?```|`[^`]*`)|«(?:(?!\n\n)[^»])*»|"(?:(?!\n\n)[^"])*"|\u201C(?:(?!\n\n)[^\u201D])*\u201D|\u2018(?:(?!\n\n)[^\u2019])*\u2019|(?<!\p{L})\x27(?:(?!\n\n)[^\x27])*\x27(?!\p{L})', unicode: true, dotAll: true), 
      (match) {
        if (match[1] != null) return match[1]!;
        return '==mark==${match[0]}==';
      },
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

    final personas = ref.watch(personaListProvider).value ?? [];
    final activePersonaId = ref.watch(activePersonaIdProvider);
    final personaConnections = ref.watch(personaConnectionsProvider);
    final effectivePersona = getEffectivePersona(personas, charId, null, activePersonaId, personaConnections);

    String displayName = isUser ? (effectivePersona?.name ?? 'User') : (character?.name ?? 'Character');
    String avatarLetter = displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';

    FileImage? avatarImage;
    if (isUser) {
      if (effectivePersona?.avatarPath != null && effectivePersona!.avatarPath!.isNotEmpty) {
        avatarImage = FileImage(File(effectivePersona.avatarPath!));
      }
    } else if (character?.avatarPath != null && character!.avatarPath!.isNotEmpty) {
      avatarImage = FileImage(File(character.avatarPath!));
    }

    final textColor = style.textColor;
    final metaColor = style.metaColor;
    final quoteColor = style.quoteColor;
    final effectiveTokens = (tokens != null && tokens > 0)
        ? tokens
        : (isUser && content.isNotEmpty ? estimateTokens(content) : null);

    Widget bubble = Align(
      alignment: style.alignment,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: isStandard ? double.infinity : MediaQuery.of(context).size.width * 0.88),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: EdgeInsets.symmetric(horizontal: isStandard ? 16 : 12, vertical: isStandard ? 8 : 4),
          padding: isStandard ? const EdgeInsets.all(0) : const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _highlighted ? const Color(0xFF7996CE).withValues(alpha: 0.15) : style.bg,
            borderRadius: isStandard ? BorderRadius.zero : BorderRadius.circular(16)
          ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isSystem) ...[
              if (isStandard) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    CircleAvatar(
                      radius: 12,
                      backgroundColor: isUser ? const Color(0xFF7996CE) : const Color(0xFFCCCCCC),
                      backgroundImage: avatarImage,
                      child: avatarImage == null ? Text(avatarLetter, style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold)) : null,
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
              ] else ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    CircleAvatar(
                      radius: 10,
                      backgroundColor: isUser ? const Color(0xFF7996CE) : const Color(0xFFCCCCCC),
                      backgroundImage: avatarImage,
                      child: avatarImage == null ? Text(avatarLetter, style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)) : null,
                    ),
                    const SizedBox(width: 6),
                    Text(displayName, style: TextStyle(fontWeight: FontWeight.w500, fontSize: 12, color: style.metaColor)),
                  ],
                ),
                const SizedBox(height: 4),
              ],
            ],
            if (reasoning != null && reasoning.isNotEmpty && !isEditing)
              _ReasoningBlock(reasoning: reasoning, scheme: scheme),
            if (isEditing)
              _EditTextarea(controller: _editController!, scheme: scheme)
            else if (isTyping && content.isEmpty)
              _TypingIndicator(textColor: textColor, scheme: scheme)
            else if (ImageContentRenderer.hasImageMarkers(displayContent))
              ImageContentRenderer(content: displayContent, textColor: textColor)
            else
              GptMarkdown(
                _highlightPhrases(hasHtmlTags(displayContent) ? htmlToMarkdown(displayContent) : displayContent),
                style: TextStyle(color: textColor),
                components: [
                  CodeBlockMd(),
                  LatexMathMultiLine(),
                  DetailsSummaryMd(),
                  NewLines(),
                  BlockQuote(),
                  TableMd(),
                  HTag(),
                  UnOrderedList(),
                  OrderedList(),
                  RadioButtonMd(),
                  CheckBoxMd(),
                  HrLine(),
                  IndentMd(),
                ],
                inlineComponents: [
                  ATagMd(),
                  ImageMd(),
                  HtmlColorMd(),
                  MarkMd(
                    textColor: quoteColor,
                  ),
                  ActiveMarkMd(activeKey: _activePhraseKey),
                  TableMd(),
                  StrikeMd(),
                  BoldMd(),
                  ItalicMd(),
                  UnderLineMd(),
                  LatexMath(),
                  LatexMathMultiLine(),
                  HighlightedText(),
                  SourceTag(),
                ],
              ),
            if (isStreaming)
              Text('...', style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
            if (!isSystem && !isStreaming) ...[
              const SizedBox(height: 6),
              _MetadataRow(
                genTime: genTime,
                tokens: effectiveTokens,
                metaColor: metaColor,
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
      ),
    );

    Widget bubbleWidget = isHidden ? Opacity(opacity: 0.45, child: bubble) : bubble;

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
  static const _textPrimary = Color(0xFFE1E3E6);
  static const _textSecondary = Color(0xFFB0B8C1);
  static const _vkBlue = Color(0xFF7996CE);
  static const _appBg = Color(0xFF19191A);

  final Color bg;
  final Alignment alignment;
  final Color textColor;
  final Color quoteColor;
  final Color metaColor;

  const _BubbleStyle({
    required this.bg,
    required this.alignment,
    required this.textColor,
    required this.quoteColor,
    required this.metaColor,
  });

  factory _BubbleStyle.resolve({
    required ColorScheme scheme,
    required bool isStandard,
    required bool isUser,
    required bool isSystem,
  }) {
    if (isStandard) {
      return _BubbleStyle(
        bg: Colors.transparent,
        alignment: Alignment.centerLeft,
        textColor: _textPrimary,
        quoteColor: _vkBlue,
        metaColor: _textSecondary,
      );
    }
    if (isUser) {
      return _BubbleStyle(
        bg: _appBg.withValues(alpha: 0.8),
        alignment: Alignment.centerRight,
        textColor: _textPrimary,
        quoteColor: _vkBlue,
        metaColor: _textSecondary,
      );
    }
    if (isSystem) {
      return _BubbleStyle(
        bg: const Color(0xFF1E1E1E).withValues(alpha: 0.8),
        alignment: Alignment.center,
        textColor: _textPrimary,
        quoteColor: _vkBlue,
        metaColor: _textSecondary,
      );
    }
    return _BubbleStyle(
      bg: _vkBlue.withValues(alpha: 0.8),
      alignment: Alignment.centerLeft,
      textColor: _textPrimary,
      quoteColor: _vkBlue,
      metaColor: _textSecondary,
    );
  }
}

class _DetailsBlock extends StatefulWidget {
  final String summary;
  final String body;
  final GptMarkdownConfig config;
  const _DetailsBlock({required this.summary, required this.body, required this.config});

  @override
  State<_DetailsBlock> createState() => _DetailsBlockState();
}

class _DetailsBlockState extends State<_DetailsBlock> with SingleTickerProviderStateMixin {
  bool _expanded = false;
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
    setState(() => _expanded = !_expanded);
    if (_expanded) {
      _ctrl.forward();
    } else {
      _ctrl.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: _toggle,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  AnimatedRotation(
                    turns: _expanded ? 0.25 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(Icons.chevron_right, size: 16, color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      widget.summary,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: scheme.onSurface),
                    ),
                  ),
                ],
              ),
            ),
          ),
          ClipRect(
            child: SizeTransition(
              sizeFactor: _anim,
              axisAlignment: -1.0,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                child: MdWidget(
                  context,
                  widget.body.trim(),
                  true,
                  config: widget.config,
                ),
              ),
            ),
          ),
        ],
      ),
    );
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
      decoration: BoxDecoration(color: const Color(0xFF1E1E1E).withValues(alpha: 0.8), borderRadius: BorderRadius.circular(8)),
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
                  Text('Reasoning', style: TextStyle(fontSize: 11, color: const Color(0xFFB0B8C1), fontWeight: FontWeight.w600)),
                  const Spacer(),
                  AnimatedRotation(
                    turns: _collapsed ? -0.25 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(Icons.expand_more, size: 16, color: const Color(0xFFB0B8C1)),
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
                    style: const TextStyle(fontSize: 12, color: Color(0xFFB0B8C1), fontStyle: FontStyle.italic),
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
  final ColorScheme scheme;
  const _EditTextarea({required this.controller, required this.scheme});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: TextField(
        controller: controller,
        autofocus: true,
        maxLines: null,
        minLines: 1,
        keyboardType: TextInputType.multiline,
        textInputAction: TextInputAction.newline,
        style: TextStyle(color: scheme.onSurface, fontSize: 14),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.all(8),
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
  final Color metaColor;
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
    required this.metaColor,
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
                Text('#${messageIndex + 1}', style: TextStyle(fontSize: 11, color: metaColor.withValues(alpha: 0.55))),
                const SizedBox(width: 8),
              ],
              if (genTime != null) ...[
                Icon(Icons.access_time, size: 12, color: metaColor),
                const SizedBox(width: 4),
                Text(genTime!, style: TextStyle(fontSize: 12, color: metaColor)),
                const SizedBox(width: 12),
              ],
              if (tokens != null && tokens! > 0) ...[
                Icon(Icons.description_outlined, size: 12, color: metaColor),
                const SizedBox(width: 4),
                Text('${tokens}t', style: TextStyle(fontSize: 12, color: metaColor)),
              ],
              if (memoryEntryCount > 0) ...[
                const SizedBox(width: 8),
                Icon(Icons.auto_stories, size: 12, color: metaColor.withValues(alpha: 0.7)),
                const SizedBox(width: 4),
                Text('$memoryEntryCount mem', style: TextStyle(fontSize: 11, color: metaColor.withValues(alpha: 0.7))),
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
                    style: TextStyle(fontSize: 11, color: metaColor.withValues(alpha: 0.8)),
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
                color: const Color(0xFF7996CE).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.refresh, size: 14, color: const Color(0xFF7996CE)),
                  const SizedBox(width: 4),
                  Text('Regenerate', style: TextStyle(fontSize: 12, color: const Color(0xFF7996CE))),
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
                      child: Icon(Icons.menu, size: 16, color: metaColor),
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
          child: Icon(icon, size: 16, color: metaColor.withValues(alpha: onTap != null ? 0.7 : 0.25)),
        ),
      ),
    );
  }
}
