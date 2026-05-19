import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/chat_message.dart';
import '../../../features/settings/app_settings_provider.dart';
import '../../../shared/theme/app_colors.dart';

import '../chat_provider.dart';
import '../chat_screen.dart';
import 'message.dart';

const double _kStickToBottomThreshold = 100;
const double _kInstantScrollDistance = 3000;
const int _kInitialRenderCount = 30;
const int _kLoadMoreCount = 20;

class ScrollAnchor {
  final String messageId;
  final double offsetFromViewportTop;
  const ScrollAnchor(this.messageId, this.offsetFromViewportTop);
}

/// In-memory anchor cache keyed by sessionId — survives navigation within the app.
final scrollAnchorProvider =
    StateProvider.family<ScrollAnchor?, String>((ref, sessionId) => null);

sealed class _ListItem {}

class _MessageItem extends _ListItem {
  final ChatMessage message;
  final int messageIndex;
  _MessageItem(this.message, this.messageIndex);
}

class _DaySeparatorItem extends _ListItem {
  final DateTime date;
  _DaySeparatorItem(this.date);
}

class _ContextCutoffItem extends _ListItem {}

class MessageList extends ConsumerStatefulWidget {
  final List<ChatMessage> messages;
  final bool isGenerating;
  final DateTime? generationStartTime;
  final String charId;
  final String? sessionId;
  final double bottomInset;
  final bool isDrawerOpen;
  final String searchQuery;
  final List<SearchMatch> searchMatches;
  final int searchCurrentIndex;
  final int contextCutoffIndex;

  const MessageList({
    super.key,
    required this.messages,
    required this.isGenerating,
    this.generationStartTime,
    required this.charId,
    this.sessionId,
    this.bottomInset = 180,
    this.isDrawerOpen = false,
    this.searchQuery = '',
    this.searchMatches = const [],
    this.searchCurrentIndex = 0,
    this.contextCutoffIndex = -1,
  });

  @override
  ConsumerState<MessageList> createState() => _MessageListState();
}

class _MessageListState extends ConsumerState<MessageList> {
  final _scrollController = ScrollController();

  bool _wasAtBottom = true;
  bool _showScrollButton = false;
  bool _isProgrammaticScrolling = false;
  Timer? _programmaticUnlockTimer;
  Timer? _scrollDebounceTimer;

  int _renderCount = _kInitialRenderCount;
  bool _needsInitialScroll = true;

  /// GlobalKey per message id — required for anchor capture/restore via the
  /// render tree.
  final Map<String, GlobalKey> _msgKeys = {};

  /// True once an anchor restore (or scroll-to-bottom fallback) has run for
  /// the current session. Prevents the build-time fallback from firing every
  /// frame.
  bool _initialAnchorAttempted = false;

  /// True once the initial scroll position has been applied. While false, the
  /// ListView is laid out but kept invisible via `Offstage` so the user
  /// doesn't see a flash of the top of the chat before we jump to the saved
  /// anchor / bottom.
  bool _initialScrollDone = false;

  /// Pending search target — set when search index changes but target message
  /// isn't currently rendered. Applied after a render pass expands `_renderCount`.
  int? _pendingSearchScrollIndex;

  /// Debounced anchor save while the user is scrolling so the persisted
  /// position stays close to wherever they paused last.
  Timer? _anchorSaveDebounce;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void deactivate() {
    // Capture anchor while the render tree is still live. By the time
    // `dispose` runs, the ScrollController/RenderObjects are gone and
    // `getOffsetToReveal` returns nothing useful.
    _saveAnchor(widget.sessionId);
    super.deactivate();
  }

  @override
  void dispose() {
    _anchorSaveDebounce?.cancel();
    _programmaticUnlockTimer?.cancel();
    _scrollDebounceTimer?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  GlobalKey _keyFor(String msgId) =>
      _msgKeys.putIfAbsent(msgId, () => GlobalKey(debugLabel: 'msg_$msgId'));

  void _pruneStaleKeys() {
    final liveIds = widget.messages.map((m) => m.id).toSet();
    _msgKeys.removeWhere((id, _) => !liveIds.contains(id));
  }

  ScrollAnchor? _captureAnchor() {
    if (!_scrollController.hasClients) return null;
    final pos = _scrollController.position;
    if (!pos.hasContentDimensions) return null;
    final currentOffset = pos.pixels;
    ScrollAnchor? best;
    double bestAbs = double.infinity;
    for (final entry in _msgKeys.entries) {
      final ctx = entry.value.currentContext;
      if (ctx == null) continue;
      final ro = ctx.findRenderObject();
      if (ro is! RenderBox || !ro.attached) continue;
      final viewport = RenderAbstractViewport.maybeOf(ro);
      if (viewport == null) continue;
      final reveal = viewport.getOffsetToReveal(ro, 0.0).offset;
      final delta = reveal - currentOffset; // distance from viewport top to box top
      if (delta.abs() < bestAbs) {
        bestAbs = delta.abs();
        best = ScrollAnchor(entry.key, delta);
      }
    }
    return best;
  }

  /// Returns true when the requested message was found and the scroll position
  /// applied.
  bool _restoreAnchor(ScrollAnchor anchor) {
    if (!_scrollController.hasClients) return false;
    final pos = _scrollController.position;
    if (!pos.hasContentDimensions) return false;
    final key = _msgKeys[anchor.messageId];
    final ctx = key?.currentContext;
    if (ctx == null) return false;
    final ro = ctx.findRenderObject();
    if (ro is! RenderBox || !ro.attached) return false;
    final viewport = RenderAbstractViewport.maybeOf(ro);
    if (viewport == null) return false;
    final reveal = viewport.getOffsetToReveal(ro, 0.0).offset;
    final target =
        (reveal - anchor.offsetFromViewportTop).clamp(0.0, pos.maxScrollExtent);
    if ((target - pos.pixels).abs() < 0.5) return true;
    _beginProgrammaticScroll();
    _scrollController.jumpTo(target);
    _endProgrammaticScroll();
    return true;
  }

  void _saveAnchor(String? sessionId) {
    if (sessionId == null || sessionId.isEmpty) return;
    // `ref` is invalid once the widget has been unmounted; guard against
    // late-firing debounce timers.
    if (!mounted) return;
    // Don't overwrite a saved anchor with "at the very bottom" — that's
    // already the default restore behaviour and saving it just hides whatever
    // useful position the user had previously.
    if (_wasAtBottom) {
      ref.read(scrollAnchorProvider(sessionId).notifier).state = null;
      return;
    }
    final anchor = _captureAnchor();
    if (anchor == null) return;
    ref.read(scrollAnchorProvider(sessionId).notifier).state = anchor;
  }

  @override
  void didUpdateWidget(covariant MessageList oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Session switch: persist the old anchor, reset state so the new session
    // either restores its own anchor or falls back to scroll-to-bottom.
    if (widget.sessionId != oldWidget.sessionId) {
      _saveAnchor(oldWidget.sessionId);
      _msgKeys.clear();
      _wasAtBottom = true;
      _showScrollButton = false;
      _renderCount = _kInitialRenderCount;
      _needsInitialScroll = true;
      _initialAnchorAttempted = false;
      _initialScrollDone = false;
      _pendingSearchScrollIndex = null;
      return;
    }

    final totalCount = widget.messages.length;
    final oldCount = oldWidget.messages.length;

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

    // Edit / height-change preservation: when message content changes (not just
    // length) and the user isn't pinned to the bottom, snapshot the anchor
    // BEFORE the new content lays out, then restore it after the next frame.
    // didUpdateWidget runs against the previous frame's render tree, so the
    // capture sees old box positions; the post-frame restore sees new ones.
    ScrollAnchor? editAnchor;
    if (!_wasAtBottom &&
        totalCount == oldCount &&
        !identical(widget.messages, oldWidget.messages)) {
      editAnchor = _captureAnchor();
    }

    if (_wasAtBottom && totalCount > oldCount) {
      _scheduleScrollToBottom();
    }

    // Keyboard / drawer / input-bar resize — Telegram-style: shift content up
    // by exactly the inset delta so what was just above the new panel stays
    // visible. This is `el.scrollTop += diff` from Vue's updateContentPadding.
    if (widget.bottomInset != oldWidget.bottomInset) {
      final delta = widget.bottomInset - oldWidget.bottomInset;
      
      if (widget.isDrawerOpen != oldWidget.isDrawerOpen) {
        // The drawer opens/closes visually over 260ms via a TweenAnimationBuilder
        // in chat_screen, but `bottomInset` is passed as the FINAL post-animation value.
        // We animate the scroll over 260ms to match the visual panel slide.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_scrollController.hasClients) return;
          final pos = _scrollController.position;
          if (!pos.hasContentDimensions) return;
          final target = (pos.pixels + delta).clamp(0.0, pos.maxScrollExtent);
          if ((target - pos.pixels).abs() < 0.5) return;
          _beginProgrammaticScroll();
          _scrollController
              .animateTo(
            target,
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
          )
              .whenComplete(() {
            _endProgrammaticScroll(delay: const Duration(milliseconds: 30));
          });
        });
      } else {
        // OS Keyboard resize.
        // `bottomInset` changes frame-by-frame on mobile, or instantly on Windows.
        // Jump synchronously so the scroll stays perfectly locked to the inset
        // without any 1-frame lag or animation delay. We clamp to `maxScrollExtent + delta`
        // because the layout hasn't updated `maxScrollExtent` yet for this frame's padding change.
        if (_scrollController.hasClients) {
          final pos = _scrollController.position;
          if (pos.hasContentDimensions) {
            final target = (pos.pixels + delta).clamp(0.0, pos.maxScrollExtent + math.max(0.0, delta));
            if ((target - pos.pixels).abs() >= 0.5) {
              pos.jumpTo(target);
            }
          }
        }
      }
    }

    // Search navigation: jump precisely to the target message via its
    // GlobalKey instead of the previous (idx/total)*max approximation.
    int oldTargetIndex = -1;
    if (oldWidget.searchMatches.isNotEmpty &&
        oldWidget.searchCurrentIndex < oldWidget.searchMatches.length) {
      oldTargetIndex =
          oldWidget.searchMatches[oldWidget.searchCurrentIndex].messageIndex;
    }
    int newTargetIndex = -1;
    if (widget.searchMatches.isNotEmpty &&
        widget.searchCurrentIndex < widget.searchMatches.length) {
      newTargetIndex =
          widget.searchMatches[widget.searchCurrentIndex].messageIndex;
    }
    if (newTargetIndex != -1 && newTargetIndex != oldTargetIndex) {
      _scrollToMessageIndex(newTargetIndex);
    }

    if (editAnchor != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _restoreAnchor(editAnchor!);
      });
    }
  }

  void _markInitialScrollDone() {
    if (!mounted || _initialScrollDone) return;
    setState(() => _initialScrollDone = true);
  }

  /// Jumps to `maxScrollExtent`, then re-jumps on subsequent frames as the
  /// extent grows. ListView only lays out items near the current scroll
  /// position; on the very first frame `maxScrollExtent` is extrapolated from
  /// the top ~10 items' average height and severely underestimates the true
  /// total for long chats (we saw 317-message chats landing at item #20).
  /// Re-jumping a handful of times lets the extent stabilise as items are
  /// laid out around the new scroll position.
  void _jumpToBottomNow({int remainingRetargets = 10}) {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (!pos.hasContentDimensions) return;
    _beginProgrammaticScroll();
    _scrollController.jumpTo(pos.maxScrollExtent);
    _endProgrammaticScroll();
    _wasAtBottom = true;
    _showScrollButton = false;
    if (remainingRetargets <= 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final p = _scrollController.position;
      if (!p.hasContentDimensions) return;
      // If maxScrollExtent grew (more items got laid out below the previous
      // estimate), bring `pixels` up to the new max.
      if (p.maxScrollExtent - p.pixels > 0.5) {
        _jumpToBottomNow(remainingRetargets: remainingRetargets - 1);
      }
    });
  }

  /// Initial-restore retry loop. The anchor's message may live far outside
  /// the rendered window, so a single restore attempt usually fails. First
  /// pass: coarse jump to the message's approximate scroll offset using its
  /// chronological index — this triggers ListView to lay out items in that
  /// region. Subsequent passes refine via the now-available GlobalKey.
  void _restoreSavedAnchor(ScrollAnchor anchor,
      {required int remainingAttempts}) {
    if (!mounted || remainingAttempts <= 0) {
      _jumpToBottomNow();
      _markInitialScrollDone();
      return;
    }
    if (!_scrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _restoreSavedAnchor(anchor,
            remainingAttempts: remainingAttempts - 1);
      });
      return;
    }
    final pos = _scrollController.position;
    if (!pos.hasContentDimensions || pos.maxScrollExtent <= 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _restoreSavedAnchor(anchor,
            remainingAttempts: remainingAttempts - 1);
      });
      return;
    }

    if (_restoreAnchor(anchor)) {
      _wasAtBottom = false;
      _showScrollButton = true;
      _markInitialScrollDone();
      return;
    }

    final idx = widget.messages.indexWhere((m) => m.id == anchor.messageId);
    if (idx < 0) {
      _jumpToBottomNow();
      _markInitialScrollDone();
      return;
    }

    // Coarse jump based on chronological position so the target's region gets
    // laid out by the next frame.
    final fraction = idx / widget.messages.length.clamp(1, 1 << 30);
    final estimate =
        (fraction * pos.maxScrollExtent).clamp(0.0, pos.maxScrollExtent);
    _beginProgrammaticScroll();
    _scrollController.jumpTo(estimate);
    _endProgrammaticScroll();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restoreSavedAnchor(anchor,
          remainingAttempts: remainingAttempts - 1);
    });
  }

  /// Render-aware jump to a message by chronological index. Expands the
  /// rendered window if needed so the target is laid out, then uses
  /// `Scrollable.ensureVisible` for a pixel-accurate position regardless of
  /// variable item heights.
  void _scrollToMessageIndex(int messageIndex, {double alignment = 0.5, int remainingAttempts = 15}) {
    if (messageIndex < 0 || messageIndex >= widget.messages.length) return;
    final msg = widget.messages[messageIndex];
    final keyCtx = _msgKeys[msg.id]?.currentContext;

    if (keyCtx != null) {
      _beginProgrammaticScroll();
      Scrollable.ensureVisible(
        keyCtx,
        alignment: alignment,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
      ).whenComplete(() {
        _endProgrammaticScroll(
            delay: const Duration(milliseconds: 280));
      });
      return;
    }

    if (remainingAttempts <= 0) return;

    // Target isn't in the rendered window — expand it, coarse jump, then retry next frame.
    final totalCount = widget.messages.length;
    _pendingSearchScrollIndex = messageIndex;
    setState(() {
      _renderCount = totalCount;
    });

    if (_scrollController.hasClients) {
      final pos = _scrollController.position;
      if (pos.hasContentDimensions && pos.maxScrollExtent > 0) {
        final fraction = messageIndex / widget.messages.length.clamp(1, 1 << 30);
        final estimate = (fraction * pos.maxScrollExtent).clamp(0.0, pos.maxScrollExtent);
        _beginProgrammaticScroll();
        _scrollController.jumpTo(estimate);
        _endProgrammaticScroll();
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final pending = _pendingSearchScrollIndex;
      _pendingSearchScrollIndex = null;
      if (pending != null) {
        _scrollToMessageIndex(pending, alignment: alignment, remainingAttempts: remainingAttempts - 1);
      }
    });
  }

  Widget _buildMessageWidget(ChatMessage msg, int index) {
    final msgMatches = widget.searchMatches.where((m) => m.messageIndex == index).toList();
    final isMatch = msgMatches.isNotEmpty;
    final activeMatchIndex = (widget.searchMatches.isNotEmpty &&
        widget.searchMatches[widget.searchCurrentIndex].messageIndex == index)
        ? widget.searchMatches[widget.searchCurrentIndex].matchIndexInMessage
        : -1;

    return Message(
      key: _keyFor(msg.id),
      content: msg.content,
      isUser: msg.role == 'user',
      isSystem: msg.role == 'system',
      reasoning: msg.reasoning,
      isAllReasoning: msg.isAllReasoning,
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
      triggeredLorebooks: msg.triggeredLorebooks,
      triggeredMemories: msg.triggeredMemories,
      isSearchMatch: isMatch,
      searchQuery: widget.searchQuery,
      activeMatchIndex: activeMatchIndex,
      time: msg.time,
    );
  }

  List<_ListItem> _buildItems() {
    final messages = widget.messages;
    final cutoffIndex = widget.contextCutoffIndex;
    final items = <_ListItem>[];
    DateTime? lastDate;

    int visibleNonHiddenCount = 0;

    for (int i = 0; i < messages.length; i++) {
      final msg = messages[i];
      final ts = msg.timestamp;
      if (ts != null) {
        final msgDate = DateTime.fromMillisecondsSinceEpoch(ts);
        final dateKey = DateTime(msgDate.year, msgDate.month, msgDate.day);
        if (dateKey != lastDate) {
          items.add(_DaySeparatorItem(dateKey));
          lastDate = dateKey;
        }
      }

      if (!msg.isHidden && !msg.isTyping) {
        if (visibleNonHiddenCount == cutoffIndex && cutoffIndex > 0) {
          items.add(_ContextCutoffItem());
        }
        visibleNonHiddenCount++;
      }

      items.add(_MessageItem(msg, i));
    }

    if (cutoffIndex >= visibleNonHiddenCount && visibleNonHiddenCount > 0) {
      items.add(_ContextCutoffItem());
    }

    return items;
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_isProgrammaticScrolling) return;
    final pos = _scrollController.position;
    if (!pos.hasContentDimensions) return;

    final distance = pos.maxScrollExtent - pos.pixels;

    if (pos.pixels < 200 && _renderCount < widget.messages.length) {
      setState(() {
        _renderCount = (_renderCount + _kLoadMoreCount).clamp(0, widget.messages.length);
      });
    }

    // Continuously track `_wasAtBottom` from the actual distance. The
    // `_handleUserScroll` callback only fires during user drag, so without
    // this the flag stays stale through ballistic / programmatic scrolling
    // and ends up clearing/saving the wrong anchor on exit.
    final atBottom = distance <= _kStickToBottomThreshold;
    final wantsButton = !atBottom;
    final needsRebuild = atBottom != _wasAtBottom || wantsButton != _showScrollButton;
    if (needsRebuild) {
      setState(() {
        _wasAtBottom = atBottom;
        _showScrollButton = wantsButton;
      });
    }

    // Debounced anchor save — keeps the persisted position close to the most
    // recent paused-state so `deactivate` is not the only chance to save.
    _anchorSaveDebounce?.cancel();
    _anchorSaveDebounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      _saveAnchor(widget.sessionId);
    });
  }

  bool _handleUserScroll(UserScrollNotification notification) {
    if (notification.direction == ScrollDirection.reverse) {
      if (_wasAtBottom) {
        setState(() {
          _wasAtBottom = false;
        });
      }
    } else if (notification.direction == ScrollDirection.forward) {
      if (!_wasAtBottom && _scrollController.hasClients) {
        final pos = _scrollController.position;
        if (pos.hasContentDimensions) {
          final distance = pos.maxScrollExtent - pos.pixels;
          if (distance < _kStickToBottomThreshold) {
            setState(() {
              _wasAtBottom = true;
            });
          }
        }
      }
    }
    return false;
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
    _pruneStaleKeys();

    final allItems = _buildItems();
    final totalCount = allItems.length;
    final renderCount = _renderCount.clamp(0, totalCount);
    final startFrom = totalCount > renderCount ? totalCount - renderCount : 0;

    if (_needsInitialScroll && totalCount > 0) {
      _needsInitialScroll = false;
      _renderCount = totalCount;
      final savedAnchor = widget.sessionId == null
          ? null
          : ref.read(scrollAnchorProvider(widget.sessionId!));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_initialAnchorAttempted) return;
        _initialAnchorAttempted = true;
        if (savedAnchor != null) {
          _restoreSavedAnchor(savedAnchor, remainingAttempts: 20);
        } else {
          // Inline jump so `_initialScrollDone` flips in the same frame as
          // the scroll — avoids a flash of the top of the list.
          if (_scrollController.hasClients) {
            final pos = _scrollController.position;
            if (pos.hasContentDimensions) {
              _beginProgrammaticScroll();
              _scrollController.jumpTo(pos.maxScrollExtent);
              _endProgrammaticScroll();
            }
          }
          _markInitialScrollDone();
        }
      });
    }

    return Stack(
      children: [
        Offstage(
          // Keep the list laid out (we need `maxScrollExtent` to be computed
          // before the first scroll) but unpainted until the initial scroll
          // has run. Avoids a 1–2 frame flash showing the top of the chat
          // before we jump to the saved anchor / bottom.
          offstage: !_initialScrollDone,
          child: NotificationListener<UserScrollNotification>(
          onNotification: _handleUserScroll,
          child: ListView.builder(
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
                totalMessages: widget.messages.length,
                onStreamingTick: _wasAtBottom ? _scheduleScrollToBottom : null,
              );
            }

            final item = allItems[startFrom + adjustedIndex];

            return switch (item) {
              _MessageItem(:final message, :final messageIndex) => RepaintBoundary(
                  key: ValueKey(message.id),
                  child: _buildMessageWidget(message, messageIndex),
                ),
              _DaySeparatorItem(:final date) => _DaySeparator(date: date),
              _ContextCutoffItem() => const _ContextCutoffDivider(),
            };
           },
          ),
         ),
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
    final showStreaming = streaming.text.isNotEmpty || (streaming.reasoning?.isNotEmpty ?? false);
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

class _ScrollDownButton extends ConsumerWidget {
  final bool visible;
  final VoidCallback onTap;

  const _ScrollDownButton({required this.visible, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final batterySaver = ref.watch(appSettingsProvider).valueOrNull?.batterySaver ?? false;

    final buttonContent = Material(
      color: context.colors.charBubble.withValues(alpha: batterySaver ? 1.0 : 0.78),
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
    );

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
              child: batterySaver
                  ? buttonContent
                  : BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                      child: buttonContent,
                    ),
            ),
    );
  }
}

class _DaySeparator extends StatelessWidget {
  final DateTime date;

  const _DaySeparator({required this.date});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final msgDay = DateTime(date.year, date.month, date.day);

    final String label;
    if (msgDay == today) {
      label = 'Today';
    } else if (msgDay == yesterday) {
      label = 'Yesterday';
    } else {
      label = '${date.day} ${_monthName(date.month)} ${date.year}';
    }

    final color = context.cs.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      child: Row(
        children: [
          Expanded(child: Container(height: 1, color: color.withValues(alpha: 0.2))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              label,
              style: TextStyle(
                color: color.withValues(alpha: 0.6),
                fontSize: 11,
                fontWeight: FontWeight.w500,
                letterSpacing: 1,
              ),
            ),
          ),
          Expanded(child: Container(height: 1, color: color.withValues(alpha: 0.2))),
        ],
      ),
    );
  }

  static String _monthName(int month) => switch (month) {
        1 => 'January',
        2 => 'February',
        3 => 'March',
        4 => 'April',
        5 => 'May',
        6 => 'June',
        7 => 'July',
        8 => 'August',
        9 => 'September',
        10 => 'October',
        11 => 'November',
        12 => 'December',
        _ => '',
      };
}

class _ContextCutoffDivider extends StatelessWidget {
  const _ContextCutoffDivider();

  @override
  Widget build(BuildContext context) {
    final color = context.cs.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      child: Row(
        children: [
          Expanded(child: Container(height: 1, color: color.withValues(alpha: 0.2))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              'CONTEXT LIMIT',
              style: TextStyle(
                color: color.withValues(alpha: 0.6),
                fontSize: 11,
                fontWeight: FontWeight.w500,
                letterSpacing: 1,
              ),
            ),
          ),
          Expanded(child: Container(height: 1, color: color.withValues(alpha: 0.2))),
        ],
      ),
    );
  }
}
