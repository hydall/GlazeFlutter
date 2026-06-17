import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/chat_message.dart';
import '../../../core/models/character.dart';
import '../../../core/llm/memory_draft_planner.dart';
import '../../../core/state/memory_settings_provider.dart';
import '../../../core/services/generation_notification_service.dart';
import '../../../core/state/db_provider.dart';
import '../../../core/utils/time_helpers.dart';
import '../../cloud_sync/sync_provider.dart' show notifySyncMessageGenerated;
import '../../chat_history/chat_history_provider.dart';
import '../abort_handler.dart';
import '../chat_generation_service.dart';
import '../chat_session_service.dart';
import '../chat_state.dart';
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
///   4. clear `restorationMessage` and `imgGenCancelToken` on completion
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
    }

    if (character != null && result.session != null) {
      await service.processExtensions(
        charId: charId,
        session: result.session!,
        character: character,
      );
      if (!ref.mounted || !abortHandler.isCurrentGen(genId)) return;
    }

    abortHandler.imgGenCancelToken = null;

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
}
