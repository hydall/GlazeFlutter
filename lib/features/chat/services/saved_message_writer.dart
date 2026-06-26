import '../../../core/models/chat_message.dart';
import '../../../core/utils/id_generator.dart';
import '../../../core/utils/time_helpers.dart';
import '../chat_state.dart';

/// Pure-function helpers for building the final [ChatState] after one
/// generation cycle (success or error). Constructor injection of
/// pre-computed inputs (pendingSessionVars, previous swipes, etc.) so
/// this class has no dependency on Riverpod, SseClient, or the chat
/// provider. It is called by [StreamGenerationService] when the SSE
/// stream completes or errors out, and by [ChatNotifier] for regen/continue
/// rollback paths.
class SavedMessageWriter {
  const SavedMessageWriter();

  /// Success path: build the assistant message, attach swipes/meta, and
  /// return a [ChatState] with the new last message appended to the session.
  /// If [regenTargetId] is given, the message replaces the existing swipe
  /// at that id instead of appending a new one.
  ///
  /// When [studioFinalOnly] is true (regen of the final agent only), the
  /// new text is appended to `agentSwipes` as a `'final'` sub-swipe (blue
  /// icon) and the legacy `swipes[]` (green icons) is left untouched.
  /// When false (full regen or new generation), `agentSwipes` is reset to a
  /// single `'final'` swipe pointing at the new text.
  ChatState writeAssistant({
    required String text,
    required String? reasoning,
    required ChatSession currentSession,
    required bool Function() isAborted,
    Map<String, String>? pendingSessionVars,
    String? genTime,
    int? tokens,
    String? rawResponse,
    List<String>? previousSwipes,
    int previousSwipeId = 0,
    String? previousReasoning,
    String? previousGenTime,
    int? previousTokens,
    List<Map<String, dynamic>>? previousSwipesMeta,
    String? guidanceText,
    Map<String, dynamic> memoryCoverage = const {},
    bool isAllReasoning = false,
    List<TriggeredEntry> triggeredLorebooks = const [],
    List<TriggeredEntry> triggeredMemories = const [],
    List<Map<String, dynamic>> studioOutputs = const [],
    String? regenTargetId,
    bool studioFinalOnly = false,
    int visibleStartIndex = 0,
  }) {
    final persistedMemoryCoverage = stripEphemeralMemoryCoverage(
      memoryCoverage,
    );
    List<String> swipes;
    int swipeId;

    // When studioFinalOnly is true, the legacy swipes[] (green icons) stay
    // frozen — the new final-agent text goes into agentSwipes[] (blue).
    if (studioFinalOnly && previousSwipes != null && previousSwipes.isNotEmpty) {
      swipes = List<String>.from(previousSwipes);
      swipeId = previousSwipeId;
    } else if (previousSwipes != null && previousSwipes.isNotEmpty) {
      swipes = [...previousSwipes, text];
      swipeId = swipes.length - 1;
    } else {
      swipes = [text];
      swipeId = 0;
    }

    final currentSwipeMeta = <String, dynamic>{
      'genTime': genTime,
      'reasoning': reasoning,
      'tokens': tokens,
      // Persist triggered entries per swipe so each variation shows its own
      // lorebook/memory activations (restored on swipe in ChatMessageService).
      if (triggeredLorebooks.isNotEmpty)
        'triggeredLorebooks': triggeredLorebooks
            .map((e) => e.toJson())
            .toList(),
      if (triggeredMemories.isNotEmpty)
        'triggeredMemories': triggeredMemories.map((e) => e.toJson()).toList(),
      if (studioOutputs.isNotEmpty) 'studioOutputs': studioOutputs,
    };
    if (guidanceText != null && guidanceText.isNotEmpty) {
      currentSwipeMeta['guidanceText'] = guidanceText;
      currentSwipeMeta['guidanceType'] = 'GENERATION';
    }

    List<Map<String, dynamic>> swipesMeta;
    if (previousSwipesMeta != null && previousSwipesMeta.isNotEmpty) {
      swipesMeta = [...previousSwipesMeta, currentSwipeMeta];
    } else if (previousSwipes != null && previousSwipes.isNotEmpty) {
      final prevMeta = <String, dynamic>{
        'genTime': previousGenTime,
        'reasoning': previousReasoning,
        'tokens': previousTokens,
      };
      swipesMeta = List<Map<String, dynamic>>.generate(
        previousSwipes.length,
        (i) => i == previousSwipeId ? prevMeta : {},
      );
      swipesMeta.add(currentSwipeMeta);
    } else {
      swipesMeta = [currentSwipeMeta];
    }

    if (regenTargetId != null) {
      if (isAborted()) {
        return ChatState(
          session: currentSession,
          isGenerating: false,
          visibleStartIndex: visibleStartIndex,
        );
      }
      final idx = currentSession.messages.indexWhere(
        (m) => m.id == regenTargetId,
      );
      if (idx >= 0) {
        final existing = currentSession.messages[idx];

        // Nested swipes: compute agentSwipes[] (blue sub-swipes).
        // - studioFinalOnly: append a 'final' sub-swipe (regen of final
        //   agent only). Legacy swipes[] stays frozen.
        // - Full regen: reset to a single 'final' pointing at the new text.
        List<AgentSwipe> agentSwipes;
        int agentSwipeId;
        if (studioFinalOnly) {
          agentSwipes = List<AgentSwipe>.from(existing.agentSwipes);
          if (agentSwipes.isEmpty) {
            // Lazy migration: old message has no agentSwipes yet — seed
            // a 'final' from the existing content so the new regen has a
            // sibling.
            agentSwipes.add(AgentSwipe(
              content: existing.content,
              kind: 'final',
              reasoning: existing.reasoning,
              genTime: existing.genTime,
              tokens: existing.tokens,
              studioOutputs: existing.studioOutputs,
            ));
          }
          agentSwipes.add(AgentSwipe(
            content: text,
            kind: 'final',
            reasoning: reasoning,
            genTime: genTime,
            tokens: tokens,
            studioOutputs: studioOutputs,
          ));
          agentSwipeId = agentSwipes.length - 1;
        } else {
          // Full regen: replace agentSwipes with a fresh single 'final'.
          agentSwipes = [
            AgentSwipe(
              content: text,
              kind: 'final',
              reasoning: reasoning,
              genTime: genTime,
              tokens: tokens,
              studioOutputs: studioOutputs,
            ),
          ];
          agentSwipeId = 0;
        }

        final updated = existing.copyWith(
          content: text,
          reasoning: reasoning,
          isAllReasoning: isAllReasoning,
          isError: false,
          isTyping: false,
          genTime: genTime,
          tokens: tokens,
          swipes: swipes,
          swipeId: swipeId,
          swipesMeta: swipesMeta,
          swipeDirection: 'right',
          memoryCoverage: persistedMemoryCoverage,
          triggeredLorebooks: triggeredLorebooks,
          triggeredMemories: triggeredMemories,
          studioOutputs: studioOutputs,
          agentSwipes: agentSwipes,
          agentSwipeId: agentSwipeId,
        );
        final updatedMessages = [...currentSession.messages];
        updatedMessages[idx] = updated;
        final finalSession = currentSession.copyWith(
          messages: updatedMessages,
          updatedAt: currentTimestampSeconds(),
          sessionVars: pendingSessionVars ?? currentSession.sessionVars,
        );
        return ChatState(
          session: finalSession,
          lastRawResponse: rawResponse,
          regenTargetId: regenTargetId,
          visibleStartIndex: visibleStartIndex,
        );
      }
    }

    if (isAborted()) {
      return ChatState(
        session: currentSession,
        isGenerating: false,
        visibleStartIndex: visibleStartIndex,
      );
    }

    // New message: seed agentSwipes with a single 'final' pointing at
    // the new text (nested-swipes RFC §5).
    final newAgentSwipes = [
      AgentSwipe(
        content: text,
        kind: 'final',
        reasoning: reasoning,
        genTime: genTime,
        tokens: tokens,
        studioOutputs: studioOutputs,
      ),
    ];
    final assistantMsg = ChatMessage(
      id: generateId(),
      role: 'assistant',
      content: text,
      reasoning: reasoning,
      isAllReasoning: isAllReasoning,
      genTime: genTime,
      tokens: tokens,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      swipes: swipes,
      swipeId: swipeId,
      swipesMeta: swipesMeta,
      memoryCoverage: persistedMemoryCoverage,
      triggeredLorebooks: triggeredLorebooks,
      triggeredMemories: triggeredMemories,
      studioOutputs: studioOutputs,
      agentSwipes: newAgentSwipes,
      agentSwipeId: 0,
    );
    final finalMessages = [...currentSession.messages, assistantMsg];
    final now = currentTimestampSeconds();
    final sessionVars = pendingSessionVars ?? currentSession.sessionVars;
    final finalSession = currentSession.copyWith(
      messages: finalMessages,
      updatedAt: now,
      sessionVars: sessionVars,
    );
    return ChatState(
      session: finalSession,
      lastRawResponse: rawResponse,
      visibleStartIndex: visibleStartIndex,
    );
  }

  static Map<String, dynamic> stripEphemeralMemoryCoverage(
    Map<String, dynamic> coverage,
  ) {
    if (coverage.isEmpty || !coverage.containsKey('diagnostics')) {
      return coverage;
    }
    final out = Map<String, dynamic>.from(coverage);
    out.remove('diagnostics');
    return out;
  }

  /// Error path (non-regen): append an error message. Does NOT write
  /// [pendingSessionVars] — those must only persist on the success path
  /// (see INV-C5). The current session's sessionVars are kept as-is.
  /// Called from SSE onError and from the top-level catch.
  ChatState writeError({
    required String errorText,
    required ChatSession currentSession,
    int visibleStartIndex = 0,
  }) {
    final errorMsg = ChatMessage(
      id: generateId(),
      role: 'assistant',
      content: errorText,
      isError: true,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      swipes: [errorText],
      swipeId: 0,
      swipesMeta: [{}],
    );
    final finalMessages = [...currentSession.messages, errorMsg];
    final finalSession = currentSession.copyWith(
      messages: finalMessages,
      updatedAt: currentTimestampSeconds(),
    );
    return ChatState(
      session: finalSession,
      visibleStartIndex: visibleStartIndex,
    );
  }

  /// Error path (regen): replace the swipe at [regenTargetId] with the
  /// error text. Does NOT write [pendingSessionVars] (see INV-C5).
  ChatState writeRegenError({
    required String errorText,
    required ChatSession saveSession,
    required String regenTargetId,
    int visibleStartIndex = 0,
  }) {
    final idx = saveSession.messages.indexWhere((m) => m.id == regenTargetId);
    if (idx < 0) {
      return writeError(
        errorText: errorText,
        currentSession: saveSession,
        visibleStartIndex: visibleStartIndex,
      );
    }
    final original = saveSession.messages[idx];
    final errorSwipes = original.swipes.isNotEmpty
        ? [...original.swipes]
        : [original.content];
    errorSwipes.add(errorText);
    final errorSwipesMeta = original.swipesMeta.isNotEmpty
        ? [...original.swipesMeta, <String, dynamic>{}]
        : [
            <String, dynamic>{
              'genTime': original.genTime,
              'reasoning': original.reasoning,
              'tokens': original.tokens,
            },
            <String, dynamic>{},
          ];
    final updated = original.copyWith(
      content: errorText,
      isError: true,
      isTyping: false,
      swipes: errorSwipes,
      swipesMeta: errorSwipesMeta,
      swipeId: errorSwipes.length - 1,
      reasoning: null,
      genTime: null,
      tokens: null,
    );
    final finalMessages = [...saveSession.messages];
    finalMessages[idx] = updated;
    final finalSession = saveSession.copyWith(
      messages: finalMessages,
      updatedAt: currentTimestampSeconds(),
    );
    return ChatState(
      session: finalSession,
      regenTargetId: regenTargetId,
      visibleStartIndex: visibleStartIndex,
    );
  }

  /// Strip residual inline reasoning markers from streamed text. The
  /// model sometimes emits `<think>...</think>` outside the parsed
  /// reasoning block; this is a defensive cleanup.
  String sanitizeReasoningMarkers(
    String input,
    String tagStart,
    String tagEnd,
  ) {
    var s = input;
    if (tagStart.isNotEmpty) {
      s = s.replaceAll(tagStart, '');
    }
    if (tagEnd.isNotEmpty) {
      s = s.replaceAll(tagEnd, '');
    }
    s = s.replaceAll('<think>', '');
    s = s.replaceAll('</think>', '');
    s = s.replaceAll('<think>\n', '');
    s = s.replaceAll('\n</think>', '');
    s = s.replaceAll('<think> ', '');
    s = s.replaceAll(' </think>', '');
    s = s.replaceAll('<think', '');
    s = s.replaceAll('</think', '');
    s = s.replaceAll('think>', '');
    s = s.replaceAll('think\n', '');
    return s;
  }
}
