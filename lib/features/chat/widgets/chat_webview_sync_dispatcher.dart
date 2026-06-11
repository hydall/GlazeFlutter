import 'dart:async';

import 'package:collection/collection.dart';

import '../../../core/models/chat_message.dart';
import '../bridge/chat_bridge_controller.dart';
import 'chat_message_sync.dart' show chatMessageListsIdentical, lastUserMessageId;

/// Mutable per-frame state owned by the [ChatWebViewSyncDispatcher].
/// Lifted out of the widget so the dispatcher can be tested in
/// isolation. All three fields are written from `didUpdateWidget`
/// and read by other lifecycle hooks (e.g. the streaming
/// `ref.listen` in `build`).
class ChatWebViewSyncState {
  bool wasGenerating = false;
  bool streamingSent = false;
  bool regenStreamingSent = false;
}

/// Per-field diff dispatch for [ChatWebViewWidget.didUpdateWidget].
///
/// Extracted from the widget because the original method had grown
/// past 180 lines with 14 hand-written diff branches. The dispatcher
/// is a plain class (no mixin) that holds a reference to the
/// [ChatBridgeController] and the parent widget's [old] + [current]
/// state, plus a small [ChatWebViewSyncState] bundle for the streaming
/// placeholders. Public methods are scoped to one concern each so
/// future changes (e.g. another field) add a new branch without
/// touching the others.
class ChatWebViewSyncDispatcher {
  ChatWebViewSyncDispatcher({required this.state}) : assert(true);

  final ChatWebViewSyncState state;

  /// Apply the diff between the previous and current [ChatWebViewWidget].
  ///
  /// Returns a [ChatWebViewSyncResult] that tells the caller whether
  /// the message sync and ext-block sync should run (`runMessageSync`)
  /// and whether a streaming placeholder should be appended to the
  /// bridge (`appendPlaceholder` + `placeholderMessage`). When
  /// `sessionSwitched` is `true` the caller should *not* call
  /// [ChatMessageSync.sync] — the session switch path handles that
  /// itself with a full bridge reset.
  ChatWebViewSyncResult dispatch({
    required ChatBridgeController? bridge,
    required ChatWebViewWidgetFields old,
    required ChatWebViewWidgetFields current,
    required List<ChatMessage> oldMessages,
    required List<ChatMessage> newMessages,
    required String streamingId,
    required Future<void> Function() onSyncExtBlockPanels,
    required Future<void> Function(ChatMessage) appendMessage,
    required ChatMessage Function() buildStreamingPlaceholder,
    bool ready = true,
  }) {
    if (!ready || bridge == null) {
      // Still need to keep `wasGenerating` rolling for the next frame
      // so the placeholder injection can detect the rising edge.
      state.wasGenerating = current.isGenerating;
      return const ChatWebViewSyncResult(
        runMessageSync: false,
        appendPlaceholder: false,
        sessionSwitched: false,
      );
    }

    _maybeUpdateMemoryBook(
      bridge: bridge,
      old: old,
      current: current,
    );

    if (current.charId != old.charId || current.sessionId != old.sessionId) {
      // The actual session switch is performed by the caller; we just
      // record the rising edge of `wasGenerating` so the post-switch
      // `didUpdateWidget` doesn't re-inject the placeholder.
      state.wasGenerating = current.isGenerating;
      return const ChatWebViewSyncResult(
        runMessageSync: false,
        appendPlaceholder: false,
        sessionSwitched: true,
      );
    }

    if (_identityChanged(old: old, current: current)) {
      bridge.setIdentity(
        charName: current.charName,
        charColor: current.charColor,
        personaName: current.personaName,
        layout: current.chatLayout,
        charAvatarPath: current.charAvatarPath,
        personaAvatarPath: current.personaAvatarPath,
        greetingTotal: current.greetingTotal,
      );
    }

    _maybeApplyTheme(bridge: bridge, old: old, current: current);
    _maybeApplyBackgroundImage(bridge: bridge, old: old, current: current);
    _maybeApplyBackgroundNoise(bridge: bridge, old: old, current: current);
    _maybeApplyChatFont(bridge: bridge, old: old, current: current);
    _maybeApplySelectionMode(bridge: bridge, old: old, current: current);
    _maybeApplyMessageSettings(bridge: bridge, old: old, current: current);
    _maybeApplySearch(bridge: bridge, old: old, current: current);
    _maybeApplyInsets(bridge: bridge, old: old, current: current);

    _maybeApplyGeneratingState(
      bridge: bridge,
      old: old,
      current: current,
    );

    if (state.wasGenerating && !current.isGenerating) {
      final finishedRegenId = old.regenTargetId;
      if (finishedRegenId != null) {
        final finalMsg = newMessages
            .where((m) => m.id == finishedRegenId)
            .firstOrNull;
        if (finalMsg != null) {
          // Pass isLast:true so _executeUpdateMessage restores data-is-last
          // on the char section. setLastMessage(null) clears it at generation
          // start; without this the swipe gesture handler sees isLast=false
          // and blocks subsequent left-swipe-to-regenerate gestures.
          bridge.updateMessage(finalMsg, isLast: true);
        }
      } else {
        // Fresh generation (no regenTargetId): restore data-is-last on the
        // last char message so subsequent swipe-to-regenerate still works.
        final lastCharMsg = newMessages.lastWhereOrNull(
          (m) => m.role == 'assistant' || m.role == 'character',
        );
        if (lastCharMsg != null) {
          bridge.updateMessage(lastCharMsg, isLast: true);
        }
      }
      if (!state.regenStreamingSent) {
        bridge.removeMessage(streamingId);
      }
      state.streamingSent = false;
      state.regenStreamingSent = false;
      unawaited(onSyncExtBlockPanels());
    }

    final runMessageSync = !identical(oldMessages, newMessages) &&
        !chatMessageListsIdentical(oldMessages, newMessages);

    // Fresh generation started (no regenTargetId) → inject typing placeholder.
    final shouldInjectPlaceholder = !state.wasGenerating &&
        current.isGenerating &&
        current.regenTargetId == null &&
        !state.streamingSent;
    state.wasGenerating = current.isGenerating;

    return ChatWebViewSyncResult(
      runMessageSync: runMessageSync,
      appendPlaceholder: shouldInjectPlaceholder,
      sessionSwitched: false,
      placeholder: shouldInjectPlaceholder
          ? buildStreamingPlaceholder()
          : null,
    );
  }

  /// Append the streaming placeholder to the bridge and flip
  /// [ChatWebViewSyncState.streamingSent] to `true`. Called by the
  /// widget after [dispatch] returns `appendPlaceholder: true`.
  void onPlaceholderAppended() {
    state.streamingSent = true;
  }

  void _maybeUpdateMemoryBook({
    required ChatBridgeController bridge,
    required ChatWebViewWidgetFields old,
    required ChatWebViewWidgetFields current,
  }) {
    if (current.memoryEntries != old.memoryEntries ||
        current.memoryDrafts != old.memoryDrafts) {
      bridge.updateMemoryBookData(
        entries: current.memoryEntries
            .map((e) => {'status': e.status, 'messageIds': e.messageIds})
            .toList(),
        pendingDrafts: current.memoryDrafts
            .map((e) => {'messageIds': e.messageIds})
            .toList(),
      );
    }
  }

  void _maybeApplyTheme({
    required ChatBridgeController bridge,
    required ChatWebViewWidgetFields old,
    required ChatWebViewWidgetFields current,
  }) {
    if (current.themeSyncKey != old.themeSyncKey ||
        current.chatLayout != old.chatLayout ||
        current.elementOpacity != old.elementOpacity ||
        current.elementBlur != old.elementBlur ||
        current.chatFontSize != old.chatFontSize) {
      bridge.applyTheme(current.buildThemeMap());
    }
  }

  void _maybeApplyBackgroundImage({
    required ChatBridgeController bridge,
    required ChatWebViewWidgetFields old,
    required ChatWebViewWidgetFields current,
  }) {
    if (current.bgImagePath != old.bgImagePath ||
        current.bgBlur != old.bgBlur ||
        current.bgOpacity != old.bgOpacity ||
        current.bgDim != old.bgDim) {
      bridge.setBackgroundImage(
        current.bgImagePath,
        current.bgBlur.toInt(),
        current.bgOpacity,
      );
      bridge.applyTheme({'bg-dim': current.bgDim.toStringAsFixed(2)});
    }
  }

  void _maybeApplyBackgroundNoise({
    required ChatBridgeController bridge,
    required ChatWebViewWidgetFields old,
    required ChatWebViewWidgetFields current,
  }) {
    if (current.bgNoiseOpacity != old.bgNoiseOpacity ||
        current.bgNoiseIntensity != old.bgNoiseIntensity) {
      bridge.setBackgroundNoise(
        current.bgNoiseOpacity,
        current.bgNoiseIntensity,
      );
    }
  }

  void _maybeApplyChatFont({
    required ChatBridgeController bridge,
    required ChatWebViewWidgetFields old,
    required ChatWebViewWidgetFields current,
  }) {
    if (current.chatFontName != old.chatFontName ||
        current.chatFontDataUrl != old.chatFontDataUrl ||
        current.chatFontSize != old.chatFontSize ||
        current.chatLetterSpacing != old.chatLetterSpacing) {
      bridge.setChatFont(
        fontName: current.chatFontName,
        fontDataUrl: current.chatFontDataUrl,
        fontSize: current.chatFontSize,
        letterSpacing: current.chatLetterSpacing,
      );
    }
  }

  void _maybeApplySelectionMode({
    required ChatBridgeController bridge,
    required ChatWebViewWidgetFields old,
    required ChatWebViewWidgetFields current,
  }) {
    if (current.isSelectionMode != old.isSelectionMode) {
      bridge.setSelectionMode(current.isSelectionMode);
    }
  }

  void _maybeApplyMessageSettings({
    required ChatBridgeController bridge,
    required ChatWebViewWidgetFields old,
    required ChatWebViewWidgetFields current,
  }) {
    if (current.batterySaver != old.batterySaver ||
        current.hideMessageId != old.hideMessageId ||
        current.hideGenerationTime != old.hideGenerationTime ||
        current.hideTokenCount != old.hideTokenCount ||
        current.disableSwipeRegeneration != old.disableSwipeRegeneration) {
      bridge.setMessageSettings(
        batterySaver: current.batterySaver,
        hideMessageId: current.hideMessageId,
        hideGenerationTime: current.hideGenerationTime,
        hideTokenCount: current.hideTokenCount,
        disableSwipeRegeneration: current.disableSwipeRegeneration,
      );
    }
  }

  void _maybeApplySearch({
    required ChatBridgeController bridge,
    required ChatWebViewWidgetFields old,
    required ChatWebViewWidgetFields current,
  }) {
    if (current.searchQuery != old.searchQuery ||
        current.searchCurrentIndex != old.searchCurrentIndex) {
      if (current.searchQuery != null && current.searchQuery!.isNotEmpty) {
        bridge.setSearch(
          query: current.searchQuery!,
          activeIndex: current.searchCurrentIndex,
        );
      } else {
        bridge.setSearch(query: '', activeIndex: -1);
      }
    }
  }

  void _maybeApplyInsets({
    required ChatBridgeController bridge,
    required ChatWebViewWidgetFields old,
    required ChatWebViewWidgetFields current,
  }) {
    if (current.bottomInset != old.bottomInset) {
      bridge.setBottomPadding(current.bottomInset);
    }
    if (current.topInset != old.topInset) {
      bridge.setTopPadding(current.topInset);
    }
  }

  void _maybeApplyGeneratingState({
    required ChatBridgeController bridge,
    required ChatWebViewWidgetFields old,
    required ChatWebViewWidgetFields current,
  }) {
    final anyGenerating = current.isGenerating || current.isGeneratingImage;
    final oldAnyGenerating = old.isGenerating || old.isGeneratingImage;
    if (anyGenerating != oldAnyGenerating ||
        current.isGenerating != old.isGenerating) {
      bridge.isGenerating = current.isGenerating;
      bridge.isGeneratingImage = current.isGeneratingImage;
      bridge.evalJs(
        'if (window.bridge) { window.bridge.setGenerating(${current.isGenerating}); window.bridge.isGeneratingImage = ${current.isGeneratingImage}; }',
      );
      if (!anyGenerating && current.messages.isNotEmpty) {
        bridge.setLastMessage(
          lastUserMessageId(current.messages) ?? current.messages.last.id,
        );
      } else if (current.isGenerating) {
        bridge.setLastMessage(null);
      }
    }
  }

  static bool _identityChanged({
    required ChatWebViewWidgetFields old,
    required ChatWebViewWidgetFields current,
  }) {
    return old.charName != current.charName ||
        old.charColor != current.charColor ||
        old.personaName != current.personaName ||
        old.charAvatarPath != current.charAvatarPath ||
        old.personaAvatarPath != current.personaAvatarPath ||
        old.chatLayout != current.chatLayout ||
        old.greetingTotal != current.greetingTotal;
  }
}

/// Result of a [ChatWebViewSyncDispatcher.dispatch] call.
class ChatWebViewSyncResult {
  const ChatWebViewSyncResult({
    required this.runMessageSync,
    required this.appendPlaceholder,
    required this.sessionSwitched,
    this.placeholder,
  });

  /// `true` when the caller should call
  /// [ChatMessageSync.sync] for the message list.
  final bool runMessageSync;

  /// `true` when the dispatcher wants the caller to append a
  /// streaming placeholder to the bridge. [placeholder] is the
  /// message to append (built by the widget because it needs the
  /// current timestamp + role).
  final bool appendPlaceholder;

  /// `true` when a session switch was detected. The caller handles
  /// the actual switch.
  final bool sessionSwitched;

  /// Placeholder to append when [appendPlaceholder] is `true`.
  final ChatMessage? placeholder;
}

/// Pure data snapshot of all the [ChatWebViewWidget] fields that the
/// dispatcher compares. The widget builds a snapshot for both [old]
/// and [current] on every `didUpdateWidget` so the dispatcher doesn't
/// have to reach into `widget` directly.
class ChatWebViewWidgetFields {
  const ChatWebViewWidgetFields({
    required this.charId,
    required this.charName,
    required this.charColor,
    required this.personaName,
    required this.charAvatarPath,
    required this.personaAvatarPath,
    required this.bgImagePath,
    required this.bgBlur,
    required this.bgOpacity,
    required this.bgDim,
    required this.bgNoiseOpacity,
    required this.bgNoiseIntensity,
    required this.bottomInset,
    required this.topInset,
    required this.searchQuery,
    required this.searchCurrentIndex,
    required this.chatLayout,
    required this.themeSyncKey,
    required this.elementOpacity,
    required this.elementBlur,
    required this.chatFontName,
    required this.chatFontDataUrl,
    required this.chatFontSize,
    required this.chatLetterSpacing,
    required this.isSelectionMode,
    required this.batterySaver,
    required this.hideMessageId,
    required this.hideGenerationTime,
    required this.hideTokenCount,
    required this.disableSwipeRegeneration,
    required this.memoryEntries,
    required this.memoryDrafts,
    required this.sessionId,
    required this.isGenerating,
    required this.isGeneratingImage,
    required this.regenTargetId,
    required this.greetingTotal,
    required this.messages,
    required this.buildThemeMap,
  });

  final String charId;
  final String? charName;
  final String? charColor;
  final String? personaName;
  final String? charAvatarPath;
  final String? personaAvatarPath;
  final String? bgImagePath;
  final double bgBlur;
  final double bgOpacity;
  final double bgDim;
  final double bgNoiseOpacity;
  final double bgNoiseIntensity;
  final double bottomInset;
  final double topInset;
  final String? searchQuery;
  final int searchCurrentIndex;
  final String? chatLayout;
  final String? themeSyncKey;
  final double elementOpacity;
  final double elementBlur;
  final String? chatFontName;
  final String? chatFontDataUrl;
  final double chatFontSize;
  final double chatLetterSpacing;
  final bool isSelectionMode;
  final bool batterySaver;
  final bool hideMessageId;
  final bool hideGenerationTime;
  final bool hideTokenCount;
  final bool disableSwipeRegeneration;
  final List<dynamic> memoryEntries;
  final List<dynamic> memoryDrafts;
  final String? sessionId;
  final bool isGenerating;
  final bool isGeneratingImage;
  final String? regenTargetId;
  final int greetingTotal;
  final List<ChatMessage> messages;

  /// Computes the theme map from the current widget state. Lazy
  /// because it depends on `BuildContext` and we only want to do it
  /// when a theme-affecting field actually changed.
  final Map<String, String> Function() buildThemeMap;
}
