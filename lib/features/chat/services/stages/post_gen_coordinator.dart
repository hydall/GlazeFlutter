import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../core/models/character.dart';
import '../../../../core/services/generation_notification_service.dart';
import '../../../../core/state/db_provider.dart';
import '../../chat_generation_service.dart';
import '../../chat_state.dart';
import 'chat_embed_stage.dart';
import 'cleaner_stage.dart';
import 'ext_blocks_stage.dart';
import 'image_tag_stage.dart';
import 'ledger_stage.dart';
import 'memory_draft_stage.dart';
import 'stage_context.dart';
import 'sync_notification_stage.dart';
import 'write_loop_stage.dart';

/// Post-generation task scheduler. Replaces the old inline postGenFutures
/// blocks in both the normal and regen paths. Implements the pipeline order
/// from PLAN_STUDIO_PIPELINE_SEPARATION.md §New Pipeline Order:
///
/// Studio ON:
///   3. Sync + notification (immediate, awaited)
///   4. Post-cleaner (fact-checker + rewrite + ext blocks + ledger)
///   5. Image tags — on canonical text, after cleaner
///   6. Write-loop — on canonical text, after cleaner
///   8. Embed (parallel fire-and-forget)
///   9. Auto-create drafts (parallel fire-and-forget)
///
/// Studio OFF:
///   2. Sync + notification (immediate, awaited)
///   3. Image tags (immediate)
///   4. Ext blocks (immediate, agentSwipeId=-1)
///   5. Embed (parallel fire-and-forget)
///   6. Auto-create drafts (parallel fire-and-forget)
class PostGenCoordinator {
  final StageContext ctx;
  final SyncNotificationStage syncStage;
  final ChatEmbedStage embedStage;
  final MemoryDraftStage draftStage;
  final ImageTagStage imageTagStage;
  final ExtBlocksStage extBlocksStage;
  final WriteLoopStage writeLoopStage;
  final LedgerStage ledgerStage;
  final CleanerStage cleanerStage;

  PostGenCoordinator(this.ctx)
      : syncStage = SyncNotificationStage(ctx),
        embedStage = ChatEmbedStage(ctx),
        draftStage = MemoryDraftStage(ctx),
        imageTagStage = ImageTagStage(ctx),
        extBlocksStage = ExtBlocksStage(ctx),
        writeLoopStage = WriteLoopStage(ctx),
        ledgerStage = LedgerStage(ctx),
        cleanerStage = CleanerStage(
          ctx,
          extBlocks: ExtBlocksStage(ctx),
          ledger: LedgerStage(ctx),
        );

  Future<void> run({
    required ChatState result,
    required int genId,
    required Character? character,
    required ChatGenerationService service,
    required GenerationNotificationService notifService,
    String? regenTargetId,
  }) async {
    if (!ctx.ref.mounted || !ctx.abortHandler.isCurrentGen(genId)) return;
    if (result.session == null) return;

    final sessionId = result.session!.id;

    // Stage 3 / 2: Sync + notification (immediate, awaited).
    await syncStage.run(
      result: result,
      genId: genId,
      character: character,
      notifService: notifService,
    );
    if (!ctx.ref.mounted || !ctx.abortHandler.isCurrentGen(genId)) return;

    // Keep the foreground service alive for post-gen tasks so the OS
    // doesn't suspend the app (screen off) while cleaner, write-loop,
    // ledger, or extension blocks are still running.
    await notifService.onPostGenStarted();

    // Determine Studio status to branch the post-gen sequence.
    var studioEnabled = false;
    try {
      final studioConfig = await ctx.ref
          .read(studioConfigRepoProvider)
          .getBySessionId(sessionId);
      studioEnabled = studioConfig?.enabled == true;
    } catch (e) {
      debugPrint(
        '[PostGenCoordinator] StudioConfig load failed session=$sessionId: $e',
      );
    }
    if (!ctx.ref.mounted || !ctx.abortHandler.isCurrentGen(genId)) return;

    final postGenFutures = <Future<void>>[];

    // Stage 8 / 5: Embed raw chat-message chunks (parallel fire-and-forget,
    // independent of cleaner — operates on raw message text, not the cleaned
    // swipe). Pairs with MessageRecallService cosine search.
    postGenFutures.add(
      embedStage.run(
        sessionId: sessionId,
        messages: result.session!.messages,
        genId: genId,
      ),
    );

    // Stage 9 / 6: Auto-create memory drafts (parallel fire-and-forget,
    // no LLM — just a planner over the MemoryBook).
    postGenFutures.add(draftStage.run(result.session));

    if (studioEnabled) {
      // Studio ON: cleaner runs first, then image tags + write-loop on
      // canonical text. Ledger is launched from inside CleanerStage.
      // Ext blocks are launched from inside CleanerStage's branches
      // (bound to the swipe the user will see).
      final cleanerTask = cleanerStage.run(
        sessionId: sessionId,
        messages: result.session!.messages,
        genId: genId,
        promptPayload: result.promptPayload,
        character: character,
      );
      postGenFutures.add(cleanerTask);

      // Stage 5: Image tags — on canonical text, after cleaner. Re-read
      // the session from DB so image tags bind to the cleaned swipe.
      postGenFutures.add(
        cleanerTask.then((_) async {
          if (!ctx.ref.mounted || !ctx.abortHandler.isCurrentGen(genId)) return;
          final refreshed = await ctx.ref.read(chatRepoProvider).getById(sessionId);
          if (refreshed == null) return;
          await imageTagStage.run(
            result: ChatState(session: refreshed),
            genId: genId,
            service: service,
          );
        }),
      );

      // Stage 6: Write-loop — on canonical text, after cleaner.
      postGenFutures.add(
        cleanerTask.then((_) => writeLoopStage.run(
              sessionId: sessionId,
              messages: result.session!.messages,
              genId: genId,
              regenTargetId: regenTargetId,
            )),
      );
    } else {
      // Studio OFF: image tags + ext blocks run immediately (no cleaner).
      postGenFutures.add(
        imageTagStage.run(
          result: result,
          genId: genId,
          service: service,
        ),
      );
      if (character != null) {
        postGenFutures.add(
          extBlocksStage.launchForSwipe(
            session: result.session!,
            character: character,
            agentSwipeId: -1,
          ),
        );
      }
    }

    // Track all post-gen tasks and release the foreground hold when
    // they all complete (success or failure).
    unawaited(
      Future.wait(postGenFutures).whenComplete(() {
        notifService.onPostGenFinished();
      }),
    );
  }
}
