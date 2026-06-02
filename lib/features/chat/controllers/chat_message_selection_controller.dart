import '../../../core/models/chat_message.dart';
import '../chat_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Manages multi-select state and bulk message actions in chat.
class ChatMessageSelectionController {
  bool isSelectionMode = false;
  Set<String> selectedMessageIds = {};

  void updateSelection(Iterable<String> ids) {
    selectedMessageIds = ids.toSet();
    isSelectionMode = selectedMessageIds.isNotEmpty;
  }

  void clearSelection() {
    isSelectionMode = false;
    selectedMessageIds.clear();
  }

  bool allSelectedHidden(List<ChatMessage> messages) {
    if (selectedMessageIds.isEmpty) return false;
    return selectedMessageIds.every((id) {
      final idx = messages.indexWhere((m) => m.id == id);
      return idx >= 0 && messages[idx].isHidden;
    });
  }

  Future<void> hideSelected(WidgetRef ref, String charId, List<ChatMessage> messages) async {
    final notifier = ref.read(chatProvider(charId).notifier);
    for (final id in selectedMessageIds) {
      final idx = messages.indexWhere((m) => m.id == id);
      if (idx >= 0) await notifier.toggleMessageHidden(idx);
    }
    clearSelection();
  }

  Future<void> deleteSelected(WidgetRef ref, String charId, List<ChatMessage> messages) async {
    final notifier = ref.read(chatProvider(charId).notifier);
    final indices = selectedMessageIds
        .map((id) => messages.indexWhere((m) => m.id == id))
        .where((idx) => idx >= 0)
        .toList()
      ..sort((a, b) => b.compareTo(a));
    for (final idx in indices) {
      await notifier.deleteMessage(idx);
    }
    clearSelection();
  }
}
