import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/block_config.dart';
import '../../models/block_run_status.dart';
import '../../models/info_block.dart';
import '../../../../core/state/character_provider.dart';
import '../../../../core/state/persona_resolution.dart';
import '../../providers/info_blocks_provider.dart';
import '../ext_blocks_panel_builder.dart';
import '../macro_expander.dart';
import '../../../../features/chat/bridge/chat_bridge_registry.dart';

class BlockPanelUpdater {
  BlockPanelUpdater(this._ref);

  final Ref _ref;

  Future<void>? _panelJsChain;
  DateTime? _lastStreamPanelAt;

  void _enqueuePanelJs(Future<void> Function() work) {
    _panelJsChain = (_panelJsChain ?? Future.value()).then((_) async {
      try {
        await work();
      } catch (e, st) {
        debugPrint('[ExtPostGen] panel JS update failed: $e\n$st');
      }
    });
  }

  void refreshForMessage(
    String charId,
    String sessionId,
    String messageId,
    int swipeId,
  ) {
    _enqueuePanelJs(() async {
      final bridge = _ref.read(chatBridgeRegistryProvider(charId));
      if (bridge == null) return;
      final blocks = ExtBlocksPanelBuilder.build(
        _ref,
        sessionId: sessionId,
        messageId: messageId,
        swipeId: swipeId,
      );
      if (blocks.isEmpty) {
        await bridge.hideExtBlocksPanel(messageId);
        return;
      }
      await bridge.showExtBlocksPanel(
        messageId,
        _expandBlockPayloads(blocks, charId, sessionId),
        canRunAll: ExtBlocksPanelBuilder.canRunAll(blocks),
      );
    });
  }

  Future<void> patchOrRefresh({
    required String charId,
    required String sessionId,
    required String messageId,
    required String blockId,
    required int swipeId,
    required String content,
    required String status,
  }) async {
    final bridge = _ref.read(chatBridgeRegistryProvider(charId));
    if (bridge == null) return;
    final patched = await bridge.patchExtBlockContent(
      messageId: messageId,
      blockId: blockId,
      content: content,
      status: status,
    );
    if (patched) return;
    refreshForMessage(charId, sessionId, messageId, swipeId);
  }

  void publishStreamingContent({
    required String charId,
    required String sessionId,
    required String messageId,
    required InfoBlock placeholder,
    required String content,
    bool force = false,
  }) {
    final now = DateTime.now();
    if (!force &&
        _lastStreamPanelAt != null &&
        now.difference(_lastStreamPanelAt!) <
            const Duration(milliseconds: 80)) {
      return;
    }
    _lastStreamPanelAt = now;
    final updated = placeholder.copyWith(
      content: content,
      status: BlockRunStatus.running,
    );
    _ref.read(infoBlocksProvider(sessionId).notifier).addOrReplace(updated);
    _enqueuePanelJs(
      () => patchOrRefresh(
        charId: charId,
        sessionId: sessionId,
        messageId: messageId,
        blockId: placeholder.blockId,
        swipeId: placeholder.swipeId,
        content: _expandContent(content, charId, sessionId),
        status: BlockRunStatus.running.name,
      ),
    );
  }

  List<Map<String, dynamic>> _expandBlockPayloads(
    List<Map<String, dynamic>> blocks,
    String charId,
    String sessionId,
  ) {
    return [
      for (final block in blocks)
        {
          ...block,
          if (block['content'] is String)
            'content': _expandContent(
              block['content'] as String,
              charId,
              sessionId,
            ),
        },
    ];
  }

  String _expandContent(String content, String charId, String sessionId) {
    final character = _ref.read(characterByIdProvider(charId));
    final persona = _ref.read(
      effectivePersonaForChatProvider((charId: charId, sessionId: sessionId)),
    );
    return expand(
      content,
      MacroContext(character: character, persona: persona?.name),
    );
  }


  void Function(String)? makeStreamHandler({
    required BlockConfig blockConfig,
    required String charId,
    required String sessionId,
    required String messageId,
    required InfoBlock placeholder,
  }) {
    if (!blockConfig.streamToPanel) return null;
    return (partial) => publishStreamingContent(
      charId: charId,
      sessionId: sessionId,
      messageId: messageId,
      placeholder: placeholder,
      content: partial,
    );
  }
}
