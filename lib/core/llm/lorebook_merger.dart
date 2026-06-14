import '../models/lorebook.dart';
import 'lorebook_scanner.dart';

List<LorebookEntry> mergeKeywordVector({
  required List<ScannedEntry> keywordEntries,
  required List<LorebookEntry> vectorEntries,
  required LorebookGlobalSettings settings,
}) {
  final maxEntries = settings.maxInjectedEntries;
  final constantKeywords = keywordEntries.where((e) => e.constant).toList();
  final triggeredKeywords = applyLorebookPerBookLimits(
    keywordEntries.where((e) => !e.constant).toList(),
  );

  if (vectorEntries.isEmpty) {
    return [
      ...constantKeywords.map(_fromScanned),
      ...triggeredKeywords.take(maxEntries).map(_fromScanned),
    ];
  }

  final splitPct = settings.keywordVectorSplit;

  final keywordSlots = (maxEntries * splitPct / 100).round();
  final vectorSlots = maxEntries - keywordSlots;

  final usedKeyword = triggeredKeywords.take(keywordSlots).toList();
  final unusedKeywordSlots = keywordSlots - usedKeyword.length;
  final adjustedVectorSlots = vectorSlots + unusedKeywordSlots;

  // Avoid duplicate prompt content for keyword entries already selected in the
  // keyword slice. Keyword matches that overflow keywordSlots may still be
  // selected through vector slots; prompt_builder labels those as keyword using
  // the full keyword activation set so the badge matches Coverage.
  final keywordIds = {
    ...constantKeywords.map((e) => e.id),
    ...usedKeyword.map((e) => e.id),
  };
  final dedupedVector = vectorEntries
      .where((e) => !keywordIds.contains(e.id))
      .toList();

  // If dedup removed some entries, compensate by taking more from the vector
  // pool so vectorSlots is still filled (requires vector search to return
  // enough candidates — overrideTopK=maxInjectedEntries handles that).
  final usedVector = dedupedVector.take(adjustedVectorSlots).toList();

  final keywordAsEntries = usedKeyword.map(_fromScanned).toList();

  return [
    ...constantKeywords.map(_fromScanned),
    ...keywordAsEntries,
    ...usedVector,
  ];
}

LorebookEntry _fromScanned(ScannedEntry e) => LorebookEntry(
  id: e.id,
  comment: e.comment,
  content: e.content,
  position: e.position,
);
