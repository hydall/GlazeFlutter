import '../../core/models/preset.dart';

const _stBlockIds = <String, String>{
  'chatHistory': 'chat_history',
  'charDescription': 'char_card',
  'charPersonality': 'char_personality',
  'personaDescription': 'user_persona',
  'dialogueExamples': 'example_dialogue',
  'worldInfoBefore': 'worldInfoBefore',
  'worldInfoAfter': 'worldInfoAfter',
  'scenario': 'scenario',
  'main': 'main',
  'nsfw': 'nsfw',
};

const _mandatoryBlockIds = <String>{
  'chat_history', 'char_card', 'char_personality', 'user_persona',
  'example_dialogue', 'worldInfoBefore', 'worldInfoAfter', 'scenario',
  'main', 'nsfw',
};

const _blockNameToId = <String, String>{
  'Chat History': 'chat_history',
  'charDescription': 'char_card',
  'Character Description': 'char_card',
  'charPersonality': 'char_personality',
  'Character Personality': 'char_personality',
  'personaDescription': 'user_persona',
  'User Persona': 'user_persona',
  'dialogueExamples': 'example_dialogue',
  'Dialogue Examples': 'example_dialogue',
};

String _normalizeImportedBlockId(String rawId, String name) {
  if (_stBlockIds.containsKey(rawId)) return _stBlockIds[rawId]!;
  if (_blockNameToId.containsKey(name)) return _blockNameToId[name]!;
  return rawId;
}

Preset parseSillyTavernPreset(Map<String, dynamic> json, String fileName) {
  final blocks = <PresetBlock>[];
  final regexes = <PresetRegex>[];

  final promptsList = json['prompts'] as List<dynamic>? ?? [];
  final promptsById = <String, Map<String, dynamic>>{};
  for (final p in promptsList) {
    final id = (p as Map<String, dynamic>)['identifier'] as String?;
    if (id != null) promptsById[id] = p;
  }

  List<Map<String, dynamic>> orderList = [];
  if (json['prompt_order'] is List) {
    final promptOrder = json['prompt_order'] as List<dynamic>;
    Map<String, dynamic>? preferredOrder;
    for (final o in promptOrder) {
      if (o is! Map<String, dynamic>) continue;
      final cid = o['character_id'];
      if (cid == 100001 && (o['order'] as List?)?.isNotEmpty == true) {
        preferredOrder = o;
        break;
      }
    }
    Map<String, dynamic> bestOrder = preferredOrder ?? promptOrder.fold<Map<String, dynamic>?>(
      null,
      (prev, current) {
        if (current is! Map<String, dynamic>) return prev;
        final prevLen = (prev?['order'] as List?)?.length ?? 0;
        final currentLen = (current['order'] as List?)?.length ?? 0;
        return currentLen > prevLen ? current : prev;
      },
    ) ?? {};
    final order = bestOrder['order'] as List<dynamic>? ?? [];
    for (final item in order) {
      if (item is Map<String, dynamic>) orderList.add(item);
    }
  }

  if (orderList.isEmpty) {
    orderList = promptsList.map((p) {
      final pm = p as Map<String, dynamic>;
      return {'identifier': pm['identifier'], 'enabled': pm['enabled'] ?? true};
    }).toList().cast<Map<String, dynamic>>();
  }

  final usedIdentifiers = <String>{};

  for (final item in orderList) {
    final identifier = item['identifier'] as String?;
    if (identifier == null) continue;
    final p = promptsById[identifier];
    if (p == null) continue;

    usedIdentifiers.add(identifier);

    final blockName = (p['name'] as String?) ?? identifier;
    final normalizedId = _normalizeImportedBlockId(identifier, blockName);
    final isMandatory = _mandatoryBlockIds.contains(normalizedId);
    final isEnabled = item['enabled'] as bool? ?? p['enabled'] as bool? ?? true;

    String insertionMode;
    int? depth;
    if (normalizedId == 'chat_history') {
      insertionMode = 'relative';
    } else if (p['injection_position'] == 1) {
      insertionMode = 'depth';
      depth = p['injection_depth'] as int? ?? 4;
    } else {
      insertionMode = 'relative';
    }

    blocks.add(PresetBlock(
      id: normalizedId,
      name: blockName,
      role: (p['role'] as String?) ?? 'system',
      content: isMandatory ? '' : ((p['content'] as String?) ?? ''),
      enabled: isEnabled,
      insertionMode: insertionMode,
      depth: depth,
    ));
  }

  for (final p in promptsList) {
    final pm = p as Map<String, dynamic>;
    final identifier = pm['identifier'] as String?;
    if (identifier == null || usedIdentifiers.contains(identifier)) continue;
    usedIdentifiers.add(identifier);

    final blockName = (pm['name'] as String?) ?? identifier;
    final normalizedId = _normalizeImportedBlockId(identifier, blockName);
    final isMandatory = _mandatoryBlockIds.contains(normalizedId);
    final isEnabled = pm['enabled'] as bool? ?? true;

    String insertionMode;
    int? depth;
    if (normalizedId == 'chat_history') {
      insertionMode = 'relative';
    } else if (pm['injection_position'] == 1) {
      insertionMode = 'depth';
      depth = pm['injection_depth'] as int? ?? 4;
    } else {
      insertionMode = 'relative';
    }

    blocks.add(PresetBlock(
      id: normalizedId,
      name: blockName,
      role: (pm['role'] as String?) ?? 'system',
      content: isMandatory ? '' : ((pm['content'] as String?) ?? ''),
      enabled: isEnabled,
      insertionMode: insertionMode,
      depth: depth,
    ));
  }

  final stRegexes = json['regexes'] as List<dynamic>?;
  final extRegexes = (json['extensions'] as Map<String, dynamic>?)?['regex_scripts'] as List<dynamic>?;
  final regexSource = extRegexes ?? stRegexes;
  if (regexSource != null) {
    for (int i = 0; i < regexSource.length; i++) {
      final r = regexSource[i] as Map<String, dynamic>;
      regexes.add(PresetRegex(
        id: r['id'] as String? ?? 'imported_r$i',
        name: (r['scriptName'] as String?) ?? 'Regex $i',
        regex: (r['findRegex'] as String?) ?? '',
        replacement: (r['replaceString'] as String?) ?? '',
        placement: (r['placement'] as List<dynamic>?)?.map((e) => e as int).toList() ?? [1, 2],
        disabled: !(r['isEnabled'] as bool? ?? !((r['disabled'] as bool?) ?? false)),
        ephemerality: (r['ephemerality'] as List<dynamic>?)?.map((e) => e as int).toList() ?? [1, 2],
        minDepth: r['minDepth'] as int?,
        maxDepth: r['maxDepth'] as int?,
      ));
    }
  }

  return Preset(
    id: DateTime.now().millisecondsSinceEpoch.toRadixString(36),
    name: (json['name'] as String?) ?? fileName.replaceAll('.json', ''),
    blocks: blocks,
    regexes: regexes,
    reasoningEnabled: json['reasoning'] as bool? ?? json['reasoning_enabled'] as bool? ?? false,
    createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
  );
}
