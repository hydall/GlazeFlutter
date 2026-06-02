import '../../../core/db/repositories/info_blocks_repository.dart';
import '../../../core/models/chat_message.dart';
import '../models/extension_preset.dart';
import '../models/info_block.dart';

/// Инжектирует инфоблоки в историю сообщений для промпта
class InfoBlockInjector {
  final InfoBlocksRepository _repository;

  InfoBlockInjector(this._repository);

  /// Инжектирует инфоблоки в историю сообщений для промпта
  Future<List<ChatMessage>> injectBlocks({
    required List<ChatMessage> messages,
    required String sessionId,
    required ExtensionPreset preset,
  }) async {
    if (!preset.blocks.any((b) => b.enabled && b.inject)) {
      return messages; // Ничего не инжектируем
    }

    // Группируем блоки по injectDepth
    final blocksByDepth = <int, List<InfoBlock>>{};

    for (final block in preset.blocks.where((b) => b.enabled && b.inject)) {
        final recentBlocks = await _repository.getRecentBlocks(
          sessionId,
          block.name,
          1,
        );

      if (recentBlocks.isNotEmpty) {
        blocksByDepth.putIfAbsent(block.injectDepth, () => []);
        blocksByDepth[block.injectDepth]!.addAll(recentBlocks);
      }
    }

    // Инжектируем блоки в историю
    final result = List<ChatMessage>.from(messages);

    for (final entry in blocksByDepth.entries) {
      final depth = entry.key;
      final blocks = entry.value;

      // Находим assistant сообщение на нужной глубине
      final targetIndex = _findAssistantMessageByDepth(result, depth);
      if (targetIndex != null) {
        // Добавляем блоки в конец сообщения
        final blockContent = blocks.map((b) => b.content).join('\n');
        result[targetIndex] = result[targetIndex].copyWith(
          content: '${result[targetIndex].content}\n\n$blockContent',
        );
      }
    }

    return result;
  }

  int? _findAssistantMessageByDepth(List<ChatMessage> messages, int depth) {
    // depth = -1 → перед последним user сообщением
    // depth = -2 → перед вторым с конца user сообщением
    // depth = 1 → после первого assistant сообщения
    // depth = 2 → после второго assistant сообщения

    if (depth < 0) {
      // Ищем с конца
      final userMessages = messages.where((m) => m.role == 'user').toList();
      final targetUserIndex = userMessages.length + depth;
      if (targetUserIndex < 0) return null;

      // Ищем assistant сообщение перед этим user
      for (int i = messages.indexOf(userMessages[targetUserIndex]) - 1; i >= 0; i--) {
        if (messages[i].role == 'assistant') return i;
      }
    } else {
      // Ищем с начала
      final assistantMessages = messages.where((m) => m.role == 'assistant').toList();
      final targetIndex = depth - 1;
      if (targetIndex >= assistantMessages.length) return null;
      return messages.indexOf(assistantMessages[targetIndex]);
    }

    return null;
  }
}
