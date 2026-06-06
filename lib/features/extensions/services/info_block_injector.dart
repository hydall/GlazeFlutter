import '../../../core/models/chat_message.dart';
import '../models/block_config.dart';
import '../models/extension_preset.dart';
import '../models/info_block.dart';
import 'block_content_extractor.dart';

/// Minimal read surface used by [InfoBlockInjector] (implemented by [InfoBlocksRepository]).
abstract class InfoBlockReader {
  Future<List<InfoBlock>> getByMessageId(String sessionId, String messageId);
}

/// Инжектирует инфоблоки в историю перед сборкой основного промпта.
///
/// Для каждого блока с `inject=true` берём последние [BlockConfig.injectLastN]
/// assistant-сообщений и дописываем к **каждому** из них только **его**
/// сохранённый вывод этого блока (`content\\n\\n<block>`).
class InfoBlockInjector {
  final InfoBlockReader _repository;

  InfoBlockInjector(InfoBlockReader repository) : _repository = repository;

  Future<List<ChatMessage>> injectBlocks({
    required List<ChatMessage> messages,
    required String sessionId,
    required ExtensionPreset preset,
  }) async {
    final injectableBlocks =
        preset.blocks.where((b) => b.enabled && b.inject).toList();
    if (injectableBlocks.isEmpty) return messages;

    // Collect visible assistant messages from the end (newest first).
    final assistantIndices = <int>[];
    for (int i = messages.length - 1; i >= 0; i--) {
      final msg = messages[i];
      if (msg.isHidden || msg.isTyping) continue;
      if (msg.role == 'assistant' || msg.role == 'character') {
        assistantIndices.add(i);
      }
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

        final injected = blockResults
            .map((b) => _formatInjectedContent(blockConfig, b.content))
            .where((c) => c.trim().isNotEmpty)
            .join('\n')
            .trim();
        if (injected.isEmpty) continue;

        result[idx] = msg.copyWith(
          content: '${msg.content}\n\n${_injectSuffix(blockConfig, injected)}',
        );
      }
    }

    return result;
  }

  /// Text after the blank line and before [blockBody] in injected history.
  String _injectSuffix(BlockConfig blockConfig, String blockBody) {
    final prefix = blockConfig.injectPrefix;
    if (prefix.isEmpty) return blockBody;
    if (prefix.endsWith('\n')) return '$prefix$blockBody';
    return '$prefix\n$blockBody';
  }

  String _formatInjectedContent(BlockConfig blockConfig, String content) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return '';

    final template = blockConfig.template
        .trim()
        .replaceAll('{{name}}', blockConfig.name);
    if (template.isEmpty) return trimmed;

    final tag = blockTagName(blockConfig, template);
    final wrappedPattern = RegExp(
      '<$tag(\\s+[^>]*)?>[\\s\\S]*<\\/$tag>',
      caseSensitive: false,
    );
    if (wrappedPattern.hasMatch(trimmed)) return trimmed;

    return '<$tag>\n$trimmed\n</$tag>';
  }
}
