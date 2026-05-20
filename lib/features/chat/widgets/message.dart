import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:gpt_markdown/custom_widgets/markdown_config.dart';

import '../../../core/models/chat_message.dart';
import '../../../core/llm/regex_service.dart';
import '../../../core/llm/tokenizer.dart';
import '../../../core/models/character.dart';
import '../../../core/state/active_selection_provider.dart';
import '../../../core/state/character_provider.dart';
import '../../../core/utils/html_to_markdown.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../features/personas/persona_list_provider.dart';
import '../../../shared/widgets/pencil_animation.dart';
import '../../../shared/widgets/rolling_number.dart';
import '../../../shared/widgets/colored_markdown.dart';import '../../../shared/widgets/image_viewer.dart';
import '../../../shared/widgets/glaze_toast.dart';
import '../../../shared/theme/theme_font_provider.dart';
import '../../../shared/theme/theme_provider.dart';
import '../../../shared/theme/theme_preset.dart';
import '../../image_gen/widgets/image_content_renderer.dart';
import '../../settings/app_settings_provider.dart';
import '../../settings/api_list_provider.dart';
import '../chat_provider.dart';
import '../../presets/preset_list_provider.dart';

import '../editing_message_provider.dart';
import 'message_actions.dart';

class MarkMd extends InlineMd {
  final Color textColor;

  MarkMd({required this.textColor});

  @override
  RegExp get exp => RegExp(r'==mark==(.+?)==');

  @override
  InlineSpan span(BuildContext context, String text, GptMarkdownConfig config) {
    final match = exp.firstMatch(text);
    final content = match?[1] ?? '';
    final markStyle = (config.style ?? const TextStyle()).copyWith(
      color: textColor,
    );
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

final _markdownCache = LruCache<String, String>(maxSize: 200);

final _mdComponents = [
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
];

class LruCache<K, V> {
  final int maxSize;
  final LinkedHashMap<K, V> _map = LinkedHashMap();

  LruCache({required this.maxSize});

  V? get(K key) {
    final v = _map.remove(key);
    if (v != null) _map[key] = v;
    return v;
  }

  void put(K key, V value) {
    _map.remove(key);
    _map[key] = value;
    while (_map.length > maxSize) {
      _map.remove(_map.keys.first);
    }
  }

  void remove(K key) => _map.remove(key);
}

class Message extends ConsumerStatefulWidget {
  final String content;
  final bool isUser;
  final bool isSystem;
  final bool isStreaming;
  final bool isTyping;
  final String? reasoning;
  final bool isAllReasoning;
  final String? genTime;
  final int? tokens;
  final bool isHidden;
  final bool isError;
  final int messageIndex;
  final int totalMessages;
  final bool isLast;
  final bool isGenerating;
  final DateTime? generationStartTime;
  final String charId;
  final List<String> swipes;
  final int swipeId;
  final int? greetingIndex;
  final Map<String, dynamic> memoryCoverage;
  final List<TriggeredEntry> triggeredLorebooks;
  final List<TriggeredEntry> triggeredMemories;
  final bool isSearchMatch;
  final String searchQuery;
  final int activeMatchIndex;
  /// Callback fired when a left-swipe on the last variant of the last message
  /// should trigger regeneration (mirrors Vue's swipe-to-regenerate).
  final VoidCallback? onSwipeRegenerate;
  final String? time;

  const Message({
    super.key,
    required this.content,
    required this.isUser,
    this.isSystem = false,
    this.isStreaming = false,
    this.isTyping = false,
    this.reasoning,
    this.isAllReasoning = false,
    this.genTime,
    this.tokens,
    this.isHidden = false,
    this.isError = false,
    required this.messageIndex,
    required this.totalMessages,
    required this.isLast,
    required this.isGenerating,
    this.generationStartTime,
    required this.charId,
    this.swipes = const [],
    this.swipeId = 0,
    this.greetingIndex,
    this.memoryCoverage = const {},
    this.triggeredLorebooks = const [],
    this.triggeredMemories = const [],
    this.isSearchMatch = false,
    this.searchQuery = '',
    this.activeMatchIndex = -1,
    this.onSwipeRegenerate,
    this.time,
  });

  @override
  ConsumerState<Message> createState() => _MessageState();
}

class _MessageState extends ConsumerState<Message>
    with AutomaticKeepAliveClientMixin, TickerProviderStateMixin {
  TextEditingController? _editController;
  bool _highlighted = false;
  final GlobalKey _activePhraseKey = GlobalKey();

  // --- Swipe gesture state ---
  double _swipeDx = 0;
  bool _swipeLocked = false; // true once vertical scroll wins
  bool _swipeActive = false; // true once horizontal drag wins
  late final AnimationController _swipeResetCtrl;
  double _swipeResetFrom = 0;

  // --- Animation states ---
  late final AnimationController _appearanceCtrl;
  late final Animation<Offset> _appearanceSlide;

  _SlideDirection _slideDir = _SlideDirection.none;
  int _lastSwipeId = 0;
  int _lastGreetingIndex = 0;

  Timer? _genTimer;
  double _elapsedGenSeconds = 0.0;

  String get _cacheKey => '${widget.messageIndex}:${widget.content}:${widget.searchQuery}:${widget.activeMatchIndex}';

  String? _cachedContent;
  String? _cachedDisplayContent;
  int? _cachedRegexHash;
  String? _cachedAvatarPath;
  FileImage? _cachedAvatarImage;

  @override
  void initState() {
    super.initState();
    _lastSwipeId = widget.swipeId;
    _lastGreetingIndex = widget.greetingIndex ?? 0;

    _swipeResetCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    )..addListener(() {
        setState(() {
          _swipeDx = _swipeResetFrom * (1 - _swipeResetCtrl.value);
        });
      });

    _appearanceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _appearanceSlide = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _appearanceCtrl, curve: Curves.easeOut));

    _appearanceCtrl.forward();

    if (widget.isSearchMatch) {
      _triggerHighlight();
    }

    _updateGenTimer();
  }

  void _updateGenTimer() {
    if (widget.isGenerating && widget.generationStartTime != null && (widget.isStreaming || widget.isTyping)) {
      if (_genTimer == null) {
        _genTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
          if (!mounted) {
            timer.cancel();
            return;
          }
          setState(() {
            _elapsedGenSeconds = DateTime.now().difference(widget.generationStartTime!).inMilliseconds / 1000.0;
          });
        });
      }
    } else {
      _genTimer?.cancel();
      _genTimer = null;
    }
  }

  @override
  void didUpdateWidget(Message oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.content != oldWidget.content ||
        widget.searchQuery != oldWidget.searchQuery ||
        widget.activeMatchIndex != oldWidget.activeMatchIndex) {
      _markdownCache.remove(_cacheKey);
    }

    if (widget.swipeId != oldWidget.swipeId) {
      setState(() {
        _slideDir = widget.swipeId > oldWidget.swipeId ? _SlideDirection.next : _SlideDirection.prev;
        _lastSwipeId = widget.swipeId;
      });
    } else if (widget.greetingIndex != oldWidget.greetingIndex) {
      setState(() {
        final oldIdx = oldWidget.greetingIndex ?? 0;
        final newIdx = widget.greetingIndex ?? 0;
        _slideDir = newIdx > oldIdx ? _SlideDirection.next : _SlideDirection.prev;
        _lastGreetingIndex = newIdx;
      });
    }

    if ((widget.isSearchMatch && !oldWidget.isSearchMatch) ||
        (widget.activeMatchIndex != -1 && widget.activeMatchIndex != oldWidget.activeMatchIndex)) {
      _triggerHighlight();
    }

    _updateGenTimer();
  }

  static final _quoteRegex = RegExp(
    r'(```.*?```|`[^`]*`)|«(?:(?!\n\n)[^»])*»|"(?:(?!\n\n)[^"])*"|\u201C(?:(?!\n\n)[^\u201D])*\u201D|\u2018(?:(?!\n\n)[^\u2019])*\u2019|(?<!\p{L})\x27(?:(?!\n\n)[^\x27])*\x27(?!\p{L})',
    unicode: true, dotAll: true,
  );
  static final _styledSegmentRegex = RegExp(
    r'(==(?:hc:#[0-9a-fA-F]{3,8}|glow:#[0-9a-fA-F]{3,8},\d+|cg:#[0-9a-fA-F]{3,8},#[0-9a-fA-F]{3,8},\d+|grad:#[0-9a-fA-F]{3,8}(?:,#[0-9a-fA-F]{3,8})+|bg:#[0-9a-fA-F]{3,8})==.+?=='
    r'|\*\*[^*]+?\*\*'
    r'|(?<!\*)\*[^*]+?\*(?!\*)'
    r'|__[^_]+?__'
    r'|(?<!\w)_[^_]+?_(?!\w)'
    r'|~~[^~]+?~~'
    r')',
    dotAll: true,
  );

  String _applyQuoteHighlight(String plain) {
    return plain.replaceAllMapped(_quoteRegex, (match) {
      if (match[1] != null) return match[1]!;
      return '==mark==${match[0]}==';
    });
  }

  String _highlightPhrases(String content) {
    final styledMatches = _styledSegmentRegex.allMatches(content).toList();

    final quoteSpans = <({int start, int end})>[];
    for (final m in _quoteRegex.allMatches(content)) {
      if (m[1] == null) {
        quoteSpans.add((start: m.start, end: m.end));
      }
    }

    final protectedRanges = <({int start, int end, String text})>[];
    for (final sm in styledMatches) {
      final insideQuote = quoteSpans.any(
        (q) => sm.start >= q.start && sm.end <= q.end,
      );
      if (!insideQuote) {
        protectedRanges.add((start: sm.start, end: sm.end, text: sm[0]!));
      }
    }
    protectedRanges.sort((a, b) => a.start.compareTo(b.start));

    final buffer = StringBuffer();
    int cursor = 0;
    for (final range in protectedRanges) {
      if (range.start > cursor) {
        buffer.write(_applyQuoteHighlight(content.substring(cursor, range.start)));
      }
      buffer.write(range.text);
      cursor = range.end;
    }
    if (cursor < content.length) {
      buffer.write(_applyQuoteHighlight(content.substring(cursor)));
    }
    String text = buffer.toString();

    if (widget.searchQuery.isEmpty || !widget.isSearchMatch) return text;
    final lowerContent = text.toLowerCase();
    final lowerQuery = widget.searchQuery.toLowerCase();
    final searchBuffer = StringBuffer();
    int startIndex = 0;
    int currentMatchIndex = 0;

    while (true) {
      final idx = lowerContent.indexOf(lowerQuery, startIndex);
      if (idx == -1) {
        searchBuffer.write(text.substring(startIndex));
        break;
      }
      searchBuffer.write(text.substring(startIndex, idx));
      final originalText = text.substring(idx, idx + lowerQuery.length);
      if (currentMatchIndex == widget.activeMatchIndex) {
        searchBuffer.write('==active==$originalText==');
      } else {
        searchBuffer.write('==mark==$originalText==');
      }
      currentMatchIndex++;
      startIndex = idx + lowerQuery.length;
    }
    return searchBuffer.toString();
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
    _genTimer?.cancel();
    _editController?.dispose();
    _swipeResetCtrl.dispose();
    _appearanceCtrl.dispose();
    super.dispose();
  }

  void _ensureEditController() {
    _editController ??= TextEditingController(
      text: _editTextWithReasoning(),
    );
  }

  String _editTextWithReasoning() {
    final reasoning = widget.reasoning;
    if (reasoning == null || reasoning.isEmpty) return widget.content;
    final tags = _reasoningTags();
    return '${tags.$1}$reasoning${tags.$2}\n${widget.content}'.trim();
  }

  (String, String) _reasoningTags() {
    final charId = widget.charId;
    final activePresetId = ref.read(activePresetIdProvider);
    final presetsAsync = ref.read(presetListProvider);
    final preset = presetsAsync.valueOrNull
        ?.where((p) => p.id == activePresetId)
        .firstOrNull;
    if (preset?.reasoningStart != null && preset?.reasoningEnd != null) {
      return (preset!.reasoningStart!, preset.reasoningEnd!);
    }
    final apiConfig = ref.read(activeApiConfigProvider);
    if (apiConfig?.reasoningTagStart != null && apiConfig?.reasoningTagEnd != null) {
      return (apiConfig!.reasoningTagStart!, apiConfig.reasoningTagEnd!);
    }
    return ('<think' + '>' , '</think' + '>' );
  }

  void _disposeEditController() {
    _editController?.dispose();
    _editController = null;
  }

  void _saveEdit() {
    final text = _editController?.text.trim() ?? '';
    if (text.isNotEmpty) {
      final tags = _reasoningTags();
      ref.read(chatProvider(widget.charId).notifier).editMessage(
            widget.messageIndex,
            text,
            tagStart: tags.$1,
            tagEnd: tags.$2,
          );
    }
    ref.read(editingMessageIndexProvider(widget.charId).notifier).state = null;
  }

  void _cancelEdit() {
    ref.read(editingMessageIndexProvider(widget.charId).notifier).state = null;
  }

  void _showTriggeredSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _TriggeredItemsSheet(
        lorebooks: widget.triggeredLorebooks,
        memories: widget.triggeredMemories,
      ),
    );
  }

  @override
  @override
  bool get wantKeepAlive => widget.messageIndex >= widget.totalMessages - 50;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final content = widget.content;
    final isUser = widget.isUser;
    final isSystem = widget.isSystem;
    final isStreaming = widget.isStreaming;
    final isTyping = widget.isTyping;
    final reasoning = widget.reasoning;
    final genTime = widget.genTime ?? (widget.generationStartTime != null && _elapsedGenSeconds > 0.0 ? '${_elapsedGenSeconds.toStringAsFixed(1)}s' : null);
    final tokens = widget.tokens;
    final isHidden = widget.isHidden;
    final isError = widget.isError;
    final messageIndex = widget.messageIndex;
    final totalMessages = widget.totalMessages;
    final isLast = widget.isLast;
    final isGenerating = widget.isGenerating;
    final charId = widget.charId;
    final time = widget.time;

    final scheme = Theme.of(context).colorScheme;
    final appSettings = ref.watch(appSettingsProvider).value;
    final isStandard = (appSettings?.chatLayout ?? 'default') == 'default';

    final isEditing = ref.watch(editingMessageIndexProvider(charId).select((v) => v == messageIndex)) && !isSystem && !isStreaming && !isTyping;
    if (isEditing) {
      _ensureEditController();
    } else if (_editController != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && ref.read(editingMessageIndexProvider(charId)) != widget.messageIndex) {
          _disposeEditController();
        }
      });
    }

    final character = ref.watch(characterByIdProvider(charId));

    final regexScripts = ref.watch(activeRegexesProvider).value ?? [];
    final regexHash = regexScripts.isEmpty ? 0 : Object.hashAll(regexScripts.map((r) => r.id));
    String displayContent;
    if (_cachedContent == content && _cachedRegexHash == regexHash) {
      displayContent = _cachedDisplayContent!;
    } else {
      final placement = isUser ? 1 : 2;
      final depth = totalMessages > 0 ? totalMessages - 1 - messageIndex : null;
      final regexCtx = RegexApplyContext(
        char: character,
        persona: null,
        depth: depth,
        totalMessages: totalMessages,
      );
      displayContent = regexScripts.isEmpty
          ? content
          : applyRegexes(content, placement, 1, regexScripts, regexCtx);
      _cachedContent = content;
      _cachedDisplayContent = displayContent;
      _cachedRegexHash = regexHash;
    }

    final style = _BubbleStyle.resolve(
      context: context,
      isStandard: isStandard,
      isUser: isUser,
      isSystem: isSystem,
      preset: ref.watch(themeProvider).activePreset,
    );

    final effectivePersona = ref.watch(effectivePersonaForChatProvider(charId));
    final fontStyle = ref.watch(chatFontStyleProvider);

    String displayName = isUser ? (effectivePersona?.name ?? 'User') : (character?.name ?? 'Character');
    String avatarLetter = displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';

    final avatarPath = isUser
        ? (effectivePersona?.avatarPath?.isNotEmpty == true ? effectivePersona!.avatarPath : null)
        : (character?.avatarPath?.isNotEmpty == true ? character!.avatarPath : null);
    FileImage? avatarImage;
    if (avatarPath != _cachedAvatarPath) {
      _cachedAvatarPath = avatarPath;
      _cachedAvatarImage = avatarPath != null ? FileImage(File(avatarPath)) : null;
    }
    avatarImage = _cachedAvatarImage;

    final textColor = style.textColor;
    final metaColor = style.metaColor;
    final quoteColor = style.quoteColor;
    final effectiveTokens = (tokens != null && tokens > 0)
        ? tokens
        : (isUser && content.isNotEmpty ? estimateTokens(content) : null);

    final container = AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: EdgeInsets.symmetric(horizontal: isStandard ? 16 : 12, vertical: isStandard ? 8 : 4),
      padding: isStandard ? const EdgeInsets.all(0) : const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _highlighted
            ? context.cs.primary.withValues(alpha: 0.15)
            : style.bg == Colors.transparent
                ? null
                : style.bg.withValues(alpha: style.elementOpacity),
        borderRadius: isStandard ? BorderRadius.zero : BorderRadius.circular(16),
        border: isStandard || style.borderWidth <= 0
            ? null
            : Border.all(
                color: style.borderColor.withValues(alpha: style.borderOpacity),
                width: style.borderWidth,
              ),
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        transitionBuilder: (Widget child, Animation<double> animation) {
          if (_slideDir == _SlideDirection.none) {
            return FadeTransition(opacity: animation, child: child);
          }

          final isOut = child.key != ValueKey('${widget.swipeId}-${widget.greetingIndex}');
          final offset = _slideDir == _SlideDirection.next
              ? (isOut ? const Offset(-0.1, 0) : const Offset(0.1, 0))
              : (isOut ? const Offset(0.1, 0) : const Offset(-0.1, 0));

          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: offset,
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          );
        },
        child: KeyedSubtree(
          key: ValueKey('${widget.swipeId}-${widget.greetingIndex}'),
          child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
            if (!isSystem) ...[
              if (isStandard) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    GestureDetector(
                      onTap: () {
                        if (avatarImage != null) {
                          ImageViewer.show(context, imageProvider: avatarImage, description: displayName);
                        }
                      },
                      child: CircleAvatar(
                        radius: 12,
                        backgroundColor: isUser ? context.cs.primary : const Color(0xFFCCCCCC),
                        backgroundImage: avatarImage,
                        child: avatarImage == null ? Text(avatarLetter, style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold)) : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(displayName, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: scheme.onSurfaceVariant)),
                    if (messageIndex >= 0) ...[
                      const SizedBox(width: 6),
                      Text('#${messageIndex + 1}', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant.withValues(alpha: 0.55))),
                    ],
                    const Spacer(),
                    if (isHidden) ...[
                      Icon(Icons.visibility_off, size: 14, color: scheme.onSurfaceVariant.withValues(alpha: 0.5)),
                      const SizedBox(width: 4),
                    ],
                    if (time != null)
                      Text(time, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant.withValues(alpha: 0.55))),
                  ],
                ),
                const SizedBox(height: 8),
              ] else ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    GestureDetector(
                      onTap: () {
                        if (avatarImage != null) {
                          ImageViewer.show(context, imageProvider: avatarImage, description: displayName);
                        }
                      },
                      child: CircleAvatar(
                        radius: 10,
                        backgroundColor: isUser ? context.cs.primary : const Color(0xFFCCCCCC),
                        backgroundImage: avatarImage,
                        child: avatarImage == null ? Text(avatarLetter, style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)) : null,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(displayName, style: TextStyle(fontWeight: FontWeight.w500, fontSize: 12, color: style.metaColor)),
                    const Spacer(),
                    if (isHidden) ...[
                      Icon(Icons.visibility_off, size: 12, color: style.metaColor.withValues(alpha: 0.7)),
                      const SizedBox(width: 4),
                    ],
                    if (time != null)
                      Text(time, style: TextStyle(fontSize: 11, color: style.metaColor.withValues(alpha: 0.8))),
                  ],
                ),
                const SizedBox(height: 4),
              ],
            ],
            if (reasoning != null && reasoning.isNotEmpty)
              _ReasoningBlock(reasoning: reasoning, scheme: scheme, initiallyExpanded: widget.isAllReasoning),
            if (isEditing)
              _EditTextarea(controller: _editController!, scheme: scheme)
            else if (isTyping && content.isEmpty)
              _TypingIndicator(textColor: textColor, scheme: scheme)
            else if (isError)
              _ErrorWindow(text: displayContent)
            else ...[
              () {
                var mdContent = _markdownCache.get(_cacheKey);
                if (mdContent == null) {
                  mdContent = _highlightPhrases(
                    ensureLineBreaks(hasHtmlTags(displayContent) ? htmlToMarkdown(displayContent) : displayContent),
                  );
                  _markdownCache.put(_cacheKey, mdContent);
                }
                if (ImageContentRenderer.hasImageMarkers(mdContent)) {
                  return ImageContentRenderer(
                    content: mdContent,
                    textColor: textColor,
                    onRegenerate: () {
                      final notifier = ref.read(chatProvider(charId).notifier);
                      if (notifier.isGeneratingImage) {
                        notifier.abortImageGeneration();
                      } else {
                        notifier.retryImageGeneration();
                      }
                    },
                  );
                }
                return GptMarkdown(
                  mdContent,
                  style: TextStyle(
                    color: textColor,
                    fontSize: fontStyle.fontSize,
                    letterSpacing: fontStyle.letterSpacing,
                    fontFamily: fontStyle.fontFamily,
                  ),
                  imageBuilder: (context, url) {
                    if (url.startsWith('http://') || url.startsWith('https://')) {
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(url, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                      );
                    }
                    if (url.startsWith('data:')) {
                      final commaIdx = url.indexOf(',');
                      if (commaIdx > 0) {
                        try {
                          final bytes = Uri.parse(url).data!.contentAsBytes();
                          return ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.memory(bytes, fit: BoxFit.contain),
                          );
                        } catch (_) {}
                      }
                    }
                    final file = File(url);
                    if (file.existsSync()) {
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(file, fit: BoxFit.contain),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                  components: _mdComponents,
                  inlineComponents: [
                    ATagMd(),
                    ImageMd(),
                    HtmlColorMd(),
                    GlowTextMd(),
                    ColorGlowTextMd(),
                    GradientTextMd(),
                    BackgroundTextMd(),
                    MarkMd(
                      textColor: quoteColor,
                    ),
                    ActiveMarkMd(activeKey: _activePhraseKey),
                    TableMd(),
                    StrikeMd(),
                    ColoredBoldMd(color: style.italicColor),
                    ColoredUnderscoreBoldMd(color: style.italicColor),
                    ColoredItalicMd(color: style.italicColor),
                    ColoredUnderscoreItalicMd(color: style.italicColor),
                    UnderLineMd(),
                    LatexMath(),
                    LatexMathMultiLine(),
                    HighlightedText(),
                    SourceTag(),
                  ],
                );
              }(),
            ],
            if (isStreaming)
              Text('...', style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
            if (!isSystem) ...[
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
                triggeredLorebooks: widget.triggeredLorebooks,
                triggeredMemories: widget.triggeredMemories,
                onTriggeredTap: () => _showTriggeredSheet(context),
                onRegenerate: (!isEditing && ((isUser && isLast) || isError) && !isGenerating)
                    ? () => ref.read(chatProvider(charId).notifier).regenerateLastAssistant()
                    : null,
                isEditing: isEditing,
                onSaveEdit: isEditing ? _saveEdit : null,
                onCancelEdit: isEditing ? _cancelEdit : null,
                hideActions: isStreaming || isTyping,
              ),
            ],
          ],
        ),
      ),
    ),
    );

    Widget decorated = container;
    if (!isStandard && style.elementBlur > 0) {
      decorated = ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: container,
      );
    }

    Widget bubble = Align(
      alignment: style.alignment,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: isStandard ? double.infinity : MediaQuery.of(context).size.width * 0.88),
        child: SlideTransition(
          position: _appearanceSlide,
          child: decorated,
        ),
      ),
    );

    Widget bubbleWidget = isHidden ? Opacity(opacity: 0.45, child: bubble) : bubble;

    if (isSystem || isStreaming) return bubbleWidget;

    // Wrap in swipe handler for char messages (variant switching + regeneration)
    final canSwipe = !isUser && !isSystem && !isStreaming && !isEditing && !isGenerating;
    if (canSwipe) {
      bubbleWidget = _SwipeableMessage(
        dx: _swipeDx,
        child: bubbleWidget,
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onLongPress: () => showMessageContextMenu(
        context: context, ref: ref, charId: charId, content: content,
        messageIndex: messageIndex, isUser: isUser, isTyping: isTyping,
        isError: isError, isLast: isLast, isGenerating: isGenerating, isHidden: isHidden,
      ),
      onHorizontalDragStart: canSwipe ? _onSwipeDragStart : null,
      onHorizontalDragUpdate: canSwipe ? _onSwipeDragUpdate : null,
      onHorizontalDragEnd: canSwipe ? _onSwipeDragEnd : null,
      child: bubbleWidget,
    );
  }

  // ───── Swipe gesture handlers (mirrors useMessageSwipe.js) ─────

  void _onSwipeDragStart(DragStartDetails _) {
    _swipeLocked = false;
    _swipeActive = false;
    _swipeResetCtrl.stop();
    setState(() => _swipeDx = 0);
  }

  void _onSwipeDragUpdate(DragUpdateDetails details) {
    if (_swipeLocked) return;
    _swipeActive = true;

    final character = (ref.read(charactersProvider).value ?? [])
        .where((c) => c.id == widget.charId)
        .firstOrNull;

    double dx = _swipeDx + details.delta.dx;

    // Clamp: can't drag right beyond first variant,
    // can't drag left beyond last variant (unless last msg → regenerate)
    final isFirstGreeting = _isFirstCharGreeting(character);
    if (isFirstGreeting) {
      // greeting switcher – always allow both directions
    } else {
      if (dx > 0 && widget.swipeId <= 0) {
        dx = dx * 0.3; // rubber-band effect
      }
      if (dx < 0 && widget.swipeId >= widget.swipes.length - 1 && !widget.isLast) {
        dx = dx * 0.3; // rubber-band effect
      }
    }

    setState(() => _swipeDx = dx);
  }

  void _onSwipeDragEnd(DragEndDetails _) {
    if (_swipeLocked || !_swipeActive) {
      _resetSwipe();
      return;
    }

    const threshold = 100.0;
    final character = (ref.read(charactersProvider).value ?? [])
        .where((c) => c.id == widget.charId)
        .firstOrNull;
    final isFirstGreeting = _isFirstCharGreeting(character);

    if (isFirstGreeting) {
      // Greeting switcher
      if (_swipeDx < -threshold) {
        _animateSwipeAndAct(() {
          ref.read(chatProvider(widget.charId).notifier)
              .setGreeting(widget.messageIndex, 1);
        });
      } else if (_swipeDx > threshold) {
        _animateSwipeAndAct(() {
          ref.read(chatProvider(widget.charId).notifier)
              .setGreeting(widget.messageIndex, -1);
        });
      } else {
        _resetSwipe();
      }
      return;
    }

    // Swipe variants
    if (_swipeDx < -threshold) {
      // Swipe left → next variant
      if (widget.swipeId < widget.swipes.length - 1) {
        _animateSwipeAndAct(() {
          ref.read(chatProvider(widget.charId).notifier)
              .setSwipe(widget.messageIndex, widget.swipeId + 1);
        });
      } else if (widget.isLast) {
        // Last variant of last message → trigger regeneration
        _animateSwipeBounce(() {
          ref.read(chatProvider(widget.charId).notifier)
              .regenerateLastAssistant();
        });
      } else {
        _resetSwipe();
      }
    } else if (_swipeDx > threshold) {
      // Swipe right → previous variant
      if (widget.swipeId > 0) {
        _animateSwipeAndAct(() {
          ref.read(chatProvider(widget.charId).notifier)
              .setSwipe(widget.messageIndex, widget.swipeId - 1);
        });
      } else {
        _resetSwipe();
      }
    } else {
      _resetSwipe();
    }
  }

  /// Smoothly reset dx to 0.
  void _resetSwipe() {
    _swipeResetFrom = _swipeDx;
    _swipeResetCtrl.forward(from: 0);
  }

  /// Animate the content off-screen, fire the action, then reset.
  void _animateSwipeAndAct(VoidCallback action) {
    action();
    setState(() => _swipeDx = 0);
  }

  /// Small "bounce" feedback for regeneration: nudge left then reset.
  void _animateSwipeBounce(VoidCallback action) {
    setState(() => _swipeDx = -20);
    Future.delayed(const Duration(milliseconds: 100), () {
      if (!mounted) return;
      action();
      _swipeResetFrom = -20;
      _swipeResetCtrl.forward(from: 0);
    });
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
    if (widget.swipeId < widget.swipes.length - 1) {
      return () => ref.read(chatProvider(widget.charId).notifier).setSwipe(widget.messageIndex, widget.swipeId + 1);
    }
    if (widget.isLast && !widget.isUser && !widget.isSystem && widget.swipes.isNotEmpty) {
      return () => ref.read(chatProvider(widget.charId).notifier).regenerateLastAssistant();
    }
    return null;
  }
}

enum _SlideDirection { next, prev, none }

/// Wraps the message bubble and applies a horizontal translation
/// for the swipe-to-switch-variant gesture.
class _SwipeableMessage extends StatelessWidget {
  final double dx;
  final Widget child;
  const _SwipeableMessage({required this.dx, required this.child});

  @override
  Widget build(BuildContext context) {
    if (dx == 0) return child;
    return Transform.translate(
      offset: Offset(dx, 0),
      child: Opacity(
        opacity: (1 - (dx.abs() / 300).clamp(0, 0.6)),
        child: child,
      ),
    );
  }
}

class _BubbleStyle {
  final Color bg;
  final Alignment alignment;
  final Color textColor;
  final Color quoteColor;
  final Color metaColor;
  final Color? italicColor;
  final double elementOpacity;
  final double elementBlur;
  final double borderWidth;
  final Color borderColor;
  final double borderOpacity;

  const _BubbleStyle({
    required this.bg,
    required this.alignment,
    required this.textColor,
    required this.quoteColor,
    required this.metaColor,
    this.italicColor,
    this.elementOpacity = 1.0,
    this.elementBlur = 0,
    this.borderWidth = 0,
    this.borderColor = Colors.transparent,
    this.borderOpacity = 1.0,
  });

  factory _BubbleStyle.resolve({
    required BuildContext context,
    required bool isStandard,
    required bool isUser,
    required bool isSystem,
    required ThemePreset preset,
  }) {
    final colors = context.colors;
    final cs = context.cs;
    final elOp = isStandard
        ? 1.0
        : preset.elementBlur > 0
            ? (preset.elementOpacity + 0.4).clamp(0.75, 0.95)
            : preset.elementOpacity.clamp(0.7, 1.0);
    final elBlur = isStandard ? 0.0 : preset.elementBlur;
    final bw = isStandard ? 0.0 : preset.borderWidth;
    final bc = preset.borderParsed ?? cs.outline;

    if (isStandard) {
      // Standard layout has no bubble background — text color must be readable on
      // the app background, not on the bubble. Mirror Glaze JS behaviour: text = inherit
      // (cs.onSurface), quote = vk-blue, italic = gray. Preset bubble text colors are
      // intentionally ignored here — they're calibrated for the bubble background only.
      return _BubbleStyle(
        bg: Colors.transparent,
        alignment: Alignment.centerLeft,
        textColor: cs.onSurface,
        quoteColor: isUser ? (colors.userQuote ?? cs.primary) : (colors.charQuote ?? cs.primary),
        metaColor: cs.onSurfaceVariant,
        italicColor: isUser ? colors.userItalic : colors.charItalic,
      );
    }
    if (isUser) {
      return _BubbleStyle(
        bg: colors.userBubble,
        alignment: Alignment.centerRight,
        textColor: colors.userText ?? cs.onSurface,
        quoteColor: colors.userQuote ?? cs.primary,
        metaColor: colors.userText?.withValues(alpha: 0.6) ?? cs.onSurfaceVariant,
        italicColor: colors.userItalic,
        elementOpacity: elOp,
        elementBlur: elBlur,
        borderWidth: bw,
        borderColor: bc,
        borderOpacity: preset.borderOpacity,
      );
    }
    if (isSystem) {
      return _BubbleStyle(
        bg: colors.charBubble,
        alignment: Alignment.center,
        textColor: colors.charText ?? cs.onSurface,
        quoteColor: colors.charQuote ?? cs.primary,
        metaColor: colors.charText?.withValues(alpha: 0.6) ?? cs.onSurfaceVariant,
        italicColor: colors.charItalic,
        elementOpacity: elOp,
        elementBlur: elBlur,
        borderWidth: bw,
        borderColor: bc,
        borderOpacity: preset.borderOpacity,
      );
    }
    return _BubbleStyle(
      bg: colors.charBubble,
      alignment: Alignment.centerLeft,
      textColor: colors.charText ?? cs.onSurface,
      quoteColor: colors.charQuote ?? cs.primary,
      metaColor: colors.charText?.withValues(alpha: 0.6) ?? cs.onSurfaceVariant,
      italicColor: colors.charItalic,
      elementOpacity: elOp,
      elementBlur: elBlur,
      borderWidth: bw,
      borderColor: bc,
      borderOpacity: preset.borderOpacity,
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
  final bool initiallyExpanded;
  const _ReasoningBlock({required this.reasoning, required this.scheme, this.initiallyExpanded = false});

  @override
  State<_ReasoningBlock> createState() => _ReasoningBlockState();
}

class _ReasoningBlockState extends State<_ReasoningBlock> with SingleTickerProviderStateMixin {
  late bool _collapsed;
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _collapsed = !widget.initiallyExpanded;
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 250));
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
    if (!_collapsed) _ctrl.value = 1.0;
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
      decoration: BoxDecoration(color: context.colors.charBubble.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(8)),
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
                  Text('Reasoning', style: TextStyle(fontSize: 11, color: context.cs.onSurfaceVariant, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  AnimatedRotation(
                    turns: _collapsed ? -0.25 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(Icons.expand_more, size: 16, color: context.cs.onSurfaceVariant),
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
                    style: TextStyle(fontSize: 12, color: context.cs.onSurfaceVariant, fontStyle: FontStyle.italic),
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

class _EditTextarea extends StatefulWidget {
  final TextEditingController controller;
  final ColorScheme scheme;
  const _EditTextarea({required this.controller, required this.scheme});

  @override
  State<_EditTextarea> createState() => _EditTextareaState();
}

class _EditTextareaState extends State<_EditTextarea> {
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: widget.scheme.surface,
        border: Border.all(color: widget.scheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: TextField(
        controller: widget.controller,
        focusNode: _focusNode,
        autofocus: true,
        maxLines: null,
        minLines: 1,
        keyboardType: TextInputType.multiline,
        textInputAction: TextInputAction.newline,
        style: TextStyle(color: widget.scheme.onSurface, fontSize: 14),
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
  final List<TriggeredEntry> triggeredLorebooks;
  final List<TriggeredEntry> triggeredMemories;
  final VoidCallback? onTriggeredTap;
  final VoidCallback? onRegenerate;
  final bool isEditing;
  final VoidCallback? onSaveEdit;
  final VoidCallback? onCancelEdit;
  final bool hideActions;

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
    this.triggeredLorebooks = const [],
    this.triggeredMemories = const [],
    this.onTriggeredTap,
    this.onRegenerate,
    this.isEditing = false,
    this.onSaveEdit,
    this.onCancelEdit,
    this.hideActions = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    if (!isStandard && messageIndex >= 0) ...[
                      Text('#${messageIndex + 1}', style: TextStyle(fontSize: 11, color: metaColor.withValues(alpha: 0.55))),
                      const SizedBox(width: 8),
                    ],
                    if (genTime != null) ...[
                      Icon(Icons.access_time, size: 12, color: metaColor),
                      const SizedBox(width: 4),
                      RollingNumber(value: genTime!, style: TextStyle(fontSize: 12, color: metaColor)),
                      const SizedBox(width: 12),
                    ],
                    if (tokens != null && tokens! > 0) ...[
                      Icon(Icons.description_outlined, size: 12, color: metaColor),
                      const SizedBox(width: 4),
                      Text('${tokens}t', style: TextStyle(fontSize: 12, color: metaColor)),
                    ],
                    if (triggeredLorebooks.isNotEmpty || triggeredMemories.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: onTriggeredTap,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHighest.withValues(alpha: 0.8),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.auto_awesome, size: 12, color: metaColor.withValues(alpha: 0.8)),
                              const SizedBox(width: 4),
                              Text('${triggeredLorebooks.length + triggeredMemories.length}',
                                  style: TextStyle(fontSize: 11, color: metaColor.withValues(alpha: 0.8))),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (!hideActions)
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
      ),
      if (!hideActions && (swipeCount > 1 || onRegenerate != null))
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
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
            if (onRegenerate != null) ...[
              if (swipeCount > 1) const SizedBox(width: 8),
              InkWell(
                onTap: onRegenerate,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: context.cs.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.refresh, size: 14, color: context.cs.primary),
                      const SizedBox(width: 4),
                      Text('Regenerate', style: TextStyle(fontSize: 12, color: context.cs.primary)),
                    ],
                  ),
                ),
              ),
            ],
          ],
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

class _ErrorWindow extends StatelessWidget {
  final String text;
  const _ErrorWindow({required this.text});

  @override
  Widget build(BuildContext context) {
    final errorColor = Theme.of(context).colorScheme.error;
    return Container(
      decoration: BoxDecoration(
        color: errorColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: errorColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 4, 4),
            child: Row(
              children: [
                Icon(Icons.error_outline, size: 14, color: errorColor),
                const SizedBox(width: 6),
                Text(
                  'ERROR',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: errorColor,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                InkWell(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: text));
                    GlazeToast.show(context, 'Copied to clipboard', duration: 1500);
                  },
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(Icons.copy, size: 14, color: errorColor.withValues(alpha: 0.7)),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            child: SelectableText(
              text,
              style: TextStyle(
                fontSize: 12,
                color: errorColor.withValues(alpha: 0.9),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TriggeredItemsSheet extends StatelessWidget {
  final List<TriggeredEntry> lorebooks;
  final List<TriggeredEntry> memories;

  const _TriggeredItemsSheet({
    required this.lorebooks,
    required this.memories,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = context.cs;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 32, height: 4,
              decoration: BoxDecoration(
                color: scheme.outlineVariant.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text('Triggered Items', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: scheme.onSurface)),
          const SizedBox(height: 12),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (lorebooks.isNotEmpty) ...[
                    _sectionHeader(context, 'World Info', Icons.menu_book),
                    const SizedBox(height: 4),
                    ...lorebooks.map((e) => _entryTile(context, e)),
                    if (memories.isNotEmpty) const SizedBox(height: 12),
                  ],
                  if (memories.isNotEmpty) ...[
                    _sectionHeader(context, 'Memory Books', Icons.psychology),
                    const SizedBox(height: 4),
                    ...memories.map((e) => _entryTile(context, e)),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 14, color: context.cs.onSurfaceVariant),
        const SizedBox(width: 6),
        Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: context.cs.onSurfaceVariant)),
      ],
    );
  }

  Widget _entryTile(BuildContext context, TriggeredEntry entry) {
    final scheme = context.cs;
    final badgeColor = entry.source == 'vector'
        ? Colors.purple.withValues(alpha: 0.15)
        : entry.source == 'memory'
            ? Colors.teal.withValues(alpha: 0.15)
            : scheme.primaryContainer;
    final badgeText = entry.source == 'vector'
        ? 'vector'
        : entry.source == 'memory'
            ? 'memory'
            : 'keyword';
    final badgeFg = entry.source == 'vector'
        ? Colors.purple
        : entry.source == 'memory'
            ? Colors.teal
            : scheme.onPrimaryContainer;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              entry.name,
              style: TextStyle(fontSize: 13, color: scheme.onSurface),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (entry.lorebookName.isNotEmpty) ...[
            const SizedBox(width: 6),
            Text(
              entry.lorebookName,
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant.withValues(alpha: 0.6)),
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: badgeColor,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(badgeText, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: badgeFg)),
          ),
        ],
      ),
    );
  }
}
