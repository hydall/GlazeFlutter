import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/chat_message.dart';
import '../../../shared/theme/app_colors.dart';

import '../chat_provider.dart';
import '../chat_state.dart';
import '../chat_screen.dart';
import 'message.dart';

const double _kStickToBottomThreshold = 100;
const double _kInstantScrollDistance = 3000;
const int _kInitialRenderCount = 30;
const int _kLoadMoreCount = 20;

class MessageList extends StatefulWidget {
  final List<ChatMessage> messages;
  final bool isGenerating;
  final DateTime? generationStartTime;
  final String charId;
  final double bottomInset;
  final String searchQuery;
  final List<SearchMatch> searchMatches;
  final int searchCurrentIndex;

  const MessageList({
    super.key,
    required this.messages,
    required this.isGenerating,
    this.generationStartTime,
    required this.charId,
    this.bottomInset = 180,
    this.searchQuery = '',
    this.searchMatches = const [],
    this.searchCurrentIndex = 0,
  });

  @override
  State<MessageList> createState() => _MessageListState();
}

class _MessageListState extends State<MessageList> {
  final _scrollController = ScrollController();

  bool _wasAtBottom = true;
  bool _showScrollButton = false;
  bool _isProgrammaticScrolling = false;
  Timer? _programmaticUnlockTimer;
  Timer? _scrollDebounceTimer;

  int _renderCount = _kInitialRenderCount;
  bool _needsInitialScroll = true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _programmaticUnlockTimer?.cancel();
    _scrollDebounceTimer?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant MessageList oldWidget) {
    super.didUpdateWidget(oldWidget);

    final totalCount = widget.messages.length;
    if (totalCount > _renderCount) {
      if (_wasAtBottom) {
        _renderCount = totalCount;
      } else if (_scrollController.hasClients) {
        final pos = _scrollController.position;
        if (pos.hasContentDimensions && pos.pixels < 200) {
          _renderCount = (_renderCount + _kLoadMoreCount).clamp(0, totalCount);
        }
      }
    }

    final newCount = widget.messages.length;
    final oldCount = oldWidget.messages.length;

    if (_wasAtBottom && newCount > oldCount) {
      _scheduleScrollToBottom();
    }

    if (widget.bottomInset != oldWidget.bottomInset && _wasAtBottom) {
      _scrollToBottom(smooth: false);
    }

    int oldTargetIndex = -1;
    if (oldWidget.searchMatches.isNotEmpty && oldWidget.searchCurrentIndex < oldWidget.searchMatches.length) {
      oldTargetIndex = oldWidget.searchMatches[oldWidget.searchCurrentIndex].messageIndex;
    }
    int newTargetIndex = -1;
    if (widget.searchMatches.isNotEmpty && widget.searchCurrentIndex < widget.searchMatches.length) {
      newTargetIndex = widget.searchMatches[widget.searchCurrentIndex].messageIndex;
    }

    if (newTargetIndex != -1 && newTargetIndex != oldTargetIndex) {
      final pos = _scrollController.position;
      if (pos.hasContentDimensions) {
        final max = pos.maxScrollExtent;
        final total = widget.messages.length;
        if (total > 0) {
          if (oldTargetIndex == -1 || (newTargetIndex - oldTargetIndex).abs() > 5) {
            final targetOffset = (newTargetIndex / total) * max;
            _scrollController.jumpTo(targetOffset);
          }
        }
      }
    }
  }

  Widget _buildMessageWidget(ChatMessage msg, int index) {
    final msgMatches = widget.searchMatches.where((m) => m.messageIndex == index).toList();
    final isMatch = msgMatches.isNotEmpty;
    final activeMatchIndex = (widget.searchMatches.isNotEmpty &&
        widget.searchMatches[widget.searchCurrentIndex].messageIndex == index)
        ? widget.searchMatches[widget.searchCurrentIndex].matchIndexInMessage
        : -1;

    return Message(
      key: ValueKey(msg.id),
      content: msg.content,
      isUser: msg.role == 'user',
      isSystem: msg.role == 'system',
      reasoning: msg.reasoning,
      genTime: msg.genTime,
      tokens: msg.tokens,
      isHidden: msg.isHidden,
      isError: msg.isError,
      messageIndex: index,
      totalMessages: widget.messages.length,
      isLast: index == widget.messages.length - 1,
      isGenerating: widget.isGenerating,
      charId: widget.charId,
      swipes: msg.swipes,
      swipeId: msg.swipeId,
      greetingIndex: msg.greetingIndex,
      memoryCoverage: msg.memoryCoverage,
      isSearchMatch: isMatch,
      searchQuery: widget.searchQuery,
      activeMatchIndex: activeMatchIndex,
    );
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_isProgrammaticScrolling) return;
    final pos = _scrollController.position;
    if (!pos.hasContentDimensions) return;

    final distance = pos.maxScrollExtent - pos.pixels;
    final atBottom = distance < _kStickToBottomThreshold;
    final wantsButton = distance > _kStickToBottomThreshold;

    if (pos.pixels < 200 && _renderCount < widget.messages.length) {
      setState(() {
        _renderCount = (_renderCount + _kLoadMoreCount).clamp(0, widget.messages.length);
      });
    }

    if (atBottom != _wasAtBottom || wantsButton != _showScrollButton) {
      setState(() {
        _wasAtBottom = atBottom;
        _showScrollButton = wantsButton;
      });
    }
  }

  void _beginProgrammaticScroll() {
    _isProgrammaticScrolling = true;
    _programmaticUnlockTimer?.cancel();
  }

  void _endProgrammaticScroll({Duration delay = const Duration(milliseconds: 50)}) {
    _programmaticUnlockTimer?.cancel();
    _programmaticUnlockTimer = Timer(delay, () {
      if (!mounted) return;
      _isProgrammaticScrolling = false;
    });
  }

  void _scheduleScrollToBottom() {
    _scrollDebounceTimer?.cancel();
    _scrollDebounceTimer = Timer(const Duration(milliseconds: 50), () {
      if (mounted) _scrollToBottom(smooth: true);
    });
  }

  Future<void> _scrollToBottom({bool smooth = true, bool force = false}) async {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || !_scrollController.hasClients) return;
      final pos = _scrollController.position;
      if (!pos.hasContentDimensions) return;

      final target = pos.maxScrollExtent;
      final distance = target - pos.pixels;
      if (!force && distance.abs() < 0.5) return;

      final useSmooth = smooth && distance.abs() < _kInstantScrollDistance;

      _beginProgrammaticScroll();
      try {
        if (useSmooth) {
          await _scrollController.animateTo(
            target,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
          if (mounted && _scrollController.hasClients) {
            _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
          }
        } else {
          _scrollController.jumpTo(target);
        }
      } finally {
        _endProgrammaticScroll(
          delay: useSmooth
              ? const Duration(milliseconds: 250)
              : const Duration(milliseconds: 50),
        );
      }

      if (mounted && (_showScrollButton || !_wasAtBottom)) {
        setState(() {
          _wasAtBottom = true;
          _showScrollButton = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final messages = widget.messages;
    final totalCount = messages.length;
    final renderCount = _renderCount.clamp(0, totalCount);
    final startFrom = totalCount > renderCount ? totalCount - renderCount : 0;

    if (_needsInitialScroll && totalCount > 0) {
      _needsInitialScroll = false;
      _renderCount = totalCount;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom(smooth: false, force: true);
      });
    }

    return Stack(
      children: [
        ListView.builder(
          controller: _scrollController,
          cacheExtent: 2000,
          padding: EdgeInsets.only(
            top: MediaQuery.paddingOf(context).top + 80,
            bottom: widget.bottomInset,
          ),
          itemCount: renderCount + (widget.isGenerating ? 1 : 0) + (startFrom > 0 ? 1 : 0),
          itemBuilder: (context, index) {
            if (startFrom > 0 && index == 0) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: TextButton(
                    onPressed: () {
                      setState(() {
                        _renderCount = (_renderCount + _kLoadMoreCount).clamp(0, totalCount);
                      });
                    },
                    child: Text('Load earlier messages (${startFrom} more)'),
                  ),
                ),
              );
            }

            final adjustedIndex = startFrom > 0 ? index - 1 : index;

            if (adjustedIndex >= renderCount) {
              return _StreamingIndicator(
                isGenerating: widget.isGenerating,
                generationStartTime: widget.generationStartTime,
                charId: widget.charId,
                totalMessages: totalCount,
                onStreamingTick: _wasAtBottom ? _scheduleScrollToBottom : null,
              );
            }

            final msgIndex = startFrom + adjustedIndex;
            final msg = messages[msgIndex];
            return RepaintBoundary(
              key: ValueKey(msg.id),
              child: _buildMessageWidget(msg, msgIndex),
            );
          },
        ),
        Positioned(
          right: 16,
          bottom: widget.bottomInset + 8,
          child: _ScrollDownButton(
            visible: _showScrollButton,
            onTap: () => _scrollToBottom(smooth: true, force: true),
          ),
        ),
      ],
    );
  }
}

class _StreamingIndicator extends ConsumerWidget {
  final bool isGenerating;
  final DateTime? generationStartTime;
  final String charId;
  final int totalMessages;
  final VoidCallback? onStreamingTick;

  const _StreamingIndicator({
    required this.isGenerating,
    this.generationStartTime,
    required this.charId,
    required this.totalMessages,
    this.onStreamingTick,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!isGenerating) return const SizedBox.shrink();

    final streaming = ref.watch(streamingStateProvider(charId));
    final showStreaming = streaming.text.isNotEmpty;
    final showTyping = !showStreaming;

    if (showStreaming) {
      onStreamingTick?.call();
      return RepaintBoundary(
        child: Message(
          content: streaming.text,
          isUser: false,
          isStreaming: true,
          reasoning: streaming.reasoning,
          messageIndex: -1,
          totalMessages: totalMessages,
          isLast: false,
          isGenerating: true,
          generationStartTime: generationStartTime,
          charId: charId,
        ),
      );
    }

    if (showTyping) {
      return Message(
        content: '',
        isUser: false,
        isTyping: true,
        messageIndex: -1,
        totalMessages: totalMessages,
        isLast: false,
        isGenerating: true,
        generationStartTime: generationStartTime,
        charId: charId,
      );
    }

    return const SizedBox.shrink();
  }
}

class _ScrollDownButton extends StatelessWidget {
  final bool visible;
  final VoidCallback onTap;

  const _ScrollDownButton({required this.visible, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: ScaleTransition(scale: anim, child: child),
      ),
      child: !visible
          ? const SizedBox.shrink(key: ValueKey('hide'))
          : ClipOval(
              key: const ValueKey('show'),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                child: Material(
                  color: context.colors.charBubble.withValues(alpha: 0.78),
                  shape: CircleBorder(
                    side: BorderSide(color: context.cs.outlineVariant),
                  ),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: onTap,
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: context.cs.primary,
                        size: 24,
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
