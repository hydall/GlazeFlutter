import '../models/lorebook.dart';
import 'lorebook_scanner.dart';

List<LorebookEntry> mergeKeywordVector({
  required List<ScannedEntry> keywordEntries,
  required List<LorebookEntry> vectorEntries,
  required LorebookGlobalSettings settings,
}) {
  if (vectorEntries.isEmpty) {
    return keywordEntries
        .map(
          (e) => LorebookEntry(
            id: e.id,
            comment: e.comment,
            content: e.content,
            position: e.position,
          ),
        )
        .toList();
  }

  final maxEntries = settings.maxInjectedEntries;
  final splitPct = settings.keywordVectorSplit;

  final keywordSlots = (maxEntries * splitPct / 100).round();
  final vectorSlots = maxEntries - keywordSlots;

  final usedKeyword = keywordEntries.take(keywordSlots).toList();
  final unusedKeywordSlots = keywordSlots - usedKeyword.length;
  final adjustedVectorSlots = vectorSlots + unusedKeywordSlots;

  final usedKeywordIds = usedKeyword.map((e) => e.id).toSet();
  final keywordById = {for (final e in keywordEntries) e.id: e};
  final dedupedVector = vectorEntries
      .where((e) => !usedKeywordIds.contains(e.id))
      .map(
        (e) => keywordById[e.id] != null ? _fromScanned(keywordById[e.id]!) : e,
      )
      .toList();

  // If dedup removed some entries, compensate by taking more from the vector
  // pool so vectorSlots is still filled (requires vector search to return
  // enough candidates — overrideTopK=maxInjectedEntries handles that).
  final usedVector = dedupedVector.take(adjustedVectorSlots).toList();

  final keywordAsEntries = usedKeyword.map(_fromScanned).toList();

  return [...keywordAsEntries, ...usedVector];
}

LorebookEntry _fromScanned(ScannedEntry e) => LorebookEntry(
  id: e.id,
  comment: e.comment,
  content: e.content,
  position: e.position,
);
