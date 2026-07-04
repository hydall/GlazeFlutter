import 'package:flutter/foundation.dart';

import '../../db/repositories/memory_book_repo.dart';
import '../../models/memory_book.dart';
import '../../models/studio_ledger_export.dart';
import '../../utils/id_generator.dart';
import '../../utils/time_helpers.dart';

/// Writes durable facts from the Studio Ledger export to the MemoryBook.
///
/// Deduplicates by title+content hash — existing entries with the same
/// `sourceHash` are skipped.
class DurableFactWriter {
  const DurableFactWriter();

  /// Write [facts] to [bookRepo] for [sessionId] with dedup by title+content
  /// hash. Returns count of facts actually written.
  Future<int> writeDurableFacts({
    required String sessionId,
    required String messageId,
    required List<LedgerDurableFact> facts,
    required MemoryBookRepo bookRepo,
  }) async {
    if (facts.isEmpty) return 0;
    var written = 0;

    // Load existing entries for dedup.
    final book = await bookRepo.getBySessionId(sessionId);
    final existing = book?.entries ?? const <MemoryEntry>[];
    final existingHashes = existing
        .map((MemoryEntry e) => e.sourceHash)
        .where((String h) => h.isNotEmpty)
        .toSet();

    final toAdd = <MemoryEntry>[];
    for (final fact in facts) {
      if (fact.title.trim().isEmpty || fact.content.trim().isEmpty) continue;
      final hash = hashFact(fact.title, fact.content);
      if (existingHashes.contains(hash)) {
        debugPrint(
          '[StudioLedger] dedup: skipping existing fact "${fact.title}"',
        );
        continue;
      }
      existingHashes.add(hash);
      toAdd.add(
        MemoryEntry(
          id: generateId(),
          title: fact.title.trim(),
          content: fact.content.trim(),
          keys: fact.keys,
          kind: 'studio_ledger',
          source: 'studio_ledger',
          sourceHash: hash,
          messageIds: [messageId],
          importance: 0.6,
          status: 'active',
          createdAt: currentTimestampSeconds(),
        ),
      );
      written++;
    }

    if (toAdd.isNotEmpty) {
      await bookRepo.appendApprovedEntries(sessionId, toAdd);
    }

    return written;
  }

  /// Compute a stable dedup hash for a (title, content) pair.
  String hashFact(String title, String content) {
    final normalized =
        '${title.trim().toLowerCase()}|${content.trim().toLowerCase()}';
    // Simple djb2 hash — enough for dedup without crypto overhead.
    var hash = 5381;
    for (final cp in normalized.codeUnits) {
      hash = ((hash << 5) + hash) ^ cp;
      hash &= 0xFFFFFFFF; // keep 32-bit
    }
    return 'sl_${hash.toRadixString(16)}';
  }
}
