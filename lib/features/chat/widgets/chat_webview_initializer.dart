import 'dart:async';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/chat_message.dart';
import '../../../core/state/active_regex_provider.dart';
import '../../../core/state/character_provider.dart';
import '../../../core/state/persona_resolution.dart';
import '../bridge/chat_bridge_controller.dart';
import '../bridge/chat_overlay_blur_region.dart';

/// Snapshot of the [ChatWebViewWidget] fields needed by
/// [ChatWebViewInitializer]. Pure data — no `BuildContext` or
/// `WidgetRef` references — so the initializer can be unit-tested
/// without a widget tree.
class ChatWebViewInitInput {
  const ChatWebViewInitInput({
    required this.charId,
    required this.sessionId,
    required this.charName,
    required this.charColor,
    required this.personaName,
    required this.chatLayout,
    required this.charAvatarPath,
    required this.personaAvatarPath,
    required this.greetingTotal,
    required this.bgImagePath,
    required this.bgBlur,
    required this.bgOpacity,
    required this.bgNoiseOpacity,
    required this.bgNoiseIntensity,
    required this.chatFontName,
    required this.chatFontDataUrl,
    required this.chatFontSize,
    required this.chatLetterSpacing,
    required this.batterySaver,
    required this.hideMessageId,
    required this.hideGenerationTime,
    required this.hideTokenCount,
    required this.disableSwipeRegeneration,
    required this.messages,
    required this.visibleStartIndex,
    required this.memoryEntries,
    required this.memoryDrafts,
    required this.bottomInset,
    required this.topInset,
    this.blurRegions = const [],
    required this.searchQuery,
    required this.searchCurrentIndex,
    required this.isSelectionMode,
    required this.isGenerating,
    required this.isGeneratingImage,
    this.isPostGenRunning = false,
  });

  final String charId;
  final String? sessionId;
  final String? charName;
  final String? charColor;
  final String? personaName;
  final String? chatLayout;
  final String? charAvatarPath;
  final String? personaAvatarPath;
  final int greetingTotal;
  final String? bgImagePath;
  final double bgBlur;
  final double bgOpacity;
  final double bgNoiseOpacity;
  final double bgNoiseIntensity;
  final String? chatFontName;
  final String? chatFontDataUrl;
  final double chatFontSize;
  final double chatLetterSpacing;
  final bool batterySaver;
  final bool hideMessageId;
  final bool hideGenerationTime;
  final bool hideTokenCount;
  final bool disableSwipeRegeneration;
  final List<ChatMessage> messages;
  final int visibleStartIndex;
  final List<dynamic> memoryEntries;
  final List<dynamic> memoryDrafts;
  final double bottomInset;
  final double topInset;
  final List<ChatOverlayBlurRegion> blurRegions;
  final String? searchQuery;
  final int searchCurrentIndex;
  final bool isSelectionMode;
  final bool isGenerating;
  final bool isGeneratingImage;
  final bool isPostGenRunning;
}

/// One-time bridge initialisation sequence: regex context → identity →
/// theme → background noise → chat font → message settings → second
/// identity pass → messages → memory book → insets → overlays → search
/// → selection mode → scroll to bottom → initial `isGenerating` flag
/// → ext-block panel sync.
///
/// Extracted from `chat_webview_widget._initWebView` so the widget
/// only calls [run] and a small `onReady` callback. The sequence is
/// the same as before (a `setIdentity` is called twice on purpose —
/// once before and once after the theme and assets load — to
/// account for persona/character resolution that may have raced
/// with the first identity call).
class ChatWebViewInitializer {
  const ChatWebViewInitializer({
    required this.ref,
    required this.bridge,
    required this.input,
    required this.onReady,
    required this.onSyncExtBlockPanels,
    required this.applyTheme,
  });

  final WidgetRef ref;
  final ChatBridgeController bridge;
  final ChatWebViewInitInput input;
  final VoidCallback onReady;
  final Future<void> Function() onSyncExtBlockPanels;
  final Future<void> Function() applyTheme;

  /// Run the full init sequence. [onReady] is called synchronously
  /// after the last `await` completes, before the ext-block sync.
  Future<void> run() async {
    final character = ref.read(characterByIdProvider(input.charId));
    final effectivePersona = ref.read(
      effectivePersonaForChatProvider((
        charId: input.charId,
        sessionId: input.sessionId,
      )),
    );
    final displayRegexes = ref.read(displayRegexesProvider).value ?? const [];
    bridge.setRegexContext(displayRegexes, character, effectivePersona);

    await _setIdentity();
    await applyTheme();
    await bridge.setBackgroundImage(
      input.bgImagePath,
      input.bgBlur.toInt(),
      input.bgOpacity,
    );
    await bridge.setBackgroundNoise(
      input.bgNoiseOpacity,
      input.bgNoiseIntensity,
    );
    await bridge.setChatFont(
      fontName: input.chatFontName,
      fontDataUrl: input.chatFontDataUrl,
      fontSize: input.chatFontSize,
      letterSpacing: input.chatLetterSpacing,
    );
    await bridge.setMessageSettings(
      batterySaver: input.batterySaver,
      hideMessageId: input.hideMessageId,
      hideGenerationTime: input.hideGenerationTime,
      hideTokenCount: input.hideTokenCount,
      disableSwipeRegeneration: input.disableSwipeRegeneration,
    );
    // Persona/char identity can resolve while theme and assets load above.
    await _setIdentity();
    await bridge.setMessages(
      input.messages,
      visibleStartIndex: input.visibleStartIndex,
    );
    bridge.updateMemoryBookData(
      entries: input.memoryEntries
          .map((e) => {'status': e.status, 'messageIds': e.messageIds})
          .toList(),
      pendingDrafts: input.memoryDrafts
          .map((e) => {'messageIds': e.messageIds})
          .toList(),
    );
    if (input.bottomInset > 0) {
      await bridge.setBottomPadding(input.bottomInset);
    }
    if (input.topInset > 0) {
      await bridge.setTopPadding(input.topInset);
    }
    if (input.blurRegions.isNotEmpty) {
      await bridge.setOverlayBlurRegions(input.blurRegions);
    }
    if (input.searchQuery != null && input.searchQuery!.isNotEmpty) {
      await bridge.setSearch(
        query: input.searchQuery!,
        activeIndex: input.searchCurrentIndex,
      );
    }
    await bridge.setSelectionMode(input.isSelectionMode);
    await bridge.scrollToBottom();
    final initialAnyGen =
        input.isGenerating || input.isGeneratingImage || input.isPostGenRunning;
    bridge.isGenerating = initialAnyGen;
    unawaited(
      bridge.evalJs(
        'if (window.bridge) window.bridge.isGenerating = $initialAnyGen;',
      ),
    );
    onReady();

    // Push initial ext-block panels on first load.
    unawaited(onSyncExtBlockPanels());
  }

  Future<void> _setIdentity() {
    return bridge.setIdentity(
      charName: input.charName,
      charColor: input.charColor,
      personaName: input.personaName,
      layout: input.chatLayout,
      charAvatarPath: input.charAvatarPath,
      personaAvatarPath: input.personaAvatarPath,
      greetingTotal: input.greetingTotal,
    );
  }
}
