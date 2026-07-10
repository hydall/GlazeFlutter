import '../models/lorebook.dart';
import 'lorebook_scanner.dart';

List<LorebookEntry> mergeKeywordVector({
  required List<ScannedEntry> keywordEntries,
  required List<LorebookEntry> vectorEntries,
  required LorebookGlobalSettings settings,
}) {
  final maxEntries = settings.maxInjectedEntries;
  final maxVector = settings.vectorTopK;
  final constantKeywords = keywordEntries.where((e) => e.constant).toList();
  final triggeredKeywords = applyLorebookPerBookLimits(
    keywordEntries.where((e) => !e.constant).toList(),
  );

  // Step 1: fill with keyword entries first (constants + triggered).
  // Keywords can occupy up to maxEntries slots (minus constants).
  final usedKeyword = triggeredKeywords
      .take(maxEntries - constantKeywords.length)
      .toList();

  if (vectorEntries.isEmpty) {
    return [
      ...constantKeywords.map(_fromScanned),
      ...usedKeyword.map(_fromScanned),
    ];
  }

  // Step 2: fill remaining slots with vector entries, but no more than
  // maxVector (vectorTopK).  Unused keyword slots do NOT carry over to
  // vector — vectorTopK is a hard cap, not a split percentage.
  final keywordSlotCount = constantKeywords.length + usedKeyword.length;
  final remainingSlots = maxEntries - keywordSlotCount;
  final vectorSlots = remainingSlots < maxVector ? remainingSlots : maxVector;
  final usableVectorSlots = vectorSlots < 0 ? 0 : vectorSlots;

  // Dedupe vector entries against keyword entries already selected.
  final keywordIds = {
    ...constantKeywords.map((e) => e.id),
    ...usedKeyword.map((e) => e.id),
  };
  final dedupedVector = vectorEntries
      .where((e) => !keywordIds.contains(e.id))
      .toList();

  final usedVector = dedupedVector.take(usableVectorSlots).toList();

  return [
    ...constantKeywords.map(_fromScanned),
    ...usedKeyword.map(_fromScanned),
    ...usedVector,
  ];
}

LorebookEntry _fromScanned(ScannedEntry e) => LorebookEntry(
  id: e.id,
  comment: e.comment,
  content: e.content,
  position: e.position,
);
