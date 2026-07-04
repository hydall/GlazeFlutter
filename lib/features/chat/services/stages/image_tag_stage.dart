import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../chat_generation_service.dart';
import '../../chat_state.dart';
import 'stage_context.dart';

/// Stage 5: Image tags. Operates on the canonical text — when Studio is
/// enabled this runs AFTER the cleaner completes (re-reads the session
/// from DB so image tags bind to the cleaned swipe, not the raw stream).
/// When Studio is off, this runs immediately after sync.
class ImageTagStage {
  final StageContext ctx;

  ImageTagStage(this.ctx);

  Future<void> run({
    required ChatState result,
    required int genId,
    required ChatGenerationService service,
  }) async {
    final imgCancelToken = CancelToken();
    ctx.abortHandler.imgGenCancelToken = imgCancelToken;

    try {
      await service.processImageTags(
        currentState: result,
        charId: ctx.charId,
        cancelToken: imgCancelToken,
        onStateUpdate: (s) {
          if (ctx.abortHandler.isCurrentGen(genId)) ctx.setState(AsyncData(s));
        },
      );
    } catch (e) {
      debugPrint(
        '[ImageTagStage] processImageTags failed (continuing): $e',
      );
    } finally {
      if (identical(ctx.abortHandler.imgGenCancelToken, imgCancelToken)) {
        ctx.abortHandler.imgGenCancelToken = null;
      }
    }
  }
}
