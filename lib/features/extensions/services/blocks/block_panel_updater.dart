import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/block_config.dart';
import '../../models/block_run_status.dart';
import '../../models/info_block.dart';
import '../../providers/info_blocks_provider.dart';
import '../ext_blocks_panel_builder.dart';
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

  void refreshForMessage(String charId, String sessionId, String messageId) {
    _enqueuePanelJs(() async {
      final bridge = _ref.read(chatBridgeRegistryProvider(charId));
      if (bridge == null) return;
      final blocks = ExtBlocksPanelBuilder.build(
        _ref,
        sessionId: sessionId,
        messageId: messageId,
      );
      if (blocks.isEmpty) {
        await bridge.hideExtBlocksPanel(messageId);
        return;
      }
      await bridge.showExtBlocksPanel(
        messageId,
        blocks,
        canRunAll: ExtBlocksPanelBuilder.canRunAll(blocks),
      );
    });
  }

  Future<void> patchOrRefresh({
    required String charId,
    required String sessionId,
    required String messageId,
    required String blockId,
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
    refreshForMessage(charId, sessionId, messageId);
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
        content: content,
        status: BlockRunStatus.running.name,
      ),
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
