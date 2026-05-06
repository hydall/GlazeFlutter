import '../models/lorebook.dart';
import 'lorebook_scanner.dart';

List<LorebookEntry> mergeKeywordVector({
  required List<ScannedEntry> keywordEntries,
  required List<LorebookEntry> vectorEntries,
  required LorebookGlobalSettings settings,
}) {
  if (vectorEntries.isEmpty) {
    return keywordEntries.map((e) => LorebookEntry(
      id: e.id,
      comment: e.comment,
      content: e.content,
      position: e.position,
    )).toList();
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

  final keywordAsEntries = usedKeyword.map((e) => LorebookEntry(
    id: e.id,
    comment: e.comment,
    content: e.content,
    position: e.position,
  )).toList();

  return [...keywordAsEntries, ...usedVector];
}
