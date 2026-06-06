import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/chat_message.dart';
import '../../extensions/providers/info_blocks_provider.dart';
import '../../extensions/services/ext_blocks_panel_builder.dart';
import '../bridge/chat_bridge_controller.dart';

/// Refresh / sync helpers for the inline ext-block panels rendered
/// by the chat WebView. Extracted from `chat_webview_widget.dart` so
/// the widget only calls `refreshForMessage` and `syncForSession`
/// without owning the panel-visibility / panel-blocks Riverpod lookups.
///
/// Pure functions on top of a [WidgetRef] and a [ChatBridgeController]
/// reference. The `ready` getter guards the bridge-dependent paths.
class ChatWebViewPanelRefresher {
  ChatWebViewPanelRefresher({
    required this.ref,
    required this.bridge,
    required this.ready,
    required this.messages,
  });

  final WidgetRef ref;
  final ChatBridgeController? bridge;
  final bool Function() ready;
  final List<ChatMessage> Function() messages;

  /// Refresh the ext-block panel for a single message: hide it if the
  /// `extBlocksPanelVisibleProvider` says so, otherwise show with the
  /// current blocks / canRunAll from Riverpod.
  Future<void> refreshForMessage(String sessionId, String messageId) async {
    final b = bridge;
    if (b == null || !ready()) return;
    final isLastAssistant = messageId == _lastAssistantMessageId();
    final panelKey = (sessionId: sessionId, messageId: messageId);
    final visibilityKey = (
      sessionId: sessionId,
      messageId: messageId,
      isLastAssistant: isLastAssistant,
    );
    if (!ref.read(extBlocksPanelVisibleProvider(visibilityKey))) {
      await b.hideExtBlocksPanel(messageId);
      return;
    }
    final blocks = ref.read(extBlocksPanelBlocksProvider(panelKey));
    final canRunAll = ref.read(extBlocksPanelCanRunAllProvider(panelKey));
    await b.showExtBlocksPanel(messageId, blocks, canRunAll: canRunAll);
  }

  /// Refresh the ext-block panel for every assistant/character message
  /// in the current chat. Used after a session switch and after any
  /// ext-block DB change.
  Future<void> syncForSession(String? sessionId) async {
    final sid = sessionId;
    if (sid == null || sid.isEmpty) return;
    final b = bridge;
    if (b == null || !ready()) return;
    await ref.read(infoBlocksProvider(sid).notifier).refresh();
    for (final msg in messages()) {
      if (msg.role != 'assistant' && msg.role != 'character') continue;
      await refreshForMessage(sid, msg.id);
    }
  }

  String? _lastAssistantMessageId() {
    for (int i = messages().length - 1; i >= 0; i--) {
      final m = messages()[i];
      if (m.role == 'assistant' || m.role == 'character') return m.id;
    }
    return null;
  }
}
