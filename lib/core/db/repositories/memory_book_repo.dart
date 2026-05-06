import 'dart:convert';

import 'package:drift/drift.dart';

import '../app_db.dart';
import '../tables.dart';
import '../../models/memory_book.dart';

part 'memory_book_repo.g.dart';

@DriftAccessor(tables: [MemoryBookRows])
class MemoryBookRepo extends DatabaseAccessor<AppDatabase>
    with _$MemoryBookRepoMixin {
  MemoryBookRepo(super.db);

  Future<MemoryBook?> getBySessionId(String sessionId) async {
    final row = await (select(memoryBookRows)
          ..where((t) => t.sessionId.equals(sessionId)))
        .getSingleOrNull();
    if (row == null) return null;
    return _rowToModel(row);
  }

  Future<List<MemoryBook>> getAll() async {
    final rows = await select(memoryBookRows).get();
    return rows.map(_rowToModel).toList();
  }

  Future<void> put(MemoryBook book) {
    return into(memoryBookRows).insertOnConflictUpdate(
      MemoryBookRowsCompanion.insert(
        sessionId: book.sessionId,
        entriesJson: Value(jsonEncode(
            book.entries.map((e) => e.toJson()).toList())),
        settingsJson: Value(jsonEncode(book.settings.toJson())),
        lastProcessedMessageCount:
            Value(book.lastProcessedMessageCount),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch ~/ 1000),
      ),
    );
  }

  Future<void> deleteBySessionId(String sessionId) {
    return (delete(memoryBookRows)
          ..where((t) => t.sessionId.equals(sessionId)))
        .go();
  }

  Future<MemoryBook> ensureForSession(String sessionId) async {
    final existing = await getBySessionId(sessionId);
    if (existing != null) return existing;
    final book = MemoryBook(
      id: 'memorybook_$sessionId',
      sessionId: sessionId,
    );
    await put(book);
    return book;
  }

  MemoryBook _rowToModel(MemoryBookRow row) {
    List<MemoryEntry> entries;
    try {
      final list = jsonDecode(row.entriesJson) as List<dynamic>;
      entries = list.map((e) => MemoryEntry.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      entries = [];
    }

    MemoryBookSettings settings;
    try {
      settings = MemoryBookSettings.fromJson(
          jsonDecode(row.settingsJson) as Map<String, dynamic>);
    } catch (_) {
      settings = const MemoryBookSettings();
    }

    return MemoryBook(
      id: 'memorybook_${row.sessionId}',
      sessionId: row.sessionId,
      entries: entries,
      settings: settings,
      lastProcessedMessageCount: row.lastProcessedMessageCount,
      updatedAt: row.updatedAt,
    );
  }
}
