import '../models/character.dart';
import '../models/chat_message.dart';
import '../models/lorebook.dart';

const _glazeBoundaries = '[\\s.,!?;:"\'\\u201C\\u201D\\u2018\\u2019\\u00AB\\u00BB(){}\\[\\]\u2014\u2013*]';

class ScannedEntry {
  final String id;
  final String comment;
  final String content;
  final String position;
  final int order;
  final String lorebookName;
  final String lorebookId;
  final bool constant;

  const ScannedEntry({
    required this.id,
    required this.comment,
    required this.content,
    required this.position,
    required this.order,
    required this.lorebookName,
    required this.lorebookId,
    required this.constant,
  });
}

List<ScannedEntry> scanLorebooks({
  required List<ChatMessage> history,
  required Character? char,
  required String textToScan,
  required String? chatId,
  required List<Lorebook> lorebooks,
  required LorebookGlobalSettings globalSettings,
  required LorebookActivations activations,
}) {
  if (globalSettings.searchType == 'vector') return [];

  final charId = char?.id;

  final activeLorebooks = lorebooks.where((lb) {
    if (lb.enabled) return true;
    if (charId != null && activations.character[charId]?.contains(lb.id) == true) return true;
    if (chatId != null && activations.chat[chatId]?.contains(lb.id) == true) return true;
    return false;
  }).toList();

  if (activeLorebooks.isEmpty) return [];

  final maxInjectedEntries = (globalSettings.maxInjectedEntries).clamp(1, 100);
  final allRelevantEntries = <ScannedEntry>[];
  final candidateEntries = <_CandidateEntry>[];

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

      candidateEntries.add(_CandidateEntry(
        entry: entry,
        lorebookName: lb.name,
        lorebookId: lb.id,
      ));
    }
  }

  for (final c in candidateEntries) {
    if (c.entry.constant) {
      if (!allRelevantEntries.any((e) => e.id == c.entry.id)) {
        allRelevantEntries.add(_toScanned(c));
      }
    }
  }

  var changed = true;
  var iteration = 0;
  final maxIterations = globalSettings.recursiveScan ? 5 : 1;
  var scanText = textToScan;

  while (changed && iteration < maxIterations) {
    changed = false;
    iteration++;

    for (final c in candidateEntries) {
      final entry = c.entry;
      if (allRelevantEntries.any((e) => e.id == entry.id)) continue;
      if (entry.constant) continue;

      final primaryKeys = entry.keys;
      final secondaryKeys = entry.secondaryKeys;
      final logic = entry.selectiveLogic;

      final caseSensitive = entry.caseSensitive || (!entry.caseSensitive && globalSettings.caseSensitive);
      final wholeWords = _resolveWholeWords(entry.matchWholeWords, globalSettings.matchWholeWords);

      final scanDepth = entry.scanDepth ?? globalSettings.scanDepth;
      final temporalDepth = entry.sticky > entry.cooldown ? entry.sticky : entry.cooldown;
      final effectiveScanDepth = temporalDepth > 0
          ? scanDepth < temporalDepth ? scanDepth : temporalDepth
          : scanDepth;

      final messagesToScan = history
          .skip(history.length > effectiveScanDepth ? history.length - effectiveScanDepth : 0)
          .map((m) => m.content)
          .join('\n');

      var scanSource = caseSensitive
          ? '$messagesToScan$scanText'
          : '${messagesToScan.toLowerCase()}${scanText.toLowerCase()}';

      bool isStickyActive = false;
      bool isOnCooldown = false;

      if (entry.sticky > 0 || entry.cooldown > 0) {
        final temporalMax = entry.sticky > entry.cooldown ? entry.sticky : entry.cooldown;
        for (var i = 1; i <= temporalMax; i++) {
          final idx = history.length - i;
          if (idx < 0) break;
          final histSource = caseSensitive
              ? history[idx].content
              : history[idx].content.toLowerCase();
          final wasMatched = primaryKeys.any((key) => _checkMatch(key, histSource, caseSensitive, wholeWords));
          if (wasMatched) {
            if (i <= entry.sticky) isStickyActive = true;
            if (i <= entry.cooldown) isOnCooldown = true;
            break;
          }
        }
      }

      if (isOnCooldown) continue;

      final matchedPrimary = isStickyActive || primaryKeys.any((key) => _checkMatch(key, scanSource, caseSensitive, wholeWords));

      if (matchedPrimary) {
        bool secondaryMatches = true;

        if (logic == 4 || secondaryKeys.isEmpty) {
          secondaryMatches = true;
        } else if (secondaryKeys.isNotEmpty) {
          final matches = secondaryKeys.map((key) => _checkMatch(key, scanSource, caseSensitive, wholeWords));
          final anyMatch = matches.any((m) => m);
          final allMatch = matches.every((m) => m);

          switch (logic) {
            case 0: secondaryMatches = anyMatch;
            case 1: secondaryMatches = allMatch;
            case 2: secondaryMatches = !anyMatch;
            case 3: secondaryMatches = !allMatch;
          }
        }

        if (secondaryMatches) {
          if (entry.probability < 100) {
            if (_randomPercent() > entry.probability) continue;
          }

          allRelevantEntries.add(_toScanned(c));

          if (!entry.preventRecursion && iteration < maxIterations) {
            scanText = '$scanText\n${entry.content.toLowerCase()}';
            changed = true;
          }
        }
      }
    }
  }

  allRelevantEntries.sort((a, b) => a.order.compareTo(b.order));
  return allRelevantEntries.take(maxInjectedEntries).toList();
}

bool _checkMatch(String key, String text, bool caseSensitive, _WholeWordMode wholeWords) {
  if (key.isEmpty) return false;

  if (wholeWords == _WholeWordMode.glaze) {
    final escaped = RegExp.escape(key);
    final beforeBoundary = '(?:^|$_glazeBoundaries)';
    final afterBoundary = r'(?:$|' + _glazeBoundaries + ')';
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

int _randomPercent() => DateTime.now().microsecond % 100;

enum _WholeWordMode { no, yes, glaze }

_WholeWordMode _resolveWholeWords(bool entryValue, bool globalValue) {
  if (entryValue == true) return _WholeWordMode.yes;
  return _WholeWordMode.no;
}

ScannedEntry _toScanned(_CandidateEntry c) => ScannedEntry(
      id: c.entry.id,
      comment: c.entry.comment,
      content: c.entry.content,
      position: c.entry.position,
      order: c.entry.order,
      lorebookName: c.lorebookName,
      lorebookId: c.lorebookId,
      constant: c.entry.constant,
    );

class _CandidateEntry {
  final LorebookEntry entry;
  final String lorebookName;
  final String lorebookId;

  const _CandidateEntry({
    required this.entry,
    required this.lorebookName,
    required this.lorebookId,
  });
}
