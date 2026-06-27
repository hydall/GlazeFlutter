import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/llm/prompt_builder.dart' show PromptPayload;
import '../../../core/models/chat_message.dart';
import '../../../core/models/character.dart';
import '../../../core/models/agent_operation_record.dart';
import '../../../core/llm/memory_draft_planner.dart';
import '../../../core/llm/memory_agentic_service.dart';
import '../../../core/state/memory_agent_providers.dart';
import '../../../core/state/memory_settings_provider.dart';
import '../../../core/services/generation_notification_service.dart';
import '../../../core/state/db_provider.dart';
import '../../../core/utils/time_helpers.dart';
import '../../cloud_sync/sync_provider.dart' show notifySyncMessageGenerated;
import '../../chat_history/chat_history_provider.dart';
import '../abort_handler.dart';
import '../chat_generation_service.dart';
import '../chat_provider.dart' show streamingStateProvider;
import '../chat_session_service.dart';
import '../chat_state.dart';
import '../state/agent_operations_log_provider.dart';
import '../state/post_cleaner_state_provider.dart';
import '../utils/message_preview.dart';

/// Result of [GenerationPipeline.run] when the regen target's id did not
/// match what the service wrote back (e.g. a stale completion after a new
/// generation started, or an abort mid-pipeline).
class GenerationOutcome {
  /// Final state to apply to the [ChatNotifier] state. May already include
  /// the rolled-back session, depending on the path.
  final ChatState state;

  /// If non-null, the [AbortHandler] should keep its restoration snapshot
  /// for the next abort. If null, restoration has been consumed.
  final ChatMessage? clearRestorationMessage;

  const GenerationOutcome({required this.state, this.clearRestorationMessage});
}

/// Runs the post-SSE side of a chat generation:
///   1. persist the service result (success path)
///   2. handle regen rollback if the service's regenTargetId does not match
///   3. handle restoration rollback if `abortHandler.restorationMessage` is set
///   4. clear `restorationMessage` and chat image `imgGenCancelToken`
///   5. kick off [ChatGenerationService.processImageTags]
///   6. kick off [ChatGenerationService.processExtensions]
///   7. notify sync, fire foreground notification preview
///
/// This class is a thin orchestrator — no business logic, no state ownership.
/// Constructor-injected dependencies: the [Ref] (for repo/provider reads),
/// the [AbortHandler] (for genId + restoration tracking), and the [ChatState]
/// at the moment the run started.
class GenerationPipeline {
  final Ref ref;
  final String charId;
  final AbortHandler abortHandler;
  final void Function(AsyncValue<ChatState>) setState;
  final AsyncValue<ChatState> Function() getState;

  GenerationPipeline({
    required this.ref,
    required this.charId,
    required this.abortHandler,
    required this.setState,
    required this.getState,
  });

  /// Run the full post-SSE pipeline. Returns the final [GenerationOutcome]
  /// describing the state to apply, or null if the genId was invalidated
  /// (caller should drop the result).
  Future<GenerationOutcome?> run({
    required int genId,
    required ChatSession session,
    required ChatSession? saveSession,
    required String? guidanceText,
    required List<String>? previousSwipes,
    int previousSwipeId = 0,
    String? previousReasoning,
    String? previousGenTime,
    int? previousTokens,
    List<Map<String, dynamic>>? previousSwipesMeta,
    String? regenTargetId,
  }) async {
    if (!ref.mounted) return null;
    abortHandler.clearStreaming();

    final notifService = GenerationNotificationService.instance;
    final charRepo = ref.read(characterRepoProvider);
    final character = await charRepo.getById(charId);
    if (!ref.mounted || !abortHandler.isCurrentGen(genId)) return null;
    await notifService.onGenerationStarted(character?.name ?? 'Unknown');
    if (!ref.mounted || !abortHandler.isCurrentGen(genId)) return null;

    try {
      final service = ref.read(chatGenerationServiceProvider);
      final result = await service.generate(
        session: session,
        saveSession: saveSession,
        charId: charId,
        genId: genId,
        currentState: getState().value ?? ChatState(session: session),
        onStateUpdate: (s) {
          if (abortHandler.isCurrentGen(genId)) setState(AsyncData(s));
        },
        isAborted: () => !abortHandler.isCurrentGen(genId),
        previousSwipes: previousSwipes,
        previousSwipeId: previousSwipeId,
        previousReasoning: previousReasoning,
        previousGenTime: previousGenTime,
        previousTokens: previousTokens,
        previousSwipesMeta: previousSwipesMeta,
        guidanceText: guidanceText,
        regenTargetId: regenTargetId,
      );

      if (!ref.mounted || !abortHandler.isCurrentGen(genId)) {
        return null;
      }

      if (result.session != null) {
        await ref.read(chatRepoProvider).put(result.session!);
        if (!ref.mounted || !abortHandler.isCurrentGen(genId)) return null;
        ChatSessionService.updateCache(result.session!);
        ref.invalidate(chatHistoryProvider);
      }

      // Regen vs normal-result dispatch.
      final regenMsg = regenTargetId != null && result.session != null
          ? result.session!.messages
                .where((m) => m.id == regenTargetId)
                .firstOrNull
          : null;
      final regenSucceeded =
          regenTargetId != null &&
          regenMsg != null &&
          !regenMsg.isError &&
          !regenMsg.isTyping;
      final regenOutcome = _resolveRegenResult(
        result: result,
        regenTargetId: regenTargetId,
        saveSession: saveSession,
        session: session,
      );
      if (regenOutcome != null) {
        // INV-EG1: extensions + image tags must run after successful regen too.
        if (regenSucceeded && result.session != null) {
          await _runPostTextSide(
            result: result.copyWith(isGenerating: false, regenTargetId: null),
            genId: genId,
            character: character,
            service: service,
            notifService: notifService,
          );
          if (!ref.mounted || !abortHandler.isCurrentGen(genId)) {
            return null;
          }

          // POST-cleaner on regen: run after successful regen. The cleaner
          // rewrites the regenerated assistant message, preserving the
          // original as a swipe.
          unawaited(
            _runPostCleaner(
              sessionId: result.session!.id,
              messages: result.session!.messages,
              genId: genId,
              promptPayload: result.promptPayload,
            ),
          );
        }
        return regenOutcome;
      }

      // Normal path: regen not requested. Handle restoration snapshot if set.
      if (regenTargetId == null &&
          result.session?.messages.length == session.messages.length &&
          abortHandler.restorationMessage != null) {
        final restoredMessages = [
          ...session.messages,
          abortHandler.restorationMessage!,
        ];
        final restoredSession = session.copyWith(
          messages: restoredMessages,
          updatedAt: currentTimestampSeconds(),
        );
        await ref.read(chatRepoProvider).put(restoredSession);
        ChatSessionService.updateCache(restoredSession);
        ref.invalidate(chatHistoryProvider);
        abortHandler.restorationMessage = null;
        setState(
          AsyncData(
            ChatState(
              session: restoredSession,
              isGenerating: false,
              error: result.error,
            ),
          ),
        );
      } else {
        setState(AsyncData(result));
        abortHandler.restorationMessage = null;
      }
      abortHandler.clearStreaming();

      // Post-text side: image tags, extensions, sync, notification.
      await _runPostTextSide(
        result: result,
        genId: genId,
        character: character,
        service: service,
        notifService: notifService,
      );

      if (!abortHandler.isCurrentGen(genId)) {
        return null;
      }

      await _autoCreateMemoryDrafts(result.session);

      // Stage 2: Agentic write-loop — only on accepted (non-regen) turns.
      // Suppressed on swipe/regen to avoid duplicate or contradictory writes
      // (the user may swipe again). The regen branch above (regenOutcome !=
      // null) returns early before reaching here, so this code only runs on
      // the normal send-message path.
      if (regenTargetId == null && result.session != null) {
        unawaited(
          _runAgenticWriteLoop(
            sessionId: result.session!.id,
            messages: result.session!.messages,
            genId: genId,
          ),
        );

        // Stage 4: POST-cleaner — silently rewrite the final assistant
        // message to remove clichés/repetition. Fire-and-forget; falls back
        // to original text on error. Original preserved as a swipe.
        unawaited(
          _runPostCleaner(
            sessionId: result.session!.id,
            messages: result.session!.messages,
            genId: genId,
            promptPayload: result.promptPayload,
          ),
        );
      }

      return GenerationOutcome(
        state: getState().value ?? result,
        clearRestorationMessage: null,
      );
    } catch (e) {
      await _handlePipelineError(e, genId, notifService);
      return null;
    }
  }

  /// Returns the final state to apply if [regenTargetId] was set, or null
  /// to fall through to the normal-result path. Encapsulates the regen
  /// success / rollback / no-restoration branches.
  GenerationOutcome? _resolveRegenResult({
    required ChatState result,
    required String? regenTargetId,
    required ChatSession? saveSession,
    required ChatSession session,
  }) {
    if (regenTargetId == null) return null;

    if (result.regenTargetId == regenTargetId) {
      setState(
        AsyncData(result.copyWith(isGenerating: false, regenTargetId: null)),
      );
      abortHandler.restorationMessage = null;
      return GenerationOutcome(
        state: getState().value ?? result,
        clearRestorationMessage: null,
      );
    }

    final original = abortHandler.restorationMessage;
    if (original == null) {
      setState(
        AsyncData(result.copyWith(isGenerating: false, regenTargetId: null)),
      );
      return GenerationOutcome(
        state: getState().value ?? result,
        clearRestorationMessage: null,
      );
    }

    final restoreSession = saveSession ?? session;
    final idx = restoreSession.messages.indexWhere(
      (m) => m.id == regenTargetId,
    );
    if (idx < 0) {
      setState(
        AsyncData(result.copyWith(isGenerating: false, regenTargetId: null)),
      );
      abortHandler.restorationMessage = null;
      return GenerationOutcome(
        state: getState().value ?? result,
        clearRestorationMessage: null,
      );
    }

    final rollbackSwipes = original.swipes.isNotEmpty
        ? original.swipes
        : [original.content];
    final rollbackSwipesMeta = original.swipesMeta.isNotEmpty
        ? original.swipesMeta
        : [
            <String, dynamic>{
              'genTime': original.genTime,
              'reasoning': original.reasoning,
              'tokens': original.tokens,
            },
          ];
    final restored = restoreSession.messages[idx].copyWith(
      content: original.content,
      swipeId: original.swipeId,
      swipes: rollbackSwipes,
      reasoning: original.reasoning,
      genTime: original.genTime,
      tokens: original.tokens,
      swipesMeta: rollbackSwipesMeta,
      swipeDirection: original.swipeDirection,
      isTyping: false,
      isError: false,
    );
    final restoredMessages = [...restoreSession.messages];
    restoredMessages[idx] = restored;
    final restoredSession = session.copyWith(
      messages: restoredMessages,
      updatedAt: currentTimestampSeconds(),
    );
    // Note: persist is fire-and-forget here; full sync lives in the
    // caller's pre-save path.
    // ignore: unawaited_futures
    ref.read(chatRepoProvider).put(restoredSession).catchError((Object e) {
      debugPrint('[GenerationPipeline] failed to persist restored session: $e');
    });
    ChatSessionService.updateCache(restoredSession);
    ref.invalidate(chatHistoryProvider);
    abortHandler.restorationMessage = null;
    setState(
      AsyncData(
        ChatState(
          session: restoredSession,
          isGenerating: false,
          error: result.error,
          regenTargetId: null,
        ),
      ),
    );
    return GenerationOutcome(
      state: getState().value ?? result,
      clearRestorationMessage: null,
    );
  }

  Future<void> _runPostTextSide({
    required ChatState result,
    required int genId,
    required Character? character,
    required ChatGenerationService service,
    required GenerationNotificationService notifService,
  }) async {
    final imgCancelToken = CancelToken();
    abortHandler.imgGenCancelToken = imgCancelToken;

    try {
      await service.processImageTags(
        currentState: result,
        charId: charId,
        cancelToken: imgCancelToken,
        onStateUpdate: (s) {
          if (abortHandler.isCurrentGen(genId)) setState(AsyncData(s));
        },
      );
      if (!ref.mounted || !abortHandler.isCurrentGen(genId)) return;
    } catch (e) {
      debugPrint(
        '[GenerationPipeline] processImageTags failed (continuing): $e',
      );
    } finally {
      if (identical(abortHandler.imgGenCancelToken, imgCancelToken)) {
        abortHandler.imgGenCancelToken = null;
      }
    }

    final lastMessage = result.session?.messages.lastOrNull;
    final hasGenerationError = lastMessage?.isError == true;

    if (character != null && result.session != null && !hasGenerationError) {
      await service.processExtensions(
        charId: charId,
        session: result.session!,
        character: character,
      );
      if (!ref.mounted || !abortHandler.isCurrentGen(genId)) return;
    }

    if (!ref.mounted || !abortHandler.isCurrentGen(genId)) return;

    notifySyncMessageGenerated(ref);

    final preview = buildMessagePreview(result.session?.messages ?? const []);
    await notifService.onGenerationCompleted(
      character?.name ?? 'Unknown',
      charId,
      messagePreview: preview,
      sessionId: result.session?.id,
      msgId: result.session?.messages.isNotEmpty == true
          ? result.session!.messages.last.id
          : null,
      avatarPath: character?.avatarPath,
    );
  }

  Future<void> _handlePipelineError(
    Object e,
    int genId,
    GenerationNotificationService notifService,
  ) async {
    if (!ref.mounted) return;
    if (!abortHandler.isCurrentGen(genId)) {
      await notifService.onGenerationAborted();
      return;
    }
    final current = getState().value;
    if (current != null && current.isGenerating) {
      final restoration = abortHandler.restorationMessage;
      if (restoration != null) {
        final msgs = <ChatMessage>[
          ...(current.session?.messages ?? const <ChatMessage>[]),
          restoration,
        ];
        final restored = current.session?.copyWith(
          messages: msgs,
          updatedAt: currentTimestampSeconds(),
        );
        if (restored != null) {
          // ignore: unawaited_futures
          ref.read(chatRepoProvider).put(restored).catchError((Object err) {
            debugPrint('[GenerationPipeline] failed to persist restored: $err');
          });
          ChatSessionService.updateCache(restored);
        }
        setState(
          AsyncData(
            current.copyWith(
              session: restored ?? current.session,
              isGenerating: false,
              error: e.toString(),
            ),
          ),
        );
      } else {
        setState(
          AsyncData(current.copyWith(isGenerating: false, error: e.toString())),
        );
      }
      abortHandler.restorationMessage = null;
    }
    await notifService.onGenerationAborted();
  }

  Future<void> _autoCreateMemoryDrafts(ChatSession? session) async {
    if (!ref.mounted) return;
    if (session == null) return;
    final settings = ref.read(memoryGlobalSettingsProvider);
    if (!settings.enabled || !settings.autoCreateEnabled) return;

    try {
      final repo = ref.read(memoryBookRepoProvider);
      final book = await repo.ensureForSession(session.id);
      if (!ref.mounted) return;
      final plan = MemoryDraftPlanner.plan(
        book: book,
        messages: session.messages,
        interval: settings.autoCreateInterval,
        lagMessages: settings.autoCreateLagMessages,
        source: 'auto_create',
        nowMillis: DateTime.now().millisecondsSinceEpoch,
      );
      if (plan.drafts.isEmpty) return;

      await repo.put(
        book.copyWith(pendingDrafts: [...book.pendingDrafts, ...plan.drafts]),
      );
    } catch (e) {
      debugPrint('[GenerationPipeline] auto-create memory drafts failed: $e');
    }
  }

  /// Stage 2: Agentic write-loop trigger.
  ///
  /// Fire-and-forget — does not block generation or user interaction.
  /// Only called on the normal (non-regen) path, after the assistant message
  /// is persisted to DB. Reads MemoryBook settings to check
  /// `agenticWriteEnabled`, fetches current trackers, extracts recent history
  /// text, and delegates to [MemoryAgenticService.runWriteLoop].
  ///
  /// Staleness guard: checks `abortHandler.isCurrentGen(genId)` before
  /// executing writes (after the LLM call returns). The write-loop itself
  /// creates its own CancelToken and checks it after each await.
  Future<void> _runAgenticWriteLoop({
    required String sessionId,
    required List<ChatMessage> messages,
    required int genId,
  }) async {
    if (!ref.mounted) return;

    try {
      final bookRepo = ref.read(memoryBookRepoProvider);
      final book = await bookRepo.getBySessionId(sessionId);
      if (!ref.mounted || !abortHandler.isCurrentGen(genId)) return;
      final pipeline = await ref.read(
        pipelineSettingsProvider(sessionId).future,
      );
      if (!ref.mounted || !abortHandler.isCurrentGen(genId)) return;
      if (book == null || !pipeline.agenticWriteEnabled) return;

      // Read the current tracker state from snapshots (preferred) with a
      // tracker_rows fallback for legacy sessions pre-migration. The write-loop
      // runs on the non-regen path, so getLatestCommitted is the correct base.
      final snapshotRepo = ref.read(trackerSnapshotRepoProvider);
      final trackerRepo = ref.read(trackerRepoProvider);
      final snapshot = await snapshotRepo.getLatestCommitted(sessionId);
      final trackers =
          snapshot?.trackers ?? await trackerRepo.getBySessionId(sessionId);
      if (!ref.mounted || !abortHandler.isCurrentGen(genId)) return;

      final recentHistory = extractRecentHistoryText(messages, maxMessages: 10);

      // Anchor for the tracker snapshot: the just-finished assistant turn.
      // The write-loop only fires on the non-regen path (line 228), so the
      // last message is the freshly-generated assistant reply with
      // swipeId=0 and agentSwipeId=0 (SavedMessageWriter seeds a single
      // 'final'). Guard against non-assistant trailing messages defensively.
      final lastAssistant = messages.lastWhere(
        (m) => m.role == 'assistant',
        orElse: () => messages.last,
      );

      debugPrint(
        '[AgenticWrite] starting write-loop session=$sessionId '
        'model=${pipeline.sidecarModel.isEmpty ? "<chat>" : pipeline.sidecarModel} '
        'timeoutMs=${pipeline.sidecarTimeoutMs} '
        'existingTrackers=${trackers.length} '
        'historyChars=${recentHistory.length}',
      );

      final agenticService = ref.read(memoryAgenticWriteServiceProvider);
      final result = await agenticService.runWriteLoop(
        sessionId: sessionId,
        settings: pipeline,
        recentHistoryText: recentHistory,
        currentTrackers: trackers,
        messageId: lastAssistant.id,
        swipeId: lastAssistant.swipeId,
        agentSwipeId: lastAssistant.agentSwipeId,
        isStillCurrent: () => ref.mounted && abortHandler.isCurrentGen(genId),
      );

      debugPrint(
        '[AgenticWrite] result session=$sessionId status=${result.status} '
        'trackersWritten=${result.trackerResult?.written ?? 0} '
        'trackersDenied=${result.trackerResult?.denied ?? 0} '
        'memoriesWritten=${result.memoryResult?.written ?? 0} '
        'error=${result.error ?? "none"}',
      );

      // Record the agentic write-loop in the operations log so the user
      // can inspect retries (e.g. 502 → 200) from the Agentic Ops UI.
      if (result.status != 'disabled' && result.attempts.isNotEmpty) {
        final status = _agenticWriteStatusToOp(result.status);
        final totalWritten = result.totalWritten;
        ref.read(agentOperationsLogProvider.notifier).state = ref
            .read(agentOperationsLogProvider)
            .append(
              AgentOperationRecord(
                id: 'agentic-write-$sessionId-${DateTime.now().microsecondsSinceEpoch}',
                kind: AgentOperationKind.agenticWrite,
                status: status,
                sessionId: sessionId,
                messageId: messages.isNotEmpty ? messages.last.id : null,
                attempts: result.attempts,
                totalElapsedMs: result.totalElapsedMs,
                model: pipeline.sidecarModel.isEmpty
                    ? null
                    : pipeline.sidecarModel,
                summary: status == AgentOperationStatus.ok
                    ? (totalWritten > 0
                          ? 'wrote $totalWritten item${totalWritten > 1 ? 's' : ''}'
                          : 'no changes')
                    : result.status,
                startedAtMs: result.attempts.first.startedAtMs,
                finishedAtMs:
                    result.attempts.last.startedAtMs +
                    result.attempts.last.elapsedMs,
                canRegenerate: status.isFailure,
              ),
            );
      }
    } catch (e) {
      debugPrint('[AgenticWrite] failed session=$sessionId error=$e');
    }
  }

  /// Stage 4: POST-cleaner trigger.
  ///
  /// Fire-and-forget — silently rewrites the last assistant message to
  /// remove clichés/repetition. Only runs on the normal (non-regen) path.
  /// Reads MemoryBook settings to check `postCleanerEnabled`. Falls back to
  /// original text on any error. The original is preserved as a swipe.
  ///
  /// Staleness guard: checks `abortHandler.isCurrentGen(genId)` before
  /// applying the cleaned text.
  Future<void> _runPostCleaner({
    required String sessionId,
    required List<ChatMessage> messages,
    required int genId,
    PromptPayload? promptPayload,
  }) async {
    if (!ref.mounted) return;

    try {
      final bookRepo = ref.read(memoryBookRepoProvider);
      final book = await bookRepo.getBySessionId(sessionId);
      if (!ref.mounted || !abortHandler.isCurrentGen(genId)) return;
      final pipeline = await ref.read(
        pipelineSettingsProvider(sessionId).future,
      );
      if (!ref.mounted || !abortHandler.isCurrentGen(genId)) return;
      if (book == null || !pipeline.postCleanerEnabled) return;

      // Find the last assistant message.
      ChatMessage? lastAssistant;
      int lastAssistantIndex = -1;
      for (var i = messages.length - 1; i >= 0; i--) {
        if (messages[i].role == 'assistant' &&
            !messages[i].isError &&
            !messages[i].isTyping &&
            messages[i].content.trim().isNotEmpty) {
          lastAssistant = messages[i];
          lastAssistantIndex = i;
          break;
        }
      }
      if (lastAssistant == null) return;

      // Collect bounded recent chat history before the assistant response for
      // conservative local continuity checks. Uses configurable history window
      // from settings. Excludes the response being cleaned itself.
      final maxHistory = pipeline.postCleanerContinuityEnabled
          ? pipeline.postCleanerHistoryMessages
          : 0;
      final recentMessages = <ChatMessage>[];
      if (maxHistory > 0 && lastAssistantIndex > 0) {
        final start = (lastAssistantIndex - maxHistory).clamp(
          0,
          lastAssistantIndex,
        );
        for (var i = start; i < lastAssistantIndex; i++) {
          final m = messages[i];
          if (m.content.trim().isEmpty || m.isError) continue;
          recentMessages.add(m);
        }
      }

      // Load broadcast blocks (output language + prose guards) captured at
      // Studio build time so the cleaner applies the user's own rules instead
      // of a hardcoded English-only cliché list. Absent (no Studio) = defaults.
      List<String> broadcastBlocks = const [];
      try {
        final studioConfig = await ref
            .read(studioConfigRepoProvider)
            .getBySessionId(sessionId);
        broadcastBlocks = studioConfig?.broadcastBlocks ?? const [];
      } catch (e) {
        debugPrint(
          '[PostCleaner] broadcast load failed session=$sessionId error=$e',
        );
      }
      if (!ref.mounted || !abortHandler.isCurrentGen(genId)) return;

      debugPrint(
        '[PostCleaner] starting session=$sessionId '
        'model=${pipeline.postCleanerModel.isNotEmpty ? pipeline.postCleanerModel : (pipeline.sidecarModel.isEmpty ? "<chat>" : pipeline.sidecarModel)} '
        'timeoutMs=${pipeline.postCleanerTimeoutMs > 0 ? pipeline.postCleanerTimeoutMs : pipeline.sidecarTimeoutMs} '
        'textChars=${lastAssistant.content.length} '
        'broadcastBlocks=${broadcastBlocks.length} '
        'historyMessages=${recentMessages.length} '
        'continuity=${pipeline.postCleanerContinuityEnabled} '
        'charCheck=${pipeline.postCleanerCharacterCheckEnabled}',
      );

      ref
          .read(postCleanerStateProvider.notifier)
          .state = PostCleanerState.running(
        sessionId: sessionId,
        messageId: lastAssistant.id,
        originalChars: lastAssistant.content.length,
      );

      final cleanerService = ref.read(postCleanerServiceProvider);

      // Pass 0: Character/World Auditor (diagnostic, optional). Runs only when
      // characterCheckEnabled AND promptPayload is available (exact generation
      // snapshot). Returns null on failure → cleaner runs without audit notes.
      List<String>? auditIssues;
      if (pipeline.postCleanerCharacterCheckEnabled && promptPayload != null) {
        try {
          final loreContent = _assembleLorebooksContent(promptPayload);
          auditIssues = await cleanerService.runCharacterAudit(
            assistantText: lastAssistant.content,
            character: promptPayload.character,
            persona: promptPayload.persona,
            lorebooksContent: loreContent,
            memoryContent:
                promptPayload.memoryContent ?? promptPayload.memoryMacroContent,
            summaryContent: promptPayload.summaryContent,
            arcContent: promptPayload.arcContent,
            entitiesContent: promptPayload.entitiesContent,
            recentMessages: recentMessages,
            settings: pipeline,
          );
          if (!ref.mounted || !abortHandler.isCurrentGen(genId)) {
            ref.read(postCleanerStateProvider.notifier).state =
                const PostCleanerState.idle();
            return;
          }
          debugPrint(
            '[PostCleaner] audit session=$sessionId '
            'issues=${auditIssues?.length ?? "null(skipped)"}',
          );
        } catch (e) {
          debugPrint('[PostCleaner] audit failed session=$sessionId error=$e');
          auditIssues = null;
        }
      }

      final result = await cleanerService.runCleaner(
        sessionId: sessionId,
        settings: pipeline,
        assistantText: lastAssistant.content,
        broadcastBlocks: broadcastBlocks,
        recentMessages: recentMessages,
        auditIssues: auditIssues,
        onCleanedChunk: (text) {
          if (!ref.mounted || !abortHandler.isCurrentGen(genId)) return;
          // Stream the cleaner's rewrite into the last assistant message in
          // the WebView. targetMessageId makes _listenStreaming update the
          // existing bubble's content in place (like regen) instead of
          // creating a new virtual streaming message. The original text is
          // preserved in the DB until applyCleanedText finalizes — at that
          // point a new swipe is appended and the original becomes the
          // previous swipe.
          ref.read(streamingStateProvider(charId).notifier).state =
              StreamingState(text: text, targetMessageId: lastAssistant!.id);
        },
      );

      if (!ref.mounted || !abortHandler.isCurrentGen(genId)) {
        ref.read(postCleanerStateProvider.notifier).state =
            const PostCleanerState.idle();
        return;
      }

      debugPrint(
        '[PostCleaner] result session=$sessionId wasCleaned=${result.wasCleaned} '
        'origChars=${lastAssistant.content.length} '
        'cleanedChars=${result.cleanedText.length} '
        'error=${result.error ?? "none"} '
        'attempts=${result.attempts.length}',
      );

      ref.read(postCleanerStateProvider.notifier).state = result.wasCleaned
          ? PostCleanerState.done(
              sessionId: sessionId,
              messageId: lastAssistant.id,
              originalChars: lastAssistant.content.length,
              cleanedChars: result.cleanedText.length,
            )
          : (result.status == 'ok' || result.status == 'disabled')
          ? const PostCleanerState.idle()
          : PostCleanerState.error(
              sessionId: sessionId,
              messageId: lastAssistant.id,
            );

      // Record the operation in the agentic operations log so the user can
      // inspect retries (502 → 200, etc.) from the dedicated UI.
      ref.read(agentOperationsLogProvider.notifier).state = ref
          .read(agentOperationsLogProvider)
          .append(
            AgentOperationRecord(
              id: 'cleaner-${lastAssistant.id}-${DateTime.now().microsecondsSinceEpoch}',
              kind: AgentOperationKind.postCleaner,
              status: _cleanerStatusToOp(result.status),
              sessionId: sessionId,
              messageId: lastAssistant.id,
              attempts: result.attempts,
              totalElapsedMs: result.totalElapsedMs,
              model: pipeline.sidecarModel.isEmpty
                  ? null
                  : pipeline.sidecarModel,
              summary: result.wasCleaned
                  ? 'cleaned (${result.cleanedText.length} chars)'
                  : result.status == 'ok'
                  ? 'no change'
                  : result.status,
              startedAtMs: result.attempts.isNotEmpty
                  ? result.attempts.first.startedAtMs
                  : DateTime.now().millisecondsSinceEpoch,
              finishedAtMs: result.attempts.isNotEmpty
                  ? result.attempts.last.startedAtMs +
                        result.attempts.last.elapsedMs
                  : DateTime.now().millisecondsSinceEpoch,
              canRegenerate:
                  result.status == 'timeout' ||
                  result.status == 'error' ||
                  result.status == 'skipped',
            ),
          );

      if (!result.wasCleaned) {
        // Cleaned text equals original (no change). Reset the streaming state
        // we may have populated during the stream so the bubble doesn't stay
        // flagged isTyping.
        if (ref.mounted) {
          ref.read(streamingStateProvider(charId).notifier).state =
              const StreamingState();
        }
        return;
      }

      await cleanerService.applyCleanedText(
        sessionId: sessionId,
        messageId: lastAssistant.id,
        cleanedText: result.cleanedText,
      );

      // Reset the streaming state so the WebView stops treating the bubble
      // as isTyping. The chatHistoryProvider invalidate below pushes the
      // finalized message (with the new cleaned swipe) to the WebView.
      if (ref.mounted) {
        ref.read(streamingStateProvider(charId).notifier).state =
            const StreamingState();
      }

      // Refresh ChatNotifier state so the UI picks up the new swipe
      // immediately without requiring the user to re-enter the chat.
      // applyCleanedText writes to DB + invalidates chatHistoryProvider,
      // but ChatNotifier holds its own ChatState copy that must be pushed.
      // Note: we do NOT check isCurrentGen here — the cleaner may run
      // after a regen, and the UI must always reflect the cleaned swipe.
      if (ref.mounted) {
        final refreshed = await ref.read(chatRepoProvider).getById(sessionId);
        if (refreshed != null) {
          ChatSessionService.updateCache(refreshed);
          final current = getState().value;
          if (current != null) {
            setState(
              AsyncData(
                current.copyWith(session: refreshed, isGenerating: false),
              ),
            );
          }
          ref.invalidate(chatHistoryProvider);
        }
      }
    } catch (e) {
      debugPrint('[PostCleaner] failed session=$sessionId error=$e');
      if (ref.mounted) {
        // Reset any partial stream so the bubble doesn't stay isTyping.
        ref.read(streamingStateProvider(charId).notifier).state =
            const StreamingState();
        ref.read(postCleanerStateProvider.notifier).state =
            const PostCleanerState.idle();
      }
    }
  }
}

/// Extracts recent conversation as plain text for the agentic write-loop
/// prompt. Format: "Role: content" per line, last [maxMessages] messages.
/// Skips error, typing, and empty-content messages.
@visibleForTesting
String extractRecentHistoryText(
  List<ChatMessage> messages, {
  int maxMessages = 10,
}) {
  final start = messages.length > maxMessages
      ? messages.length - maxMessages
      : 0;
  final recent = messages.sublist(start);
  final lines = <String>[];
  for (final msg in recent) {
    if (msg.isError || msg.isTyping) continue;
    final role = msg.role == 'assistant' ? 'Assistant' : 'User';
    final content = msg.content.trim();
    if (content.isEmpty) continue;
    lines.add('$role: $content');
  }
  return lines.join('\n\n');
}

/// Maps a [PostCleanerResult] status string to the operations-log enum.
AgentOperationStatus _cleanerStatusToOp(String status) {
  return switch (status) {
    'ok' => AgentOperationStatus.ok,
    'skipped' => AgentOperationStatus.invalidOutput,
    'disabled' => AgentOperationStatus.disabled,
    'aborted' => AgentOperationStatus.aborted,
    'timeout' => AgentOperationStatus.timeout,
    'error' => AgentOperationStatus.error,
    _ => AgentOperationStatus.error,
  };
}

/// Maps a [MemoryWriteLoopResult] status string to the operations-log enum.
AgentOperationStatus _agenticWriteStatusToOp(String status) {
  return switch (status) {
    'ok' => AgentOperationStatus.ok,
    'disabled' => AgentOperationStatus.disabled,
    'aborted' => AgentOperationStatus.aborted,
    'timeout' => AgentOperationStatus.timeout,
    'error' => AgentOperationStatus.httpError,
    'invalid_output' => AgentOperationStatus.invalidOutput,
    _ => AgentOperationStatus.error,
  };
}

/// Assembles a plain-text lorebook context snapshot from the [PromptPayload]
/// for the auditor. Combines vector entries (already retrieved, with content)
/// and pre-scanned keyword entries (if available). This is a simpler assembly
/// than the full prompt builder's `_classifyLorebooks` — the auditor only needs
/// the facts, not the precise positioning/formatting.
String? _assembleLorebooksContent(PromptPayload payload) {
  final blocks = <String>[];

  // Pre-scanned keyword entries (from buildFromSession path).
  final preScanned = payload.preScannedEntries;
  if (preScanned != null) {
    for (final e in preScanned) {
      final content = e.content.trim();
      if (content.isEmpty) continue;
      final name = e.comment.isNotEmpty ? e.comment : e.id;
      blocks.add('[${e.lorebookName}] $name:\n$content');
    }
  }

  // Vector entries (from buildFromPreFetched / deep mode).
  for (final e in payload.vectorEntries) {
    final content = e.content.trim();
    if (content.isEmpty) continue;
    final name = e.comment.isNotEmpty ? e.comment : e.id;
    blocks.add('[vector] $name:\n$content');
  }

  if (blocks.isEmpty) return null;
  return blocks.join('\n\n');
}
