import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/repositories/memory_book_repo.dart';
import '../models/memory_book.dart';
import '../state/db_provider.dart';

class MemoryInjectionResult {
  final List<MemoryEntry> entries;
  final String content;
  final String injectionTarget;
  final String macroContent;

  const MemoryInjectionResult({
    this.entries = const [],
    this.content = '',
    this.injectionTarget = 'summary_block',
    this.macroContent = '',
  });
}

class MemoryInjectionService {
  final MemoryBookRepo _repo;

  MemoryInjectionService(this._repo);

  Future<MemoryInjectionResult> buildInjection({
    required String sessionId,
    required String historyText,
    required int messageCount,
    String? summaryExcerpt,
  }) async {
    final book = await _repo.getBySessionId(sessionId);
    if (book == null) return const MemoryInjectionResult();

    final settings = book.settings;
    if (!settings.enabled) return const MemoryInjectionResult();

    final activeEntries = book.entries
        .where((e) => (e.status == 'active') && e.content.trim().isNotEmpty)
        .toList();

    if (activeEntries.isEmpty) return const MemoryInjectionResult();

    final scanText = historyText.toLowerCase();
    final keywordMatched = <String>{};

    for (final entry in activeEntries) {
      for (final key in entry.keys) {
        if (key.isEmpty) continue;
        if (settings.keyMatchMode == 'glaze') {
          if (_glazeMatch(key, scanText)) keywordMatched.add(entry.id);
        } else if (settings.keyMatchMode == 'both') {
          if (scanText.contains(key.toLowerCase()) || _glazeMatch(key, scanText)) {
            keywordMatched.add(entry.id);
          }
        } else {
          if (scanText.contains(key.toLowerCase())) keywordMatched.add(entry.id);
        }
      }
    }

    final scoredEntries = activeEntries.map((entry) {
      var score = 0.0;
      if (keywordMatched.contains(entry.id)) score += 6;
      if (entry.messageIds.isNotEmpty) score += 2;
      score += entry.content.length > 20 ? 1 : 0;
      return (entry: entry, score: score);
    }).toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    final topEntries = scoredEntries
        .where((item) => item.score > 0)
        .take(settings.maxInjectedEntries)
        .map((item) => item.entry)
        .toList();

    if (topEntries.isEmpty) return const MemoryInjectionResult();

    final macroContent = topEntries
        .map((e) => e.content.trim())
        .join('\n\n');

    final contentParts = <String>[];
    if (summaryExcerpt != null && summaryExcerpt.isNotEmpty) {
      contentParts.add('Summary excerpt:\n$summaryExcerpt');
    }
    contentParts.add('Memory context:');
    for (final entry in topEntries) {
      final title = entry.title.isNotEmpty ? entry.title : 'Memory';
      contentParts.add('- $title: ${entry.content.trim()}');
    }

    final injectionTarget =
        settings.injectionTarget == 'summary_macro' ? 'summary_macro' : 'summary_block';

    return MemoryInjectionResult(
      entries: topEntries,
      content: contentParts.join('\n\n'),
      injectionTarget: injectionTarget,
      macroContent: macroContent,
    );
  }

  bool _glazeMatch(String key, String text) {
    final pattern = r'[\s.,!?;:"\u201C\u201D\u2018\u2019\u00AB\u00BB(){}\[\]\u2014\u2013*]';
    final regex = '(?<=^|$pattern)${RegExp.escape(key)}(?=\$|$pattern)';
    try {
      return RegExp(regex, caseSensitive: false).hasMatch(text);
    } catch (_) {
      return text.contains(key.toLowerCase());
    }
  }
}

final memoryInjectionServiceProvider = Provider<MemoryInjectionService>((ref) {
  return MemoryInjectionService(ref.watch(memoryBookRepoProvider));
});
