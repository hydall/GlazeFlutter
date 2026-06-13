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

  // Keyword match wins over vector for the same entry globally, not only for
  // keyword entries that fit into the current split. Otherwise an entry that
  // matched by key but overflowed keywordSlots can come back as a vector hit,
  // making the badge claim it was vector-injected while coverage reports a key
  // trigger/cutoff.
  final keywordIds = keywordEntries.map((e) => e.id).toSet();
  final dedupedVector = vectorEntries
      .where((e) => !keywordIds.contains(e.id))
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
