import '../models/preset.dart';
import 'history_assembler.dart';
import 'prompt_builder.dart';

const _mandatoryBlockIds = {'char_card', 'char_personality', 'user_persona'};

/// The Studio chat-time context split: static (char/persona/scenario), dynamic
/// (memory/summary/lore), per-history messages, and a by-block-id index.
/// Extracted from `MemoryStudioService` (plan §2).
class StudioContextBuckets {
  final List<PromptMessage> staticContext;
  final List<PromptMessage> history;
  final List<PromptMessage> dynamicContext;
  final Map<String, List<PromptMessage>> byKind;

  const StudioContextBuckets({
    required this.staticContext,
    required this.history,
    required this.dynamicContext,
    required this.byKind,
  });

  List<PromptMessage> messagesForKind(String kind) =>
      byKind[kind] ?? const <PromptMessage>[];

  String joinKind(String kind) =>
      messagesForKind(kind).map((message) => message.content).join('\n\n');

  String taggedDynamicContent(String tag) {
    final buffer = StringBuffer();
    final pattern = RegExp(
      '<$tag>\\s*([\\s\\S]*?)\\s*</$tag>',
      caseSensitive: false,
    );
    for (final message in dynamicContext) {
      for (final match in pattern.allMatches(message.content)) {
        final content = match.group(1)?.trim();
        if (content != null && content.isNotEmpty) {
          if (buffer.isNotEmpty) buffer.writeln('\n');
          buffer.write(content);
        }
      }
    }
    return buffer.toString();
  }
}

/// Builds [StudioContextBuckets] from a [PromptResult], classifying each
/// message into static / dynamic / history buckets and synthesizing mandatory
/// character/persona fallbacks when the preset did not emit them. Pure
/// specialist extracted from `MemoryStudioService` (plan §2).
class StudioContextBucketizer {
  const StudioContextBucketizer();

  StudioContextBuckets bucketize(
    PromptResult promptResult, {
    required PromptPayload promptPayload,
  }) {
    final staticIds = <String>{
      'char_card',
      'char_personality',
      'user_persona',
      'scenario',
      'example_dialogue',
      'authors_note',
    };
    final dynamicIds = <String>{
      'memory',
      'summary',
      'worldInfoBefore',
      'worldInfoAfter',
      'guided_generation',
    };
    final presetBlockNames = <String, String>{
      for (final b in promptPayload.preset?.blocks ?? const <PresetBlock>[])
        normalizeBlockId(b.id): b.name,
    };
    final mandatoryFallback = _mandatoryCharacterPersonaContext(
      promptResult,
      promptPayload,
      presetBlockNames,
    ).where((m) => !promptResult.messages.any((p) => p.blockId == m.blockId));

    final staticContext = <PromptMessage>[];
    final dynamicContext = <PromptMessage>[];
    final history = <PromptMessage>[];
    final byKind = <String, List<PromptMessage>>{};
    void addByKind(String kind, PromptMessage message) {
      byKind.putIfAbsent(kind, () => <PromptMessage>[]).add(message);
    }

    for (final message in promptResult.messages) {
      if (message.content.trim().isEmpty) continue;
      final blockId = message.blockId;
      if (message.isHistory) {
        history.add(message);
      } else if (blockId != null && staticIds.contains(blockId)) {
        addByKind(blockId, message);
      } else if (blockId != null && dynamicIds.contains(blockId)) {
        addByKind(blockId, message);
      } else if (_isStudioDynamicMessage(message, dynamicIds)) {
        dynamicContext.add(message);
      } else {
        staticContext.add(message);
      }
    }

    for (final m in mandatoryFallback) {
      final blockId = m.blockId;
      final fallback = PromptMessage(
        role: 'system',
        content:
            '[Mandatory fallback: ${_studioBlockLabel(m, presetBlockNames)}]\n${_trimForStudioContext(m.content, 6000)}',
        blockId: blockId,
        blockName: m.blockName,
      );
      if (blockId != null && blockId.isNotEmpty) {
        byKind
            .putIfAbsent(blockId, () => <PromptMessage>[])
            .insert(0, fallback);
      } else {
        staticContext.insert(0, fallback);
      }
    }

    return StudioContextBuckets(
      staticContext: staticContext,
      history: history,
      dynamicContext: dynamicContext,
      byKind: byKind,
    );
  }

  bool _isStudioDynamicMessage(PromptMessage message, Set<String> dynamicIds) {
    final blockId = message.blockId;
    if (message.isSummary || message.isLorebook) return true;
    if (blockId != null && dynamicIds.contains(blockId)) return true;
    if (blockId != null && blockId.startsWith('runtime_prompt:')) return true;

    final name = (message.blockName ?? '').toLowerCase();
    if (name.contains('dynamic') ||
        name.contains('memory') ||
        name.contains('summary') ||
        name.contains('lore') ||
        name.contains('world info') ||
        name.contains('arc') ||
        name.contains('entit')) {
      return true;
    }

    final content = message.content.toLowerCase();
    return content.contains('<lorebooks>') ||
        content.contains('<summary>') ||
        content.contains('<memory>') ||
        content.contains('<arc') ||
        content.contains('<entities>');
  }

  List<PromptMessage> _mandatoryCharacterPersonaContext(
    PromptResult promptResult,
    PromptPayload promptPayload,
    Map<String, String> presetBlockNames,
  ) {
    final existing = promptResult.messages
        .where((m) => _mandatoryBlockIds.contains(m.blockId))
        .where((m) => m.content.trim().isNotEmpty)
        .toList();
    final found = existing.map((m) => m.blockId).whereType<String>().toSet();
    final fallback = <PromptMessage>[...existing];
    if (!found.contains('char_card')) {
      final character = promptPayload.character;
      final parts = <String>[
        'Name: ${character.name}',
        if ((character.description ?? '').trim().isNotEmpty)
          'Description:\n${character.description}',
        if ((character.scenario ?? '').trim().isNotEmpty)
          'Scenario:\n${character.scenario}',
        if ((character.systemPrompt ?? '').trim().isNotEmpty)
          'System prompt:\n${character.systemPrompt}',
        if ((character.postHistoryInstructions ?? '').trim().isNotEmpty)
          'Post-history instructions:\n${character.postHistoryInstructions}',
        if ((character.mesExample ?? '').trim().isNotEmpty)
          'Example dialogue:\n${character.mesExample}',
      ];
      fallback.add(
        PromptMessage(
          role: 'system',
          content: parts.join('\n\n'),
          blockId: 'char_card',
          blockName: presetBlockNames['char_card'] ?? 'Character Card',
        ),
      );
    }
    if (!found.contains('char_personality') &&
        (promptPayload.character.personality ?? '').trim().isNotEmpty) {
      fallback.add(
        PromptMessage(
          role: 'system',
          content: promptPayload.character.personality!,
          blockId: 'char_personality',
          blockName: presetBlockNames['char_personality'] ?? 'Personality',
        ),
      );
    }
    if (!found.contains('user_persona')) {
      final persona = promptPayload.persona;
      if (persona != null && (persona.prompt ?? '').trim().isNotEmpty) {
        fallback.add(
          PromptMessage(
            role: 'system',
            content: 'Name: ${persona.name}\n\n${persona.prompt}',
            blockId: 'user_persona',
            blockName: presetBlockNames['user_persona'] ?? 'User Persona',
          ),
        );
      }
    }
    return fallback;
  }

  String _studioBlockLabel(
    PromptMessage msg,
    Map<String, String> presetBlockNames,
  ) {
    if ((msg.blockName ?? '').trim().isNotEmpty) return msg.blockName!;
    final id = msg.blockId;
    if (id != null && (presetBlockNames[id] ?? '').trim().isNotEmpty) {
      return presetBlockNames[id]!;
    }
    return id ?? msg.role;
  }

  String _trimForStudioContext(String text, int maxChars) {
    final trimmed = text.trim();
    if (trimmed.length <= maxChars) return trimmed;
    return '${trimmed.substring(0, maxChars)}...';
  }
}
