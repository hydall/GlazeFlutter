import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/chat_message.dart';
import '../../../chat/bridge/chat_bridge_registry.dart';
import '../../models/block_config.dart';
import '../js_engine_service.dart';
import 'js_block_executor.dart';

class PeriodicJsBlockRunner {
  const PeriodicJsBlockRunner({required this.ref});

  final Ref ref;

  Future<String?> run({
    required String charId,
    required BlockConfig block,
    required List<ChatMessage> contextMessages,
  }) async {
    if (block.type != BlockType.jsRunner) {
      throw ArgumentError(
        'runJsBlock only supports BlockType.jsRunner (got ${block.type.name})',
      );
    }
    final script = block.prompt.isNotEmpty ? block.prompt : block.script;
    if (script.isEmpty) {
      return null;
    }
    final engine = JsEngineService.instance;
    final bridge = ref.read(chatBridgeRegistryProvider(charId));
    if (!engine.isReady && bridge == null) {
      debugPrint(
        '[ExtPostGen] runJsBlock: no engine or bridge (block "${block.name}")',
      );
      return null;
    }
    final cancelToken = CancelToken();
    try {
      if (engine.isReady) {
        try {
          final contextMap = JsBlockExecutor.jsContextMap(
            messages: contextMessages
                .map((m) => {'role': m.role, 'text': m.content})
                .toList(),
            character: null, // no character payload for periodic
            sessionId: '',
            previousOutput: null,
          );
          // Periodic ticks have no character/session payload; the script
          // can still read `messages` from the context (empty list by default).
          final patchedContext = Map<String, dynamic>.from(contextMap)
            ..['characterId'] = charId
            ..['sessionId'] = '';
          return await engine.runScript(
            script: script,
            context: patchedContext,
            cancelToken: cancelToken,
          );
        } on HeadlessUnavailableError catch (_) {
          // Fall through to visual bridge.
        }
      }
      final visualBridge = bridge;
      if (visualBridge == null) {
        return null;
      }
      return await visualBridge.runJsBlock(
        script: script,
        messages: contextMessages,
        character: null,
        sessionId: '',
        previousOutput: null,
        contextMessageCount: -1,
        cancelToken: cancelToken,
      );
    } catch (e) {
      debugPrint('[ExtPostGen] runJsBlock failed: $e');
      return null;
    }
  }
}
