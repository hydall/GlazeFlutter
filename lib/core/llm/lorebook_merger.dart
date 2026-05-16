import 'package:flutter/foundation.dart';

import '../models/lorebook.dart';
import 'lorebook_scanner.dart';

List<LorebookEntry> mergeKeywordVector({
  required List<ScannedEntry> keywordEntries,
  required List<LorebookEntry> vectorEntries,
  required LorebookGlobalSettings settings,
}) {
  if (vectorEntries.isEmpty) {
    final result = keywordEntries.map((e) => LorebookEntry(
      id: e.id,
      comment: e.comment,
      content: e.content,
      position: e.position,
    )).toList();
    debugPrint('MERGER: vectorEntries empty → keyword only: ${result.length}');
    return result;
  }

  final maxEntries = settings.maxInjectedEntries;
  final splitPct = settings.keywordVectorSplit;

  final keywordSlots = (maxEntries * splitPct / 100).round();
  final vectorSlots = maxEntries - keywordSlots;

  final usedKeyword = keywordEntries.take(keywordSlots).toList();
  final unusedKeywordSlots = keywordSlots - usedKeyword.length;
  final adjustedVectorSlots = vectorSlots + unusedKeywordSlots;

  final keywordIds = usedKeyword.map((e) => e.id).toSet();
  final dedupedVector = vectorEntries.where((e) => !keywordIds.contains(e.id)).toList();

  final usedVector = dedupedVector.take(adjustedVectorSlots).toList();

  debugPrint('MERGER: maxEntries=$maxEntries splitPct=$splitPct% '
      '→ keywordSlots=$keywordSlots vectorSlots=$vectorSlots '
      '| keyword in=${keywordEntries.length} used=${usedKeyword.length} unusedSlots=$unusedKeywordSlots '
      '| vector in=${vectorEntries.length} deduped=${dedupedVector.length} adjustedSlots=$adjustedVectorSlots used=${usedVector.length} '
      '| total=${usedKeyword.length + usedVector.length}');

  final keywordAsEntries = usedKeyword.map((e) => LorebookEntry(
    id: e.id,
    comment: e.comment,
    content: e.content,
    position: e.position,
  )).toList();

  return [...keywordAsEntries, ...usedVector];
}
