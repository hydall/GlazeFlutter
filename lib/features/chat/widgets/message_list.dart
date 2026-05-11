import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../core/models/chat_message.dart';
import '../../../shared/theme/app_colors.dart';
import '../chat_screen.dart';
import 'message.dart';

/// Threshold (px from bottom) below which we treat the user as "at bottom":
/// auto-scroll keeps applying, scroll-button stays hidden.
const double _kStickToBottomThreshold = 100;

/// If we're farther than this from the bottom, prefer instant scroll over
/// smooth — animating across thousands of px is jarring and slow.
const double _kInstantScrollDistance = 3000;

class MessageList extends StatefulWidget {
  final List<ChatMessage> messages;
  final String? streamingText;
  final String? streamingReasoning;
  final bool isGenerating;
  final DateTime? generationStartTime;
  final String charId;

  /// Extra space at the bottom of the list to keep the last message above the
  /// input bar / drawer / keyboard. Owner of the layout passes this in so the
  /// list and the scroll-to-bottom button stay in sync with the bottom UI.
  final double bottomInset;

  final String searchQuery;
  final List<SearchMatch> searchMatches;
  final int searchCurrentIndex;

  const MessageList({
    super.key,
    required this.messages,
    this.streamingText,
    this.streamingReasoning,
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
  final _listKey = GlobalKey<SliverAnimatedListState>();
  final List<ChatMessage> _items = [];

  bool _wasAtBottom = true;
  bool _showScrollButton = false;
  bool _isProgrammaticScrolling = false;
  Timer? _programmaticUnlockTimer;

  @override
  void initState() {
    super.initState();
    _items.addAll(widget.messages);
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom(smooth: false, force: true);
    });
  }

  @override
  void dispose() {
    _programmaticUnlockTimer?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  int _itemCount(MessageList w) {
    final showStreaming =
        w.streamingText != null && w.streamingText!.isNotEmpty;
    final showTyping = w.isGenerating &&
        !showStreaming &&
        (w.messages.isEmpty || w.messages.last.role == 'user');
    return w.messages.length + (showStreaming || showTyping ? 1 : 0);
  }

  @override
  void didUpdateWidget(covariant MessageList oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Structural changes (insertions/removals)
    final newMessages = widget.messages;
    
    // Simple structural diffing using IDs
    int i = 0;
    while (i < _items.length || i < newMessages.length) {
      if (i >= _items.length) {
        // Insertion at end
        _items.add(newMessages[i]);
        _listKey.currentState?.insertItem(i);
        i++;
      } else if (i >= newMessages.length) {
        // Removal at end
        final removed = _items.removeAt(i);
        _listKey.currentState?.removeItem(
          i,
          (context, animation) => _buildRemovedItem(removed, i, animation, oldWidget),
        );
      } else if (_items[i].id != newMessages[i].id) {
        // Check if it's an insertion
        if (newMessages.any((m) => m.id == _items[i].id)) {
          // New item inserted before current one
          _items.insert(i, newMessages[i]);
          _listKey.currentState?.insertItem(i);
          i++;
        } else {
          // Current item was removed
          final removed = _items.removeAt(i);
          _listKey.currentState?.removeItem(
            i,
            (context, animation) => _buildRemovedItem(removed, i, animation, oldWidget),
          );
        }
      } else {
        // Same ID, just update the local copy to pick up content changes (variant swipes, etc.)
        _items[i] = newMessages[i];
        i++;
      }
    }

    final newCount = _itemCount(widget);
    final oldCount = _itemCount(oldWidget);
    final streamingChanged =
        widget.streamingText != oldWidget.streamingText ||
        widget.streamingReasoning != oldWidget.streamingReasoning;

    // Auto-stick to bottom only while user was already there. New items
    // appended while user is scrolled up should not yank them back —
    // instead we surface the scroll-to-bottom button.
    if (_wasAtBottom && (newCount > oldCount || streamingChanged)) {
      // Streaming chunks: no animation (would constantly retrigger).
      // New full messages or finalized streaming: smooth if close, instant if far.
      _scrollToBottom(smooth: true);
    }

    if (widget.bottomInset != oldWidget.bottomInset && _wasAtBottom) {
      // The bottom UI changed size (drawer toggled, input grew, keyboard
      // appeared). Stay pinned to bottom so the latest message remains
      // visible above the new bottom edge.
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
          // If the message is far away, we do a rough jump so ListView builds it.
          // Message.didUpdateWidget will then trigger an exact Scrollable.ensureVisible.
          if (oldTargetIndex == -1 || (newTargetIndex - oldTargetIndex).abs() > 5) {
            final targetOffset = (newTargetIndex / total) * max;
            // Use jumpTo to prevent fighting with Message's smooth ensureVisible.
            _scrollController.jumpTo(targetOffset);
          }
        }
      }
    }
  }

  Widget _buildRemovedItem(ChatMessage msg, int index, Animation<double> animation, MessageList w) {
    return FadeTransition(
      opacity: animation,
      child: SizeTransition(
        sizeFactor: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.1),
            end: Offset.zero,
          ).animate(animation),
          child: _buildMessageWidget(msg, index, w, isRemoved: true),
        ),
      ),
    );
  }

  Widget _buildMessageWidget(ChatMessage msg, int index, MessageList w, {bool isRemoved = false}) {
    final msgMatches = w.searchMatches.where((m) => m.messageIndex == index).toList();
    final isMatch = msgMatches.isNotEmpty;
    final activeMatchIndex = (w.searchMatches.isNotEmpty && 
        w.searchMatches[w.searchCurrentIndex].messageIndex == index) 
        ? w.searchMatches[w.searchCurrentIndex].matchIndexInMessage 
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
      totalMessages: w.messages.length,
      isLast: !isRemoved && index == w.messages.length - 1,
      isGenerating: w.isGenerating,
      charId: w.charId,
      swipes: msg.swipes,
      swipeId: msg.swipeId,
      greetingIndex: msg.greetingIndex,
      memoryCoverage: msg.memoryCoverage,
      isSearchMatch: isMatch,
      searchQuery: w.searchQuery,
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

  Future<void> _scrollToBottom({bool smooth = true, bool force = false}) async {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || !_scrollController.hasClients) return;
      final pos = _scrollController.position;
      if (!pos.hasContentDimensions) return;

      final target = pos.maxScrollExtent;
      final distance = target - pos.pixels;
      if (!force && distance.abs() < 0.5) return;

      // Long jumps: never animate. Stay close to Vue's behavior.
      final useSmooth = smooth && distance.abs() < _kInstantScrollDistance;

      _beginProgrammaticScroll();
      try {
        if (useSmooth) {
          await _scrollController.animateTo(
            target,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
          // Re-pin in case content grew during the animation (streaming).
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
    final showStreaming =
        widget.streamingText != null && widget.streamingText!.isNotEmpty;
    final showTyping =
        widget.isGenerating &&
        !showStreaming &&
        (widget.messages.isEmpty || widget.messages.last.role == 'user');

    return Stack(
      children: [
        CustomScrollView(
          controller: _scrollController,
          slivers: [
            SliverPadding(
              padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top + 80),
              sliver: SliverAnimatedList(
                key: _listKey,
                initialItemCount: _items.length,
                itemBuilder: (context, index, animation) {
                  if (index >= _items.length) return const SizedBox.shrink();
                  final msg = _items[index];
                  return FadeTransition(
                    opacity: animation,
                    child: SizeTransition(
                      sizeFactor: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.05),
                          end: Offset.zero,
                        ).animate(animation),
                        child: _buildMessageWidget(msg, index, widget),
                      ),
                    ),
                  );
                },
              ),
            ),
            SliverToBoxAdapter(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: child),
                child: Column(
                  key: ValueKey('bottom-area-${showStreaming}-${showTyping}'),
                  children: [
                    if (showStreaming)
                      RepaintBoundary(
                        child: Message(
                          content: widget.streamingText!,
                          isUser: false,
                          isStreaming: true,
                          reasoning: widget.streamingReasoning,
                          messageIndex: -1,
                          totalMessages: widget.messages.length,
                          isLast: false,
                          isGenerating: true,
                          generationStartTime: widget.generationStartTime,
                          charId: widget.charId,
                        ),
                      )
                    else if (showTyping)
                      Message(
                        content: '',
                        isUser: false,
                        isTyping: true,
                        messageIndex: -1,
                        totalMessages: widget.messages.length,
                        isLast: false,
                        isGenerating: true,
                        generationStartTime: widget.generationStartTime,
                        charId: widget.charId,
                      ),
                    SizedBox(height: widget.bottomInset),
                  ],
                ),
              ),
            ),
          ],
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
                  color: const Color(0xFF1E1E1E).withValues(alpha: 0.78),
                  shape: const CircleBorder(
                    side: BorderSide(color: AppColors.glassBorder),
                  ),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: onTap,
                    child: const SizedBox(
                      width: 40,
                      height: 40,
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: AppColors.accent,
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
