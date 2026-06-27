import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:glaze_flutter/core/db/app_db.dart';
import 'package:glaze_flutter/core/db/repositories/memory_book_repo.dart';
import 'package:glaze_flutter/core/models/memory_book.dart';
import 'package:glaze_flutter/core/state/db_provider.dart';

AppDatabase _testDb() => AppDatabase.forTesting(NativeDatabase.memory());

void main() {
  group('MemoryBookRepo.appendFactsToEntry (patch #4 — append-only)', () {
    late AppDatabase db;
    late MemoryBookRepo repo;
    late ProviderContainer container;

    setUp(() {
      db = _testDb();
      container = ProviderContainer(
        overrides: [appDbProvider.overrideWithValue(db)],
      );
      repo = container.read(memoryBookRepoProvider);
      addTearDown(container.dispose);
      addTearDown(() => db.close());
    });

    test('appends new facts to existing entry content (not rewrite)', () async {
      final book = MemoryBook(
        id: 'memorybook_s1',
        sessionId: 's1',
        entries: [
          MemoryEntry(
            id: 'mem_abc',
            title: 'Lucyna plan',
            content: 'Lucyna plans to kill Danvi.',
            keys: ['Lucyna', 'plan'],
            messageIds: ['m40'],
            status: 'active',
            source: 'agentic',
            kind: 'agent',
          ),
        ],
      );
      await repo.put(book);

      final updated = await repo.appendFactsToEntry(
        sessionId: 's1',
        entryId: 'mem_abc',
        newFacts: 'Lucyna acquired a knife.',
        newKeys: ['knife'],
      );

      expect(updated, isTrue);
      final after = await repo.getBySessionId('s1');
      expect(after!.entries, hasLength(1));
      final entry = after.entries.first;
      // Append-only: original content preserved, new facts appended with
      // \n\n separator (Marinara newFacts semantics).
      expect(
        entry.content,
        'Lucyna plans to kill Danvi.\n\nLucyna acquired a knife.',
      );
    });

    test('merges keys case-insensitively (no duplicate keys)', () async {
      final book = MemoryBook(
        id: 'memorybook_s2',
        sessionId: 's2',
        entries: [
          MemoryEntry(
            id: 'mem_def',
            title: 'Test',
            content: 'Original',
            keys: ['Lucyna', 'Plan'],
            status: 'active',
          ),
        ],
      );
      await repo.put(book);

      await repo.appendFactsToEntry(
        sessionId: 's2',
        entryId: 'mem_def',
        newFacts: 'New fact',
        // 'lucyna' (lowercase) should dedup against existing 'Lucyna'.
        // 'knife' is genuinely new.
        newKeys: ['lucyna', 'knife'],
      );

      final after = await repo.getBySessionId('s2');
      final entry = after!.entries.first;
      // 'Lucyna' preserved (original casing), 'Plan' preserved, 'knife' added.
      // 'lucyna' deduped against 'Lucyna' (case-insensitive).
      expect(entry.keys, containsAll(['Lucyna', 'Plan', 'knife']));
      expect(entry.keys, hasLength(3));
      // No lowercase 'lucyna' duplicate.
      expect(entry.keys.where((k) => k.toLowerCase() == 'lucyna').length, 1);
    });

    test('returns false when entryId does not exist', () async {
      final book = MemoryBook(
        id: 'memorybook_s3',
        sessionId: 's3',
        entries: [],
      );
      await repo.put(book);

      final updated = await repo.appendFactsToEntry(
        sessionId: 's3',
        entryId: 'mem_nonexistent',
        newFacts: 'Some fact',
      );

      expect(updated, isFalse);
    });

    test('returns false when book does not exist', () async {
      final updated = await repo.appendFactsToEntry(
        sessionId: 's_nonexistent',
        entryId: 'mem_x',
        newFacts: 'Some fact',
      );

      expect(updated, isFalse);
    });

    test('no-op when newFacts is whitespace-only', () async {
      final book = MemoryBook(
        id: 'memorybook_s4',
        sessionId: 's4',
        entries: [
          MemoryEntry(
            id: 'mem_ghi',
            title: 'Test',
            content: 'Original',
            status: 'active',
          ),
        ],
      );
      await repo.put(book);

      final updated = await repo.appendFactsToEntry(
        sessionId: 's4',
        entryId: 'mem_ghi',
        newFacts: '   \n\n  ',
      );

      expect(updated, isFalse);
      final after = await repo.getBySessionId('s4');
      // Content untouched.
      expect(after!.entries.first.content, 'Original');
    });

    test('appends to empty content without leading separator', () async {
      final book = MemoryBook(
        id: 'memorybook_s5',
        sessionId: 's5',
        entries: [
          MemoryEntry(
            id: 'mem_jkl',
            title: 'Empty content entry',
            content: '',
            status: 'active',
          ),
        ],
      );
      await repo.put(book);

      await repo.appendFactsToEntry(
        sessionId: 's5',
        entryId: 'mem_jkl',
        newFacts: 'First fact',
      );

      final after = await repo.getBySessionId('s5');
      // No leading \n\n when original content was empty.
      expect(after!.entries.first.content, 'First fact');
    });

    test('preserves existing messageIds (does not overwrite linkage)', () async {
      // The append should NOT touch the entry's messageIds — the caller
      // (agentic write service) sets messageIds on the original entry and
      // append-only newFacts should not change that linkage. This test
      // documents that contract.
      final book = MemoryBook(
        id: 'memorybook_s6',
        sessionId: 's6',
        entries: [
          MemoryEntry(
            id: 'mem_mno',
            title: 'Test',
            content: 'Original',
            messageIds: ['m40', 'm41'],
            status: 'active',
          ),
        ],
      );
      await repo.put(book);

      await repo.appendFactsToEntry(
        sessionId: 's6',
        entryId: 'mem_mno',
        newFacts: 'Appended fact',
      );

      final after = await repo.getBySessionId('s6');
      // messageIds unchanged by the append.
      expect(after!.entries.first.messageIds, ['m40', 'm41']);
    });
  });
}
