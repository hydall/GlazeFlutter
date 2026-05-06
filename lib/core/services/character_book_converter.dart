import '../../core/models/lorebook.dart';

Lorebook convertCharacterBook(
  Map<String, dynamic> bookData,
  String characterId,
) {
  final rawEntries = bookData['entries'] as List<dynamic>? ?? [];
  final entries = <LorebookEntry>[];

  for (int i = 0; i < rawEntries.length; i++) {
    final e = rawEntries[i] as Map<String, dynamic>;
    final keys = (e['keys'] as List<dynamic>?)
            ?.map((k) => k.toString())
            .toList() ??
        [];
    final secondaryKeys = (e['secondary_keys'] as List<dynamic>?)
            ?.map((k) => k.toString())
            .toList() ??
        [];

    entries.add(LorebookEntry(
      id: e['id']?.toString() ?? 'cbentry_$i',
      comment: (e['name'] as String?) ?? (e['comment'] as String?) ?? '',
      keys: keys,
      secondaryKeys: secondaryKeys,
      content: (e['content'] as String?) ?? '',
      enabled: e['enabled'] as bool? ?? true,
      constant: e['constant'] as bool? ?? false,
      position: _mapPosition(e['position'] as int?),
      order: e['insertion_order'] as int? ?? e['order'] as int? ?? 100,
      scanDepth: e['scan_depth'] as int?,
      caseSensitive: e['case_sensitive'] as bool?,
      matchWholeWords: e['match_whole_words'] as bool?,
      selectiveLogic: _mapSelectiveLogic(e['selective'] as bool?, e['selective_logic'] as int?),
      probability: ((e['probability'] as num?)?.toDouble() ?? 1.0).round().clamp(0, 100),
      group: (e['group'] as String?) ?? '',
      preventRecursion: e['prevent_recursion'] as bool? ?? false,
      sticky: e['constant'] as bool? ?? false ? 1 : 0,
    ));
  }

  return Lorebook(
    id: 'charbook_${characterId}_${DateTime.now().millisecondsSinceEpoch}',
    name: (bookData['name'] as String?) ?? 'Character Book',
    enabled: true,
    activationScope: 'character',
    activationTargetId: characterId,
    entries: entries,
  );
}

String _mapPosition(int? pos) {
  switch (pos) {
    case 0:
      return 'before_char';
    case 1:
      return 'after_char';
    case 2:
      return 'worldInfoBefore';
    case 3:
      return 'worldInfoAfter';
    case 4:
      return 'at_depth';
    default:
      return 'after_char';
  }
}

int _mapSelectiveLogic(bool? selective, int? selectiveLogic) {
  if (selective != true) return 4;
  return selectiveLogic ?? 1;
}
