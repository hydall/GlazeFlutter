import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/llm/aux_llm_client.dart' show AuxApiConfig;
import '../../../../core/llm/beauty_state_parser.dart';
import '../../../../core/llm/prompt_builder.dart' show PromptPayload;
import '../../../../core/llm/studio_slot_resolver.dart';
import '../../../../core/llm/tokenizer.dart';
import '../../../../core/models/agent_operation_record.dart';
import '../../../../core/models/character.dart';
import '../../../../core/models/chat_message.dart';
import '../../../../core/models/pipeline_settings.dart';
import '../../../../core/state/db_provider.dart';
import '../../../../core/state/memory_agent_providers.dart';
import '../../../../core/state/character_provider.dart';
import '../../../chat_history/chat_history_provider.dart';
import '../../chat_session_service.dart';
import '../../state/agent_operations_log_provider.dart';
import '../../state/post_cleaner_state_provider.dart';
import '../../chat_provider.dart' show streamingStateProvider;
import '../../chat_state.dart';
import '../pipeline_utils.dart';
import 'ext_blocks_stage.dart';
import 'ledger_stage.dart';
import 'stage_context.dart';
import 'fact_checker_runner.dart';
import 'beauty_state_handler.dart';

/// Stage 4: POST-cleaner trigger.
///
/// Fire-and-forget — silently rewrites the last assistant message to
/// remove clichés/repetition. Studio-only. Falls back to original text on
/// any error. The original is preserved as a swipe.
///
/// Also handles manual rerun via [rerun].
class CleanerStage {
  final StageContext ctx;
  final ExtBlocksStage extBlocks;
  final LedgerStage ledger;
  late final FactCheckerRunner _factChecker = FactCheckerRunner(ctx);

  CleanerStage(this.ctx, {required this.extBlocks, required this.ledger});

  /// Latest accumulated chunk from the cleaner's onCleanedChunk callback.
  /// Captured so we can persist partial text when the cleaner fails
  /// mid-stream (Fix 1): AuxCallOutcome.text is null on any failure, so
  /// the partial text the user saw live is only reachable via the callback.
  /// Reset in [run]'s finally block.
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
  /// abort a running cleaner via `cleanerCancelTokenProvider` (Stop button
  /// in the PostCleanerStatusCard). `null` when no cleaner is in flight.
  CancelToken? _cleanerCancelToken;

  /// Auto post-generation cleaner trigger. Staleness guard: checks
  /// `abortHandler.isCurrentGen(genId)` before applying the cleaned text.
  Future<void> run({
    required String sessionId,
    required List<ChatMessage> messages,
    required int genId,
    PromptPayload? promptPayload,
    Character? character,
  }) async {
    if (!ctx.ref.mounted) return;

    try {
      final bookRepo = ctx.ref.read(memoryBookRepoProvider);
      final book = await bookRepo.getBySessionId(sessionId);
      if (!ctx.ref.mounted || !ctx.abortHandler.isCurrentGen(genId)) return;
      final pipeline = ctx.ref.read(pipelineSettingsProvider);
      if (!ctx.ref.mounted || !ctx.abortHandler.isCurrentGen(genId)) return;
      if (book == null) return;

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
      final maxHistory = pipeline.cleaner.postCleanerHistoryMessages;
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
      // The cleaner is Studio-only — skip entirely when Studio is disabled.
      List<String> broadcastBlocks = const [];
      var studioConfigEnabled = false;
      var studioCleanerApiConfigId = '';
      try {
        final studioConfig = await ctx.ref
            .read(studioConfigRepoProvider)
            .getBySessionId(sessionId);
        broadcastBlocks = studioConfig?.broadcastBlocks ?? const [];
        studioConfigEnabled = studioConfig?.enabled == true;
        studioCleanerApiConfigId = studioConfig?.cleanerApiConfigId ?? '';
      } catch (e) {
        debugPrint(
          '[PostCleaner] broadcast load failed session=$sessionId error=$e',
        );
      }
      if (!ctx.ref.mounted || !ctx.abortHandler.isCurrentGen(genId)) return;

      // Cleaner is Studio-only. Skip when Studio is disabled.
      if (!studioConfigEnabled) {
        debugPrint('[PostCleaner] skipping — Studio not enabled');
        return;
      }

      // Resolve the Studio cleaner slot (fail-explicit).
      final AuxApiConfig cleanerConfig;
      try {
        cleanerConfig = await StudioSlotResolver(ctx.ref).resolve(
          apiConfigId: studioCleanerApiConfigId,
          errorLabel: 'post-cleaner',
          modelOverride: pipeline.cleaner.postCleanerModel,
        );
      } catch (e) {
        debugPrint('[PostCleaner] slot resolution failed: $e');
        return;
      }
      if (!ctx.ref.mounted || !ctx.abortHandler.isCurrentGen(genId)) return;

      // Extract Beauty Shard brief from the assistant message's studioOutputs.
      var beautyBrief = '';
      String? beautyState;
      try {
        beautyBrief = BeautyStateHandler.extractBeautyBrief(lastAssistant);
        // Load current beauty state from session vars.
        final session = await ctx.ref.read(chatRepoProvider).getById(sessionId);
        if (session != null) {
          beautyState = BeautyStateHandler.extractBeautyState(
            session.sessionVars,
          );
        }
      } catch (e) {
        debugPrint(
          '[PostCleaner] beauty brief extraction failed session=$sessionId error=$e',
        );
      }
      if (!ctx.ref.mounted || !ctx.abortHandler.isCurrentGen(genId)) return;

      await _executeAndApplyCleaner(
        sessionId: sessionId,
        genId: genId,
        targetMessage: lastAssistant,
        assistantText: lastAssistant.content,
        recentMessages: recentMessages,
        broadcastBlocks: broadcastBlocks,
        pipeline: pipeline,
        promptPayload: promptPayload,
        character: character,
        cleanerConfig: cleanerConfig,
        beautyBrief: beautyBrief,
        beautyState: beautyState,
      );
    } catch (e) {
      debugPrint('[PostCleaner] failed session=$sessionId error=$e');
      if (ctx.ref.mounted) {
        // Reset any partial stream so the bubble doesn't stay isTyping.
        ctx.ref.read(streamingStateProvider(ctx.charId).notifier).state =
            const StreamingState();
        ctx.ref.read(postCleanerStateProvider.notifier).state =
            const PostCleanerState.idle();
        // Best-effort cleanup of the pre-created swipe on a hard pipeline
        // failure (e.g. runCleaner threw before returning). Revert to final.
        if (_preCreatedCleanerSwipeId >= 0) {
          try {
            final removed = await ctx.ref
                .read(chatRepoProvider)
                .removeAgentSwipe(
                  sessionId: sessionId,
                  messageId: _preCreatedMessageId ?? '',
                  agentSwipeId: _preCreatedCleanerSwipeId,
                );
            if (removed) {
              final reverted = await ctx.ref
                  .read(chatRepoProvider)
                  .getById(sessionId);
              if (reverted != null) {
                ChatSessionService.updateCache(reverted);
                ctx.ref.invalidate(chatHistoryProvider);
              }
            }
          } catch (_) {
            // swallow — already in an error path
          }
        }
      }
    } finally {
      // Cancel any still-running audit call on abort/error cleanup. No-op if
      // the audit already completed or was never started.
      if (_auditCancelToken != null && !_auditCancelToken!.isCancelled) {
        _auditCancelToken!.cancel();
      }
      _auditCancelToken = null;
      _cleanerCancelToken = null;
      ctx.ref.read(cleanerCancelTokenProvider.notifier).state = null;
      _lastStreamedText = '';
      _preCreatedCleanerSwipeId = -1;
      _preCreatedMessageId = null;
    }
  }

  /// Shared core of the POST-cleaner pipeline. Handles:
  ///   - debugPrint start line + `PostCleanerState.running`
  ///   - optional character audit before cleaner prompt assembly
  ///   - pre-create the blue 'cleaned' sub-swipe (Fix 1)
  ///   - `runCleaner` with streaming into the chat bubble
  ///   - finalize the pre-created swipe (update / remove / append fallback)
  ///   - record to the agentic operations log
  ///   - setState with the refreshed session so the UI picks up the new swipe
  Future<void> _executeAndApplyCleaner({
    required String sessionId,
    required int genId,
    required ChatMessage targetMessage,
    required String assistantText,
    required List<ChatMessage> recentMessages,
    required List<String> broadcastBlocks,
    required PipelineSettings pipeline,
    PromptPayload? promptPayload,
    Character? character,
    required AuxApiConfig cleanerConfig,
    String beautyBrief = '',
    String? beautyState,
  }) async {
    final isManualRerun = genId < 0;
    bool abortCheck() =>
        ctx.ref.mounted && (isManualRerun || ctx.abortHandler.isCurrentGen(genId));

    debugPrint(
      '[PostCleaner] starting session=$sessionId '
      'model=${cleanerConfig.model} '
      'timeoutMs=${pipeline.cleaner.postCleanerTimeoutMs > 0 ? pipeline.cleaner.postCleanerTimeoutMs : pipeline.memoryPipeline.auxTimeoutMs} '
      'textChars=${assistantText.length} '
      'broadcastBlocks=${broadcastBlocks.length} '
      'historyMessages=${recentMessages.length} '
      'continuity=true '
      'charCheck=true '
      'rerun=$isManualRerun',
    );

    final factCheckEnabled = promptPayload != null;

    ctx.ref.read(postCleanerStateProvider.notifier).state = factCheckEnabled
        ? PostCleanerState.factChecking(
            sessionId: sessionId,
            messageId: targetMessage.id,
            originalChars: assistantText.length,
          )
        : PostCleanerState.running(
            sessionId: sessionId,
            messageId: targetMessage.id,
            originalChars: assistantText.length,
          );

    final cleanerService = ctx.ref.read(postCleanerServiceProvider);

    // Pass 0: Character/World Auditor (diagnostic, optional). Runs only when
    // characterCheckEnabled AND promptPayload is available (exact generation
    // snapshot). Returns null on failure → cleaner runs without audit notes.
    List<String>? auditIssues;
    Future<List<String>?>? auditFuture;
    int? auditStartedAt;
    if (factCheckEnabled) {
      final auditPayload = promptPayload;
      final loreContent = assembleLorebooksContent(auditPayload);
      // Dedicated cancel token so Stop can abort the auditor before the
      // cleaner prompt is built.
      _auditCancelToken = CancelToken();
      ctx.ref.read(cleanerCancelTokenProvider.notifier).state = _auditCancelToken;
      auditStartedAt = DateTime.now().millisecondsSinceEpoch;
      auditFuture = cleanerService
          .runCharacterAudit(
            assistantText: assistantText,
            character: auditPayload.character,
            persona: auditPayload.persona,
            lorebooksContent: loreContent,
            memoryContent:
                auditPayload.memoryContent ?? auditPayload.memoryMacroContent,
            summaryContent: auditPayload.summaryContent,
            arcContent: auditPayload.arcContent,
            entitiesContent: auditPayload.entitiesContent,
            recentMessages: recentMessages,
            settings: pipeline,
            config: cleanerConfig,
            cancelToken: _auditCancelToken,
          )
          .catchError((Object e) {
            debugPrint(
              '[PostCleaner] audit failed session=$sessionId error=$e',
            );
            return null;
          });
    }

    // ── Swipe-first: pre-create the blue 'cleaned' swipe NOW (Fix 1) ─────────
    _lastStreamedText = '';
    _preCreatedCleanerSwipeId = -1;
    _preCreatedMessageId = targetMessage.id;
    try {
      final chatRepo = ctx.ref.read(chatRepoProvider);
      final preCreated = await chatRepo.appendAgentSwipe(
        sessionId: sessionId,
        messageId: targetMessage.id,
        content: '',
        kind: 'cleaned',
      );
      if (preCreated && ctx.ref.mounted) {
        // Re-read to capture the new active agentSwipeId (handles
        // lazy-backfill for legacy messages the same way applyCleanedText
        // does at post_cleaner_service.dart:417).
        final postAppend = await chatRepo.getById(sessionId);
        if (postAppend != null) {
          ChatSessionService.updateCache(postAppend);
          final msg = postAppend.messages
              .where((m) => m.id == targetMessage.id)
              .firstOrNull;
          if (msg != null && msg.agentSwipeId > 0) {
            _preCreatedCleanerSwipeId = msg.agentSwipeId;
            final parentAgentSwipeId = msg.agentSwipeId - 1;
            final snapshotRepo = ctx.ref.read(trackerSnapshotRepoProvider);
            final parent = await snapshotRepo.getByAnchor(
              sessionId: sessionId,
              messageId: targetMessage.id,
              swipeId: msg.swipeId,
              agentSwipeId: parentAgentSwipeId,
            );
            if (parent != null) {
              await snapshotRepo.upsertTrackers(
                sessionId: sessionId,
                messageId: targetMessage.id,
                swipeId: msg.swipeId,
                agentSwipeId: msg.agentSwipeId,
                trackers: parent.trackers,
              );
            }
            ctx.ref.invalidate(chatHistoryProvider);
          }
        }
      }
    } catch (e) {
      debugPrint(
        '[PostCleaner] pre-create swipe failed session=$sessionId error=$e',
      );
      _preCreatedCleanerSwipeId = -1;
    }

    // If audit is enabled, wait for it before constructing the cleaner prompt
    // so its issues flow into CHARACTER CONSISTENCY NOTES. Audit failure still
    // degrades gracefully to `null` notes.
    if (auditFuture != null) {
      try {
        auditIssues = await auditFuture;
        _factChecker.record(
          sessionId: sessionId,
          messageId: targetMessage.id,
          startedAtMs: auditStartedAt ?? DateTime.now().millisecondsSinceEpoch,
          issues: auditIssues,
          model: cleanerConfig.model,
        );
        debugPrint(
          '[PostCleaner] audit session=$sessionId '
          'issues=${auditIssues?.length ?? "null(timeout/failed)"}',
        );
      } catch (e) {
        debugPrint('[PostCleaner] audit await error=$e');
        auditIssues = null;
        _factChecker.record(
          sessionId: sessionId,
          messageId: targetMessage.id,
          startedAtMs: auditStartedAt ?? DateTime.now().millisecondsSinceEpoch,
          issues: null,
          error: '$e',
          model: cleanerConfig.model,
        );
      }
    }

    _cleanerCancelToken = CancelToken();
    ctx.ref.read(cleanerCancelTokenProvider.notifier).state = _cleanerCancelToken;
    if (factCheckEnabled) {
      ctx.ref
          .read(postCleanerStateProvider.notifier)
          .state = PostCleanerState.running(
        sessionId: sessionId,
        messageId: targetMessage.id,
        originalChars: assistantText.length,
        factCheckEnabled: true,
      );
    }
    final result = await cleanerService.runCleaner(
      sessionId: sessionId,
      settings: pipeline,
      config: cleanerConfig,
      assistantText: assistantText,
      broadcastBlocks: broadcastBlocks,
      recentMessages: recentMessages,
      auditIssues: auditIssues,
      cancelToken: _cleanerCancelToken,
      beautyBrief: beautyBrief,
      beautyState: beautyState,
      onCleanedChunk: (text) {
        if (!abortCheck()) return;
        ctx.ref.read(streamingStateProvider(ctx.charId).notifier).state =
            StreamingState(text: text, targetMessageId: targetMessage.id);
        if (text.length >= _lastStreamedText.length) {
          _lastStreamedText = text;
        }
      },
    );

    if (result.status == 'aborted') {
      if (_preCreatedCleanerSwipeId >= 0) {
        try {
          await ctx.ref
              .read(chatRepoProvider)
              .removeAgentSwipe(
                sessionId: sessionId,
                messageId: targetMessage.id,
                agentSwipeId: _preCreatedCleanerSwipeId,
              );
        } catch (_) {}
      }
      ctx.ref.read(postCleanerStateProvider.notifier).state =
          const PostCleanerState.idle();
      return;
    }

    debugPrint(
      '[PostCleaner] result session=$sessionId wasCleaned=${result.wasCleaned} '
      'origChars=${assistantText.length} '
      'cleanedChars=${result.cleanedText.length} '
      'error=${result.error ?? "none"} '
      'attempts=${result.attempts.length} '
      'partialChars=${_lastStreamedText.length}',
    );

    ctx.ref.read(postCleanerStateProvider.notifier).state = result.wasCleaned
        ? PostCleanerState.done(
            sessionId: sessionId,
            messageId: targetMessage.id,
            originalChars: assistantText.length,
            cleanedChars: result.cleanedText.length,
          )
        : (result.status == 'ok' || result.status == 'disabled')
        ? const PostCleanerState.idle()
        : PostCleanerState.error(
            sessionId: sessionId,
            messageId: targetMessage.id,
          );

    // Record the operation in the agentic operations log.
    ctx.ref.read(agentOperationsLogProvider.notifier).state = ctx.ref
        .read(agentOperationsLogProvider)
        .append(
          AgentOperationRecord(
            id: 'cleaner-${targetMessage.id}-${DateTime.now().microsecondsSinceEpoch}',
            kind: AgentOperationKind.postCleaner,
            status: cleanerStatusToOp(result.status),
            sessionId: sessionId,
            messageId: targetMessage.id,
            attempts: result.attempts,
            totalElapsedMs: result.totalElapsedMs,
            model: result.model,
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
    final genTime = '${(result.totalElapsedMs / 1000).toStringAsFixed(1)}s';
    final chatRepo = ctx.ref.read(chatRepoProvider);

    if (result.wasCleaned) {
      var cleanedAgentSwipeId = _preCreatedCleanerSwipeId >= 0
          ? _preCreatedCleanerSwipeId
          : (targetMessage.agentSwipes.isNotEmpty
                ? targetMessage.agentSwipes.length - 1
                : 0);
      var persisted = false;
      if (_preCreatedCleanerSwipeId >= 0) {
        persisted = await chatRepo.updateAgentSwipeContent(
          sessionId: sessionId,
          messageId: targetMessage.id,
          agentSwipeId: _preCreatedCleanerSwipeId,
          content: result.cleanedText,
          genTime: genTime,
          tokens: estimateTokens(result.cleanedText),
        );
      }
      if (!persisted) {
        if (_preCreatedCleanerSwipeId >= 0) {
          await chatRepo.removeAgentSwipe(
            sessionId: sessionId,
            messageId: targetMessage.id,
            agentSwipeId: _preCreatedCleanerSwipeId,
          );
        }
        // Pre-create failed earlier — fall back to the legacy append path.
        await cleanerService.applyCleanedText(
          sessionId: sessionId,
          messageId: targetMessage.id,
          cleanedText: result.cleanedText,
          genTime: genTime,
          tokens: estimateTokens(result.cleanedText),
        );
        final postFallback = await chatRepo.getById(sessionId);
        final postFallbackMsg = postFallback?.messages
            .where((m) => m.id == targetMessage.id)
            .firstOrNull;
        cleanedAgentSwipeId =
            postFallbackMsg?.agentSwipeId ?? cleanedAgentSwipeId;
      }
      // Launch extension blocks bound to the NEW cleaned swipe.
      if (character != null && ctx.ref.mounted) {
        final refreshed = await ctx.ref.read(chatRepoProvider).getById(sessionId);
        if (refreshed != null) {
          await extBlocks.launchForSwipe(
            session: refreshed,
            character: character,
            agentSwipeId: cleanedAgentSwipeId,
          );
        }
      }
    } else if (result.status == 'ok') {
      if (_preCreatedCleanerSwipeId >= 0) {
        await chatRepo.removeAgentSwipe(
          sessionId: sessionId,
          messageId: targetMessage.id,
          agentSwipeId: _preCreatedCleanerSwipeId,
        );
      }
      if (character != null && ctx.ref.mounted) {
        final refreshed = await ctx.ref.read(chatRepoProvider).getById(sessionId);
        if (refreshed != null) {
          await extBlocks.launchForSwipe(
            session: refreshed,
            character: character,
            agentSwipeId: -1,
          );
        }
      }
    } else if (result.status == 'skipped') {
      if (_preCreatedCleanerSwipeId >= 0) {
        await chatRepo.removeAgentSwipe(
          sessionId: sessionId,
          messageId: targetMessage.id,
          agentSwipeId: _preCreatedCleanerSwipeId,
        );
      }
      if (character != null && ctx.ref.mounted) {
        final refreshed = await ctx.ref.read(chatRepoProvider).getById(sessionId);
        if (refreshed != null) {
          await extBlocks.launchForSwipe(
            session: refreshed,
            character: character,
            agentSwipeId: -1,
          );
        }
      }
    } else if (_lastStreamedText.trim().isNotEmpty) {
      if (_preCreatedCleanerSwipeId >= 0) {
        await chatRepo.updateAgentSwipeContent(
          sessionId: sessionId,
          messageId: targetMessage.id,
          agentSwipeId: _preCreatedCleanerSwipeId,
          content: _lastStreamedText,
          genTime: genTime,
          tokens: estimateTokens(_lastStreamedText),
        );
      } else {
        await cleanerService.applyCleanedText(
          sessionId: sessionId,
          messageId: targetMessage.id,
          cleanedText: _lastStreamedText,
          genTime: genTime,
          tokens: estimateTokens(_lastStreamedText),
        );
      }
      if (character != null && ctx.ref.mounted) {
        final refreshed = await ctx.ref.read(chatRepoProvider).getById(sessionId);
        if (refreshed != null) {
          await extBlocks.launchForSwipe(
            session: refreshed,
            character: character,
            agentSwipeId: _preCreatedCleanerSwipeId >= 0
                ? _preCreatedCleanerSwipeId
                : -1,
          );
        }
      }
    } else if (_preCreatedCleanerSwipeId >= 0) {
      await chatRepo.removeAgentSwipe(
        sessionId: sessionId,
        messageId: targetMessage.id,
        agentSwipeId: _preCreatedCleanerSwipeId,
      );
      if (character != null && ctx.ref.mounted) {
        final refreshed = await ctx.ref.read(chatRepoProvider).getById(sessionId);
        if (refreshed != null) {
          await extBlocks.launchForSwipe(
            session: refreshed,
            character: character,
            agentSwipeId: -1,
          );
        }
      }
    }

    // Persist the updated beauty state from the cleaner output.
    if (result.beautyMarkerFound &&
        result.beautyStateJson != null &&
        result.beautyStateJson!.trim().isNotEmpty &&
        ctx.ref.mounted) {
      try {
        await ctx.ref.read(chatRepoProvider).updateSessionVarsJson(
          sessionId,
          (vars) {
            final updated = Map<String, dynamic>.from(vars);
            updated[beautyStateVarKey] = result.beautyStateJson!;
            return updated;
          },
        );
        debugPrint(
          '[PostCleaner] beauty state persisted session=$sessionId',
        );
      } catch (e) {
        debugPrint(
          '[PostCleaner] beauty state persist failed session=$sessionId error=$e',
        );
      }
    }

    // Reset the streaming state so the WebView stops treating the bubble
    // as isTyping.
    if (ctx.ref.mounted) {
      if (ctx.abortHandler.isCurrentGen(genId)) {
        ctx.ref.read(streamingStateProvider(ctx.charId).notifier).state =
            const StreamingState();
      }
    }

    // Refresh ChatNotifier state so the UI picks up the new swipe.
    List<ChatMessage>? refreshedMessages;
    if (ctx.ref.mounted) {
      final refreshed = await ctx.ref.read(chatRepoProvider).getById(sessionId);
      if (refreshed != null) {
        refreshedMessages = refreshed.messages;
        ChatSessionService.updateCache(refreshed);
        final current = ctx.getState().value;
        if (current != null &&
            current.session?.id == sessionId &&
            (!current.isGenerating || ctx.abortHandler.isCurrentGen(genId))) {
          ctx.setState(
            AsyncData(
              current.copyWith(
                session: refreshed,
                isGenerating: ctx.abortHandler.isCurrentGen(genId)
                    ? false
                    : current.isGenerating,
              ),
            ),
          );
        }
        ctx.ref.invalidate(chatHistoryProvider);
      }
    }

    // Stage 7: Studio Ledger — fired here so it always receives the final
    // canonical text.
    if (ctx.ref.mounted && !isManualRerun) {
      final ledgerText = selectStudioLedgerTextAfterCleaner(
        cleanerStatus: result.status,
        wasCleaned: result.wasCleaned,
        cleanedText: result.cleanedText,
        assistantText: assistantText,
        streamedPartialText: _lastStreamedText,
      );
      final ledgerTargetMessage = refreshedMessages
          ?.where((m) => m.id == targetMessage.id)
          .firstOrNull;

      unawaited(
        ledger.run(
          sessionId: sessionId,
          messages: refreshedMessages ?? recentMessages,
          genId: genId,
          finalAssistantText: ledgerText,
          targetMessage: ledgerTargetMessage ?? targetMessage,
        ),
      );
    }
  }

  /// Re-run the POST-cleaner against an existing assistant message.
  ///
  /// Unlike the auto post-generation [run] which cleans the just-streamed
  /// trailing message, this:
  ///   - Takes the **final** (agentSwipes[0]) text as the cleaner input.
  ///   - Appends a NEW 'cleaned' sub-swipe (does not overwrite existing).
  ///   - Streams the rewrite into the bubble as it arrives.
  ///   - Has no `genId` abort (genId = -1) — the user can still stop via
  ///     the Stop button which cancels the in-flight cleaner token.
  Future<void> rerun({
    required String sessionId,
    required String messageId,
  }) async {
    if (!ctx.ref.mounted) return;

    // Refuse concurrent cleaner runs — the pre-created swipe tracking
    // is single-slot; a second run would clobber it.
    if (_cleanerCancelToken != null) {
      debugPrint('[PostCleaner] rerun skipped: cleaner already in flight');
      return;
    }

    final pipeline = ctx.ref.read(pipelineSettingsProvider);

    final session = await ctx.ref.read(chatRepoProvider).getById(sessionId);
    if (session == null) return;
    final targetIndex = session.messages.indexWhere((m) => m.id == messageId);
    if (targetIndex < 0) return;
    final target = session.messages[targetIndex];
    if (target.role != 'assistant' || target.isError || target.isTyping) {
      return;
    }
    final finalText = target.agentSwipes.isNotEmpty
        ? target.agentSwipes[0].content
        : target.content;
    if (finalText.trim().isEmpty) return;

    final bookRepo = ctx.ref.read(memoryBookRepoProvider);
    final book = await bookRepo.getBySessionId(sessionId);
    if (!ctx.ref.mounted) return;
    if (book == null) {
      debugPrint('[PostCleaner] rerun skipped: no memory book for session');
      return;
    }

    // Collect recent chat history before the target message for continuity
    // checks (same window as the auto path).
    final maxHistory = pipeline.cleaner.postCleanerHistoryMessages;
    final recentMessages = <ChatMessage>[];
    if (maxHistory > 0 && targetIndex > 0) {
      final start = (targetIndex - maxHistory).clamp(0, targetIndex);
      for (var i = start; i < targetIndex; i++) {
        final m = session.messages[i];
        if (m.content.trim().isEmpty || m.isError) continue;
        recentMessages.add(m);
      }
    }

    // Load broadcast blocks (same as auto path).
    // Cleaner is Studio-only — skip rerun when Studio is disabled.
    List<String> broadcastBlocks = const [];
    var studioConfigEnabled = false;
    var studioCleanerApiConfigId = '';
    try {
      final studioConfig = await ctx.ref
          .read(studioConfigRepoProvider)
          .getBySessionId(sessionId);
      broadcastBlocks = studioConfig?.broadcastBlocks ?? const [];
      studioConfigEnabled = studioConfig?.enabled == true;
      studioCleanerApiConfigId = studioConfig?.cleanerApiConfigId ?? '';
    } catch (e) {
      debugPrint(
        '[PostCleaner] rerun broadcast load failed session=$sessionId error=$e',
      );
    }
    if (!ctx.ref.mounted) return;

    if (!studioConfigEnabled) {
      debugPrint('[PostCleaner] rerun skipped — Studio not enabled');
      return;
    }

    // Resolve the Studio cleaner slot (fail-explicit).
    final AuxApiConfig cleanerConfig;
    try {
      cleanerConfig = await StudioSlotResolver(ctx.ref).resolve(
        apiConfigId: studioCleanerApiConfigId,
        errorLabel: 'post-cleaner-rerun',
        modelOverride: pipeline.cleaner.postCleanerModel,
      );
    } catch (e) {
      debugPrint('[PostCleaner] rerun slot resolution failed: $e');
      return;
    }
    if (!ctx.ref.mounted) return;

    // Manual rerun has no promptPayload snapshot (the original generation
    // context is gone), so the character-audit pass is skipped.
    final character = ctx.ref.read(characterByIdProvider(ctx.charId));
    try {
      await _executeAndApplyCleaner(
        sessionId: sessionId,
        genId: -1,
        targetMessage: target,
        assistantText: finalText,
        recentMessages: recentMessages,
        broadcastBlocks: broadcastBlocks,
        pipeline: pipeline,
        promptPayload: null,
        character: character,
        cleanerConfig: cleanerConfig,
      );
    } catch (e) {
      debugPrint('[PostCleaner] rerun failed session=$sessionId error=$e');
      if (ctx.ref.mounted) {
        ctx.ref.read(streamingStateProvider(ctx.charId).notifier).state =
            const StreamingState();
        ctx.ref.read(postCleanerStateProvider.notifier).state =
            const PostCleanerState.idle();
        if (_preCreatedCleanerSwipeId >= 0) {
          try {
            await ctx.ref
                .read(chatRepoProvider)
                .removeAgentSwipe(
                  sessionId: sessionId,
                  messageId: target.id,
                  agentSwipeId: _preCreatedCleanerSwipeId,
                );
          } catch (_) {}
        }
      }
    } finally {
      if (_auditCancelToken != null && !_auditCancelToken!.isCancelled) {
        _auditCancelToken!.cancel();
      }
      _auditCancelToken = null;
      _cleanerCancelToken = null;
      ctx.ref.read(cleanerCancelTokenProvider.notifier).state = null;
      _lastStreamedText = '';
      _preCreatedCleanerSwipeId = -1;
      _preCreatedMessageId = null;
    }
  }
}
