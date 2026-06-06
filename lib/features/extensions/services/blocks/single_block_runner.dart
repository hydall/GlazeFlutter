import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../../core/models/character.dart';
import '../../../../core/models/chat_message.dart';
import '../../../../core/models/persona.dart';
import '../../models/block_config.dart';
import '../../models/extension_preset.dart';
import '../../models/info_block.dart';
import 'block_context.dart';
import 'block_handler.dart';
import 'block_status_tracker.dart';

class SingleBlockRunner {
  const SingleBlockRunner({
    required this.statusTracker,
    required this.refreshPanelForMessage,
    required this.handlerFor,
  });

  final BlockStatusTracker statusTracker;
  final BlockPanelRefresh refreshPanelForMessage;
  final BlockHandler Function(BlockType type) handlerFor;

  Future<InfoBlock?> run({
    required String charId,
    required String sessionId,
    required String messageId,
    required List<ChatMessage> messages,
    required BlockConfig blockConfig,
    required ExtensionPreset preset,
    required Character character,
    required Persona? persona,
    required String? previousOutput,
    required CancelToken cancelToken,
    String? reuseBlockId,
  }) async {
    if (cancelToken.isCancelled) return null;

    debugPrint(
      '[ExtPostGen] _runSingleBlock START: name="${blockConfig.name}" type=${blockConfig.type.name} order=${blockConfig.order} reuse=${reuseBlockId ?? "new"}',
    );

    final prepared = await statusTracker.prepare(
      charId: charId,
      sessionId: sessionId,
      messageId: messageId,
      blockConfig: blockConfig,
      reuseBlockId: reuseBlockId,
    );
    final placeholderId = prepared.placeholderId;
    final placeholder = prepared.placeholder;

    refreshPanelForMessage(charId, sessionId, messageId);

    final context = BlockContext(
      charId: charId,
      sessionId: sessionId,
      messageId: messageId,
      messages: messages,
      blockConfig: blockConfig,
      preset: preset,
      character: character,
      persona: persona,
      previousOutput: previousOutput,
      cancelToken: cancelToken,
      placeholderId: placeholderId,
      placeholder: placeholder,
    );

    try {
      return await handlerFor(blockConfig.type).handle(context);
    } catch (e) {
      if (!cancelToken.isCancelled) {
        debugPrint('[ExtPostGen] Error in block "${blockConfig.name}": $e');
        return statusTracker.markErrorForPlaceholder(
          charId: charId,
          sessionId: sessionId,
          messageId: messageId,
          placeholderId: placeholderId,
          placeholder: placeholder,
          errorMessage: e.toString(),
        );
      }
      return null;
    }
  }
}
