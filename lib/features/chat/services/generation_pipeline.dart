import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/llm/prompt_builder.dart' show PromptPayload;
import '../../../core/llm/tokenizer.dart';
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

  /// Latest accumulated chunk from the cleaner's onCleanedChunk callback.
  /// Captured so we can persist partial text when the cleaner fails
  /// mid-stream (Fix 1): SidecarCallOutcome.text is null on any failure, so
  /// the partial text the user saw live is only reachable via the callback.
  /// Reset in `_runPostCleaner`'s finally block.
  String _lastStreamedText = '';

  /// The agent-swipe id of the blue 'cleaned' swipe pre-created at cleaner
  /// start (Fix 1). `-1` when no pre-created swipe exists. Reset in the
  /// finally block so a stale id never leaks into the next run.
  int _preCreatedCleanerSwipeId = -1;

  /// The message id the pre-created swipe belongs to (tracked so the catch
  /// block can remove the swipe on a hard pipeline failure, when
  /// `lastAssistant` is out of scope).
  String? _preCreatedMessageId;

  /// Cancel token for the parallel character-audit call (Feature 3). On the
  /// race-loser path the audit Future outlives the cleaner; this lets the
  /// `finally` block cancel the orphaned LLM request. `null` when no audit
  /// is in flight.
  CancelToken? _auditCancelToken;

  /// Cancel token for the cleaner LLM call. Held as a field so the user can
  /// abort a running cleaner via [abortPostCleaner] (Stop button in the
  /// PostCleanerStatusCard). `null` when no cleaner is in flight.
  CancelToken? _cleanerCancelToken;

  /// Abort a running POST-cleaner. Called by the Stop button in
  /// PostCleanerStatusCard. No-op when the cleaner is not running. The
  /// cleaner's `finally` block reverts the pre-created swipe and resets
  /// state, so this only needs to cancel the in-flight LLM request.
  void abortPostCleaner() {
    if (_cleanerCancelToken != null && !_cleanerCancelToken!.isCancelled) {
      _cleanerCancelToken!.cancel('User aborted post-cleaner');
    }
  }

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

      // Stage 2: Agentic write-loop — runs on both normal send AND regen.
      // On regen, SavedMessageWriter resets agentSwipes to a single fresh
      // 'final' (agentSwipeId=0), so the write-loop anchors the new snapshot
      // to (messageId, swipeId, 0) — mirroring Marinara's retry-agents which
      // re-run the full agent cycle per swipe. The stale snapshot from the
      // previous swipe is excluded via getLatestCommittedExcludingMessage.
      if (result.session != null) {
        unawaited(
          _runAgenticWriteLoop(
            sessionId: result.session!.id,
            messages: result.session!.messages,
            genId: genId,
            regenTargetId: regenTargetId,
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
    String? regenTargetId,
  }) async {
    if (!ref.mounted) return;

    try {
      final bookRepo = ref.read(memoryBookRepoProvider);
      final book = await bookRepo.getBySessionId(sessionId);
      if (!ref.mounted || !abortHandler.isCurrentGen(genId)) return;
      final pipeline = ref.read(pipelineSettingsProvider);
      if (!ref.mounted || !abortHandler.isCurrentGen(genId)) return;
      if (book == null || !pipeline.agenticWriteEnabled) return;

      // Read the current tracker state from snapshots (preferred) with a
      // tracker_rows fallback for legacy sessions pre-migration. On regen,
      // exclude the regenerating message's own stale snapshot so the base
      // state does not read the pre-regen tracker values.
      final snapshotRepo = ref.read(trackerSnapshotRepoProvider);
      final trackerRepo = ref.read(trackerRepoProvider);
      final snapshot = regenTargetId != null
          ? await snapshotRepo.getLatestCommittedExcludingMessage(
              sessionId,
              regenTargetId,
            )
          : await snapshotRepo.getLatestCommitted(sessionId);
      final trackers =
          snapshot?.trackers ?? await trackerRepo.getBySessionId(sessionId);
      if (!ref.mounted || !abortHandler.isCurrentGen(genId)) return;

      final recentHistory = extractRecentHistoryText(messages, maxMessages: 10);

      // Anchor for the tracker snapshot: the just-finished assistant turn.
      // On both normal send and regen, SavedMessageWriter seeds a single
      // 'final' agentSwipe (agentSwipeId=0), so the anchor is
      // (messageId, swipeId, 0). Guard against non-assistant trailing
      // messages defensively.
      final lastAssistant = messages.lastWhere(
        (m) => m.role == 'assistant',
        orElse: () => messages.last,
      );

      // Guard: if the user deleted the assistant message between the
      // generation finishing and the write-loop starting, the message no
      // longer exists in the session. Writing trackers/memory for a deleted
      // message would create orphaned entries tied to a non-existent
      // messageId. Re-read the session and abort if the target is gone.
      final currentSession = await ref.read(chatRepoProvider).getById(sessionId);
      if (currentSession == null ||
          !currentSession.messages.any((m) => m.id == lastAssistant.id)) {
        debugPrint(
          '[AgenticWrite] target message ${lastAssistant.id} no longer exists '
          'in session $sessionId — aborting write-loop',
        );
        return;
      }

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

      // Post-write guard: the user may have deleted the assistant message
      // WHILE the write-loop was running (it can take 60s+). If so, the
      // trackers and memory entries just written are now orphaned — tied to
      // a messageId that no longer exists. Clean them up so the UI doesn't
      // show stale state for a deleted turn.
      if (result.status == 'ok' && ref.mounted) {
        final postCheck = await ref.read(chatRepoProvider).getById(sessionId);
        if (postCheck == null ||
            !postCheck.messages.any((m) => m.id == lastAssistant.id)) {
          debugPrint(
            '[AgenticWrite] message ${lastAssistant.id} deleted during '
            'write-loop — purging orphaned trackers + memory',
          );
          await ref
              .read(memoryBookRepoProvider)
              .deleteForMessage(sessionId, lastAssistant.id)
              .catchError((Object _) {});
          await ref
              .read(trackerSnapshotRepoProvider)
              .deleteForMessage(sessionId, lastAssistant.id)
              .catchError((Object _) {});
          final snapshot = await ref
              .read(trackerSnapshotRepoProvider)
              .getLatestCommitted(sessionId);
          if (snapshot == null) {
            await ref
                .read(trackerRepoProvider)
                .clearForSession(sessionId);
          } else {
            await ref
                .read(trackerRepoProvider)
                .replaceForSession(sessionId, snapshot.trackers);
          }
        }
      }

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
      final pipeline = ref.read(pipelineSettingsProvider);
      if (!ref.mounted || !abortHandler.isCurrentGen(genId)) return;
      if (book == null || !pipeline.postCleanerEnabled) return;

      // The cleaner must only rewrite the just-generated assistant message.
      // If the trailing message is an error (e.g. Studio returned an empty
      // response → writeError), there is nothing to clean — return early so
      // we never accidentally rewrite a PREVIOUS valid assistant message.
      final trailing = messages.isNotEmpty ? messages.last : null;
      if (trailing == null ||
          trailing.role != 'assistant' ||
          trailing.isError) {
        return;
      }

      // Find the last non-error, non-typing, non-empty assistant message.
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

      // Defensive: the found `lastAssistant` must be the trailing message
      // (or its most recent swipe). If a later error message snuck in, abort.
      if (lastAssistant.id != trailing.id) return;

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
      //
      // Parallelised with the cleaner (Marinara `mergePairedBuiltInRewriteAgents`
      // adaptation for streaming UX): audit is non-streaming and short; the
      // cleaner is streaming and long. We fire audit `unawaited`-style in a
      // Future and `await` it with a SHORT timeout that races the cleaner's
      // pre-create-swipe + first-chunk work. If audit wins → its issues are
      // injected into the cleaner prompt as CHARACTER CONSISTENCY NOTES (same
      // as the serial path). If audit loses the race → cleaner runs without
      // audit notes this turn (graceful degradation; the audit Future is left
      // running and its result is logged when it completes — it does NOT block
      // cleanup). This trades 1 serial LLM call's latency for parallel
      // execution: UX-feel is "blue swipe starts streaming immediately,
      // audit badge appears later if it finished in time".
      List<String>? auditIssues;
      Future<List<String>?>? auditFuture;
      if (pipeline.postCleanerCharacterCheckEnabled && promptPayload != null) {
        final loreContent = _assembleLorebooksContent(promptPayload);
        // Dedicated cancel token: on the race-loser path the audit Future
        // keeps running in the background. Without this it would run to
        // completion (burning an LLM call / quota) even after the cleaner
        // finalized or the turn was aborted. We cancel it in the `finally`
        // block so the orphaned call is always bounded.
        _auditCancelToken = CancelToken();
        auditFuture = cleanerService
            .runCharacterAudit(
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
              cancelToken: _auditCancelToken,
            )
            .catchError((Object e) {
              debugPrint('[PostCleaner] audit failed session=$sessionId error=$e');
              return null;
            });
        // Log late-landing audit results (race-loser case): the Future
        // keeps running after the 3s timeout below; when it completes we
        // emit a debug line so the user can see "audit found N issues" even
        // on a turn where the cleaner ran without them. Fire-and-forget.
        unawaited(
          auditFuture.then((r) {
            if (r != null && r.isNotEmpty) {
              debugPrint(
                '[PostCleaner] audit late-landed session=$sessionId '
                'issues=${r.length} (not applied this turn — race loser)',
              );
            }
          }),
        );
      }

      // ── Swipe-first: pre-create the blue 'cleaned' swipe NOW (Fix 1) ────────
      //
      // Append an empty 'cleaned' sub-swipe before the cleaner runs, so the
      // blue swipe switcher is visible immediately while the rewrite streams
      // into the chat bubble for live preview. On completion we fill the
      // pre-created swipe with the final text via applyCleanedText (which
      // appends ANOTHER swipe — see below), or remove it if nothing useful
      // was produced.
      //
      // Note: applyCleanedText itself calls appendAgentSwipe, which means the
      // final state has TWO 'cleaned' swipes if we pre-create one here. To
      // avoid that, when wasCleaned / partial-save we instead update the
      // pre-created swipe in place via removeAgentSwipe followed by
      // applyCleanedText (append) — simplest sequence that reuses the existing
      // atomic append + snapshot-clone logic. The user-visible result is one
      // 'cleaned' swipe carrying the final text.
      //
      // Snapshot clone: the 'cleaned' sub-swipe must inherit the parent
      // 'final' tracker snapshot so navigating to it restores the correct
      // tracker state. applyCleanedText does this clone after its append; here
      // we clone into the pre-created empty swipe so the snapshot is correct
      // even if the cleaner crashes before finalization.
      _lastStreamedText = '';
      _preCreatedCleanerSwipeId = -1;
      _preCreatedMessageId = lastAssistant.id;
      try {
        final chatRepo = ref.read(chatRepoProvider);
        final preCreated = await chatRepo.appendAgentSwipe(
          sessionId: sessionId,
          messageId: lastAssistant.id,
          content: '',
          kind: 'cleaned',
        );
        if (preCreated && ref.mounted) {
          // Re-read to capture the new active agentSwipeId (handles
          // lazy-backfill for legacy messages the same way applyCleanedText
          // does at post_cleaner_service.dart:417).
          final postAppend = await chatRepo.getById(sessionId);
          if (postAppend != null) {
            ChatSessionService.updateCache(postAppend);
            final msg = postAppend.messages
                .where((m) => m.id == lastAssistant!.id)
                .firstOrNull;
            if (msg != null && msg.agentSwipeId > 0) {
              _preCreatedCleanerSwipeId = msg.agentSwipeId;
              final parentAgentSwipeId = msg.agentSwipeId - 1;
              final snapshotRepo = ref.read(
                trackerSnapshotRepoProvider,
              );
              final parent = await snapshotRepo.getByAnchor(
                sessionId: sessionId,
                messageId: lastAssistant.id,
                swipeId: msg.swipeId,
                agentSwipeId: parentAgentSwipeId,
              );
              if (parent != null) {
                await snapshotRepo.upsertTrackers(
                  sessionId: sessionId,
                  messageId: lastAssistant.id,
                  swipeId: msg.swipeId,
                  agentSwipeId: msg.agentSwipeId,
                  trackers: parent.trackers,
                );
              }
              ref.invalidate(chatHistoryProvider);
            }
          }
        }
      } catch (e) {
        debugPrint(
          '[PostCleaner] pre-create swipe failed session=$sessionId error=$e',
        );
        _preCreatedCleanerSwipeId = -1;
      }

      // Race the audit Future against a short budget (3s). If audit wins,
      // its issues flow into the cleaner prompt as CHARACTER CONSISTENCY
      // NOTES (same as the serial path). If it loses the race, the cleaner
      // runs without audit notes this turn — graceful degradation. The
      // audit Future keeps running in the background; we log its result
      // when it lands (below, after the cleaner returns) so the user can
      // still see "audit found N issues" even on a losing race.
      if (auditFuture != null) {
        try {
          auditIssues = await auditFuture.timeout(
            const Duration(seconds: 3),
            onTimeout: () => null,
          );
          if (!ref.mounted || !abortHandler.isCurrentGen(genId)) {
            ref.read(postCleanerStateProvider.notifier).state =
                const PostCleanerState.idle();
            return;
          }
          debugPrint(
            '[PostCleaner] audit session=$sessionId '
            'issues=${auditIssues?.length ?? "null(timeout/failed)"}',
          );
        } catch (e) {
          debugPrint('[PostCleaner] audit await error=$e');
          auditIssues = null;
        }
      }

      _cleanerCancelToken = CancelToken();
      ref.read(cleanerCancelTokenProvider.notifier).state = _cleanerCancelToken;
      final result = await cleanerService.runCleaner(
        sessionId: sessionId,
        settings: pipeline,
        assistantText: lastAssistant.content,
        broadcastBlocks: broadcastBlocks,
        recentMessages: recentMessages,
        auditIssues: auditIssues,
        cancelToken: _cleanerCancelToken,
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
          // Track the latest accumulated chunk (Fix 1 — "preserve partial
          // text on failure"). SidecarCallOutcome.text is null on any failure
          // (timeout, error, abort), so the partial text the user saw live is
          // only available via this callback. Retries reset the accumulator
          // and re-call onChunk from '', so only overwrite lastStreamedText
          // when the incoming chunk is at least as long — that picks the
          // latest attempt's partial output.
          if (text.length >= _lastStreamedText.length) {
            _lastStreamedText = text;
          }
        },
      );

      if (!ref.mounted || !abortHandler.isCurrentGen(genId)) {
        // Aborted mid-cleaner. The pre-created empty 'cleaned' swipe would be
        // left dangling — remove it and revert to the parent 'final'. We do
        // NOT persist partial text on abort (per plan: default delete on
        // abort). onCleanedChunk early-returns on stale genId, so
        // _lastStreamedText is empty here.
        if (_preCreatedCleanerSwipeId >= 0) {
          try {
            await ref.read(chatRepoProvider).removeAgentSwipe(
              sessionId: sessionId,
              messageId: lastAssistant.id,
              agentSwipeId: _preCreatedCleanerSwipeId,
            );
          } catch (_) {}
        }
        ref.read(postCleanerStateProvider.notifier).state =
            const PostCleanerState.idle();
        return;
      }

      debugPrint(
        '[PostCleaner] result session=$sessionId wasCleaned=${result.wasCleaned} '
        'origChars=${lastAssistant.content.length} '
        'cleanedChars=${result.cleanedText.length} '
        'error=${result.error ?? "none"} '
        'attempts=${result.attempts.length} '
        'partialChars=${_lastStreamedText.length}',
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
                  : _lastStreamedText.trim().isNotEmpty
                  ? 'partialSaved (${_lastStreamedText.length} chars)'
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

      // ── Swipe-first finalization (Fix 1) ─────────────────────────────────
      //
      // The blue 'cleaned' swipe was pre-created before runCleaner (above).
      // Now we finalize it based on what the cleaner produced:
      //   - wasCleaned==true → fill the pre-created swipe with the cleaned text.
      //   - wasCleaned==false BUT the cleaner streamed partial text before
      //     failing (timeout/error) → keep the partial text in the swipe so
      //     the user doesn't lose what they saw live.
      //   - wasCleaned==false AND nothing was streamed → delete the pre-created
      //     empty swipe and revert to the 'final'.
      //
      // We update the pre-created swipe IN PLACE via updateAgentSwipeContent
      // (not append another swipe) so the final state has exactly one 'cleaned'
      // sub-swipe. The tracker snapshot was already cloned at pre-create time.
      //
      // genTime/tokens wiring is from Phase 1 (Fix 3 + Fix 4): per-swipe badge
      // carrying the cleaner's own elapsed time + the cleaned text's token
      // estimate so the badge doesn't disappear on the blue sub-swipe.

      // Guard: if the user deleted the message while the cleaner was running,
      // lastAssistant.id no longer exists in the session. Applying the cleaned
      // swipe now would either fail silently or attach to the wrong message
      // (e.g. the previous assistant turn). Re-read the session and abort if
      // the target message is gone.
      final currentSession = await ref.read(chatRepoProvider).getById(sessionId);
      if (currentSession == null ||
          !currentSession.messages.any((m) => m.id == lastAssistant!.id)) {
        debugPrint(
          '[PostCleaner] target message ${lastAssistant.id} no longer exists '
          'in session $sessionId — aborting cleaner apply',
        );
        if (_preCreatedCleanerSwipeId >= 0) {
          try {
            await ref.read(chatRepoProvider).removeAgentSwipe(
              sessionId: sessionId,
              messageId: lastAssistant.id,
              agentSwipeId: _preCreatedCleanerSwipeId,
            );
          } catch (_) {}
        }
        ref.read(postCleanerStateProvider.notifier).state =
            const PostCleanerState.idle();
        return;
      }

      final genTime =
          '${(result.totalElapsedMs / 1000).toStringAsFixed(1)}s';
      final chatRepo = ref.read(chatRepoProvider);

      if (result.wasCleaned) {
        if (_preCreatedCleanerSwipeId >= 0) {
          await chatRepo.updateAgentSwipeContent(
            sessionId: sessionId,
            messageId: lastAssistant.id,
            agentSwipeId: _preCreatedCleanerSwipeId,
            content: result.cleanedText,
            genTime: genTime,
            tokens: estimateTokens(result.cleanedText),
          );
        } else {
          // Pre-create failed earlier — fall back to the legacy append path so
          // the user still gets a 'cleaned' swipe.
          await cleanerService.applyCleanedText(
            sessionId: sessionId,
            messageId: lastAssistant.id,
            cleanedText: result.cleanedText,
            genTime: genTime,
            tokens: estimateTokens(result.cleanedText),
          );
        }
      } else if (result.status == 'skipped') {
        // The cleaner ran to completion but the result was DELIBERATELY
        // rejected by a safety guard (length-ratio out of bounds, or the
        // rewrite dropped protected markup — see PostCleanerService). In this
        // case `_lastStreamedText` holds the rejected (e.g. markup-stripped)
        // text that was streamed live for UX; we must NOT persist it, or the
        // guard is defeated. Delete the pre-created swipe and revert to the
        // parent 'final' (the untouched original).
        if (_preCreatedCleanerSwipeId >= 0) {
          await chatRepo.removeAgentSwipe(
            sessionId: sessionId,
            messageId: lastAssistant.id,
            agentSwipeId: _preCreatedCleanerSwipeId,
          );
        }
      } else if (_lastStreamedText.trim().isNotEmpty) {
        // Cleaner failed mid-stream (error/timeout/aborted) but produced
        // partial text — keep it (do-no-harm: partial cleaned text is still
        // closer to the user's intent than discarding the work).
        if (_preCreatedCleanerSwipeId >= 0) {
          await chatRepo.updateAgentSwipeContent(
            sessionId: sessionId,
            messageId: lastAssistant.id,
            agentSwipeId: _preCreatedCleanerSwipeId,
            content: _lastStreamedText,
            genTime: genTime,
            tokens: estimateTokens(_lastStreamedText),
          );
        } else {
          // Pre-create failed — append the partial text as a new swipe.
          await cleanerService.applyCleanedText(
            sessionId: sessionId,
            messageId: lastAssistant.id,
            cleanedText: _lastStreamedText,
            genTime: genTime,
            tokens: estimateTokens(_lastStreamedText),
          );
        }
      } else if (_preCreatedCleanerSwipeId >= 0) {
        // Nothing useful was produced — delete the pre-created empty swipe
        // and revert to the parent 'final'.
        await chatRepo.removeAgentSwipe(
          sessionId: sessionId,
          messageId: lastAssistant.id,
          agentSwipeId: _preCreatedCleanerSwipeId,
        );
      }

      // Reset the streaming state so the WebView stops treating the bubble
      // as isTyping. The chatHistoryProvider invalidate below pushes the
      // finalized message (with the new cleaned swipe) to the WebView.
      if (ref.mounted) {
        ref.read(streamingStateProvider(charId).notifier).state =
            const StreamingState();
      }

      // Refresh ChatNotifier state so the UI picks up the new swipe
      // immediately without requiring the user to re-enter the chat. The
      // update/remove above wrote to DB; ChatNotifier holds its own
      // ChatState copy that must be pushed.
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
        // Best-effort cleanup of the pre-created swipe on a hard pipeline
        // failure (e.g. runCleaner threw before returning). Revert to final.
        if (_preCreatedCleanerSwipeId >= 0) {
          try {
            final removed = await ref
                .read(chatRepoProvider)
                .removeAgentSwipe(
                  sessionId: sessionId,
                  messageId: _preCreatedMessageId ?? '',
                  agentSwipeId: _preCreatedCleanerSwipeId,
                );
            if (removed) {
              final reverted = await ref
                  .read(chatRepoProvider)
                  .getById(sessionId);
              if (reverted != null) {
                ChatSessionService.updateCache(reverted);
                ref.invalidate(chatHistoryProvider);
              }
            }
          } catch (_) {
            // swallow — already in an error path
          }
        }
      }
    } finally {
      // Cancel any still-running (race-loser) audit call so it doesn't burn
      // an LLM request after the cleaner has finalized / the turn aborted.
      // No-op if the audit already completed (won the race) or was never
      // started. The `.catchError` on `auditFuture` neutralizes the
      // resulting cancellation error for the late `.then` logger.
      if (_auditCancelToken != null && !_auditCancelToken!.isCancelled) {
        _auditCancelToken!.cancel();
      }
      _auditCancelToken = null;
      _cleanerCancelToken = null;
      ref.read(cleanerCancelTokenProvider.notifier).state = null;
      _lastStreamedText = '';
      _preCreatedCleanerSwipeId = -1;
      _preCreatedMessageId = null;
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
