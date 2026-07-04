import '../../../../core/models/character.dart';
import '../../../../core/services/generation_notification_service.dart';
import '../../../cloud_sync/sync_provider.dart' show notifySyncMessageGenerated;
import '../../chat_state.dart';
import '../../utils/message_preview.dart';
import 'stage_context.dart';

/// Stage 3 / 2: Sync + notification. Runs immediately after generation
/// completes (or after regen rollback handling). Extracted from the old
/// `_runPostTextSide` so that image tags and extension blocks can be
/// scheduled independently (and after the cleaner when Studio is on).
class SyncNotificationStage {
  final StageContext ctx;

  SyncNotificationStage(this.ctx);

  Future<void> run({
    required ChatState result,
    required int genId,
    required Character? character,
    required GenerationNotificationService notifService,
  }) async {
    if (!ctx.ref.mounted || !ctx.abortHandler.isCurrentGen(genId)) return;

    notifySyncMessageGenerated(ctx.ref);

    final preview = buildMessagePreview(result.session?.messages ?? const []);
    await notifService.onGenerationCompleted(
      character?.name ?? 'Unknown',
      ctx.charId,
      messagePreview: preview,
      sessionId: result.session?.id,
      msgId: result.session?.messages.isNotEmpty == true
          ? result.session!.messages.last.id
          : null,
      avatarPath: character?.avatarPath,
    );
  }
}
