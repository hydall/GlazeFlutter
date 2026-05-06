import '../models/character.dart';
import '../models/chat_message.dart';
import '../models/lorebook.dart';

class CoverageEntry {
  final String id;
  final String comment;
  final String content;
  final String position;
  final int order;
  final String lorebookName;
  final String lorebookId;
  final bool constant;
  final bool activated;
  final List<String> matchedKeys;
  final List<String> matchedSecondaryKeys;
  final int? matchMessageIndex;
  final bool cutOffByBudget;

  const CoverageEntry({
    required this.id,
    required this.comment,
    required this.content,
    required this.position,
    required this.order,
    required this.lorebookName,
    required this.lorebookId,
    required this.constant,
    required this.activated,
    this.matchedKeys = const [],
    this.matchedSecondaryKeys = const [],
    this.matchMessageIndex,
    this.cutOffByBudget = false,
  });
}

class CoverageResult {
  final List<CoverageEntry> entries;
  final int totalCandidates;
  final int activatedCount;
  final int cutOffCount;

  const CoverageResult({
    required this.entries,
    required this.totalCandidates,
    required this.activatedCount,
    required this.cutOffCount,
  });
}

const _glazeBoundaries = '[\\s.,!?;:"\'\\u201C\\u201D\\u2018\\u2019\\u00AB\\u00BB(){}\\[\\]\u2014\u2013*]';

CoverageResult computeLorebookCoverage({
  required List<ChatMessage> history,
  required Character? char,
  required String textToScan,
  required String? chatId,
  required List<Lorebook> lorebooks,
  required LorebookGlobalSettings globalSettings,
  required LorebookActivations activations,
}) {
  if (globalSettings.searchType == 'vector') {
    return const CoverageResult(entries: [], totalCandidates: 0, activatedCount: 0, cutOffCount: 0);
  }

  final charId = char?.id;

  final activeLorebooks = lorebooks.where((lb) {
    if (lb.enabled) return true;
    if (charId != null && activations.character[charId]?.contains(lb.id) == true) return true;
    if (chatId != null && activations.chat[chatId]?.contains(lb.id) == true) return true;
    return false;
  }).toList();

  if (activeLorebooks.isEmpty) {
    return const CoverageResult(entries: [], totalCandidates: 0, activatedCount: 0, cutOffCount: 0);
  }

  final maxInjectedEntries = globalSettings.maxInjectedEntries.clamp(1, 100);
  final candidates = <String, _Candidate>{};

  for (final lb in activeLorebooks) {
    for (final entry in lb.entries) {
      final isVectorOnly = entry.vectorSearch && !entry.useKeywordSearch;
      if (!entry.enabled || isVectorOnly) continue;

      if (char != null && entry.characterFilter != null) {
        final filter = entry.characterFilter!;
        if (filter.names.isNotEmpty) {
          final charName = char.name.toLowerCase();
          final isInCategory = filter.names.any((n) => charName.contains(n.toLowerCase()));
          if (filter.isExclude && isInCategory) continue;
          if (!filter.isExclude && !isInCategory) continue;
        }
      }

      candidates[entry.id] = _Candidate(
        entry: entry,
        lorebookName: lb.name,
        lorebookId: lb.id,
        activated: entry.constant,
        matchedKeys: [],
        matchedSecondaryKeys: [],
        matchMessageIndex: entry.constant ? null : null,
      );
    }
  }

  final caseSensitive = globalSettings.caseSensitive;
  final wholeWords = _resolveWholeWords(null, globalSettings.matchWholeWords, globalSettings.keySearchMode);
  final scanDepth = globalSettings.scanDepth;

  final nonHidden = history.where((m) => !m.isHidden).toList();
  final scanMessages = nonHidden.length > scanDepth
      ? nonHidden.sublist(nonHidden.length - scanDepth)
      : nonHidden;

  final scanText = caseSensitive
      ? '$textToScan\n${scanMessages.map((m) => m.content).join('\n')}'
      : '${textToScan.toLowerCase()}\n${scanMessages.map((m) => m.content).join('\n').toLowerCase()}';

  for (final c in candidates.values) {
    final entry = c.entry;
    if (entry.constant) continue;

    final matchedPrimary = <String>[];
    for (final key in entry.keys) {
      if (key.isEmpty) continue;
      if (_checkMatch(key, scanText, caseSensitive, wholeWords)) {
        matchedPrimary.add(key);
      }
    }

    int? matchIdx;
    if (matchedPrimary.isNotEmpty) {
      for (int i = scanMessages.length - 1; i >= 0; i--) {
        final msgText = caseSensitive
            ? scanMessages[i].content
            : scanMessages[i].content.toLowerCase();
        for (final key in entry.keys) {
          if (key.isNotEmpty && _checkMatch(key, msgText, caseSensitive, wholeWords)) {
            matchIdx = nonHidden.indexOf(scanMessages[i]);
            break;
          }
        }
        if (matchIdx != null) break;
      }
    }

    final matchedSecondary = <String>[];
    if (matchedPrimary.isNotEmpty && entry.secondaryKeys.isNotEmpty) {
      for (final key in entry.secondaryKeys) {
        if (key.isEmpty) continue;
        if (_checkMatch(key, scanText, caseSensitive, wholeWords)) {
          matchedSecondary.add(key);
        }
      }
    }

    c.matchedKeys = matchedPrimary;
    c.matchedSecondaryKeys = matchedSecondary;
    c.matchMessageIndex = matchIdx;

    if (matchedPrimary.isEmpty) continue;

    bool secondaryPass = true;
    final logic = entry.selectiveLogic;
    if (logic != 4 && entry.secondaryKeys.isNotEmpty) {
      final anyMatch = matchedSecondary.isNotEmpty;
      final allMatch = entry.secondaryKeys.every(
          (k) => k.isEmpty || _checkMatch(k, scanText, caseSensitive, wholeWords));

      switch (logic) {
        case 0: secondaryPass = anyMatch;
        case 1: secondaryPass = allMatch;
        case 2: secondaryPass = !anyMatch;
        case 3: secondaryPass = !allMatch;
      }
    }

    if (secondaryPass) {
      c.activated = true;
    }
  }

  final activatedList = candidates.values.where((c) => c.activated).toList()
    ..sort((a, b) => a.entry.order.compareTo(b.entry.order));

  final notActivatedList = candidates.values.where((c) => !c.activated).toList()
    ..sort((a, b) => a.entry.order.compareTo(b.entry.order));

  final cutOffCount = activatedList.length > maxInjectedEntries
      ? activatedList.length - maxInjectedEntries
      : 0;

  for (int i = maxInjectedEntries; i < activatedList.length; i++) {
    activatedList[i].cutOffByBudget = true;
  }

  final inBudget = activatedList.take(maxInjectedEntries).toList();
  final overBudget = activatedList.skip(maxInjectedEntries).toList();

  final allEntries = <CoverageEntry>[
    ...inBudget.map(_toCoverage),
    ...overBudget.map((c) {
      final base = _toCoverage(c);
      return CoverageEntry(
        id: base.id,
        comment: base.comment,
        content: base.content,
        position: base.position,
        order: base.order,
        lorebookName: base.lorebookName,
        lorebookId: base.lorebookId,
        constant: base.constant,
        activated: base.activated,
        matchedKeys: base.matchedKeys,
        matchedSecondaryKeys: base.matchedSecondaryKeys,
        matchMessageIndex: base.matchMessageIndex,
        cutOffByBudget: true,
      );
    }),
    ...notActivatedList.map(_toCoverage),
  ];

  return CoverageResult(
    entries: allEntries,
    totalCandidates: candidates.length,
    activatedCount: activatedList.length,
    cutOffCount: cutOffCount,
  );
}

CoverageEntry _toCoverage(_Candidate c) => CoverageEntry(
  id: c.entry.id,
  comment: c.entry.comment,
  content: c.entry.content,
  position: c.entry.position,
  order: c.entry.order,
  lorebookName: c.lorebookName,
  lorebookId: c.lorebookId,
  constant: c.entry.constant,
  activated: c.activated,
  matchedKeys: c.matchedKeys,
  matchedSecondaryKeys: c.matchedSecondaryKeys,
  matchMessageIndex: c.matchMessageIndex,
  cutOffByBudget: c.cutOffByBudget,
);

bool _checkMatch(String key, String text, bool caseSensitive, _WholeWordMode wholeWords) {
  if (key.isEmpty) return false;

  if (wholeWords == _WholeWordMode.glaze) {
    final escaped = RegExp.escape(key);
    final beforeBoundary = '(?:^|$_glazeBoundaries)';
    final afterBoundary = '(?:\$|$_glazeBoundaries)';
    final pattern = beforeBoundary + escaped + afterBoundary;
    final regex = _tryCreateRegex(pattern, caseSensitive);
    if (regex != null) return regex.hasMatch(text);
    final needle = caseSensitive ? key : key.toLowerCase();
    final haystack = caseSensitive ? text : text.toLowerCase();
    if (needle.isEmpty) return false;
    final fallback = _tryCreateRegex(
      beforeBoundary + RegExp.escape(needle) + afterBoundary,
      caseSensitive,
    );
    return fallback?.hasMatch(haystack) ?? false;
  }

  var pattern = key;
  if (wholeWords == _WholeWordMode.yes) {
    pattern = '\\b$pattern\\b';
  }

  final regex = _tryCreateRegex(pattern, caseSensitive);
  if (regex != null) return regex.hasMatch(text);

  final haystack = caseSensitive ? text : text.toLowerCase();
  final needle = caseSensitive ? key : key.toLowerCase();
  if (needle.isEmpty) return false;

  if (wholeWords == _WholeWordMode.yes) {
    final wordRegex = _tryCreateRegex('\\b${RegExp.escape(needle)}\\b', caseSensitive);
    return wordRegex?.hasMatch(haystack) ?? false;
  }

  return haystack.contains(needle);
}

RegExp? _tryCreateRegex(String pattern, bool caseSensitive) {
  try {
    return RegExp(pattern, caseSensitive: caseSensitive);
  } catch (_) {
    return null;
  }
}

enum _WholeWordMode { no, yes, glaze }

_WholeWordMode _resolveWholeWords(bool? entryValue, bool globalValue, String keySearchMode) {
  if (entryValue == true) return _WholeWordMode.yes;
  if (entryValue == false) return _WholeWordMode.no;
  if (keySearchMode == 'glaze') return _WholeWordMode.glaze;
  if (globalValue) return _WholeWordMode.yes;
  return _WholeWordMode.no;
}

class _Candidate {
  final LorebookEntry entry;
  final String lorebookName;
  final String lorebookId;
  bool activated;
  List<String> matchedKeys;
  List<String> matchedSecondaryKeys;
  int? matchMessageIndex;
  bool cutOffByBudget = false;

  _Candidate({
    required this.entry,
    required this.lorebookName,
    required this.lorebookId,
    required this.activated,
    required this.matchedKeys,
    required this.matchedSecondaryKeys,
    required this.matchMessageIndex,
  });
}
