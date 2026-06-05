import '../../../core/db/repositories/info_blocks_repository.dart';
import '../../../core/models/chat_message.dart';
import '../models/extension_preset.dart';

/// Инжектирует инфоблоки в историю сообщений перед отправкой промпта LLM.
///
/// Логика: для каждого включённого блока с inject=true берём последние
/// [BlockConfig.injectLastN] assistant-сообщений и вставляем перед каждым
/// из них сгенерированный ранее инфоблок этого блока.
class InfoBlockInjector {
  final InfoBlocksRepository _repository;

  InfoBlockInjector(this._repository);

  Future<List<ChatMessage>> injectBlocks({
    required List<ChatMessage> messages,
    required String sessionId,
    required ExtensionPreset preset,
  }) async {
    final injectableBlocks =
        preset.blocks.where((b) => b.enabled && b.inject).toList();
    if (injectableBlocks.isEmpty) return messages;

    // Collect assistant messages from the end.
    final assistantIndices = <int>[];
    for (int i = messages.length - 1; i >= 0; i--) {
      if (messages[i].role == 'assistant') assistantIndices.add(i);
    }

    if (assistantIndices.isEmpty) return messages;

    final result = List<ChatMessage>.from(messages);

    for (final blockConfig in injectableBlocks) {
      final n = blockConfig.injectLastN.clamp(0, assistantIndices.length);
      if (n <= 0) continue;

      // assistantIndices is newest-first; take first n.
      final targetIndices = assistantIndices.take(n).toList();

      for (final idx in targetIndices) {
        final msg = result[idx];
        final blocks =
            await _repository.getByMessageId(sessionId, msg.id);
        final blockResults =
            blocks.where((b) => b.blockName == blockConfig.name).toList();
        if (blockResults.isEmpty) continue;

        final injected =
            blockResults.map((b) => b.content).join('\n').trim();
        if (injected.isEmpty) continue;

        result[idx] = msg.copyWith(
          content: '${msg.content}\n\n$injected',
        );
      }
    }

    return result;
  }
}
