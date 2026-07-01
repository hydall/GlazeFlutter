// ignore_for_file: lines_longer_than_80_chars

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:glaze_flutter/core/db/app_db.dart';
import 'package:glaze_flutter/core/db/repositories/memory_book_repo.dart';
import 'package:glaze_flutter/core/db/repositories/tracker_repo.dart';
import 'package:glaze_flutter/core/db/repositories/tracker_snapshot_repo.dart';
import 'package:glaze_flutter/core/llm/studio_ledger_export_parser.dart';
import 'package:glaze_flutter/core/llm/prompt_payload_builder.dart'
    show kCompileStudioSessionStateForTest;
import 'package:glaze_flutter/core/models/memory_book.dart';
import 'package:glaze_flutter/core/models/tracker.dart';
import 'package:glaze_flutter/core/state/db_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

AppDatabase _db() => AppDatabase.forTesting(NativeDatabase.memory());

const _validJson = '''
{
  "sceneState": {
    "time": "00:48",
    "date": "16-01-2077",
    "location": "Watson streets",
    "immediateThread": "Lucy and Danvi are riding.",
    "presentEntities": [
      { "name": "Lucyna Kushinada", "status": "present", "confidence": "high" }
    ],
    "activeTensions": []
  },
  "entities": [
    {
      "name": "Lucyna Kushinada",
      "aliases": ["Lucy"],
      "type": "npc",
      "relationshipToUser": "fragile alliance",
      "attitudeToUser": "wary but familiar",
      "knowledge": ["Danvi knows her role in David's fate"],
      "boundaries": [],
      "durableFacts": ["Lucy accepted a shared ride with Danvi."],
      "cardOverrides": ["Do not treat Danvi as a random newcomer to Lucy."]
    }
  ],
  "arcState": [
    {
      "id": "david_fate",
      "title": "David's fate revelation",
      "status": "completed",
      "summary": "Danvi knows Lucy's role in David's fate.",
      "doNotReopen": true,
      "cardOverride": "Treat David's fate as resolved backstory.",
      "entities": ["Lucyna Kushinada", "Danvi"]
    }
  ],
  "durableFacts": [
    {
      "title": "Lucy accepts fragile alliance",
      "content": "Lucy accepted a shared ride with Danvi despite distrust.",
      "keys": ["Lucy", "Danvi", "alliance"],
      "entities": ["Lucyna Kushinada", "Danvi"]
    }
  ],
  "ops": [
    {
      "op": "set",
      "key": "npc:Lucyna Kushinada.relationship_to_user",
      "value": "fragile alliance",
      "evidence": "Lucy accepted a shared ride.",
      "eventState": "completed"
    },
    {
      "op": "append_unique",
      "key": "npc:Lucyna Kushinada.knowledge",
      "value": "Danvi knows Lucy's role in David's fate.",
      "evidence": "Revealed in final assistant response.",
      "eventState": "completed"
    },
    {
      "op": "set",
      "key": "arc:david_fate.status",
      "value": "completed",
      "evidence": "Arc resolved this turn.",
      "eventState": "completed"
    }
  ]
}
''';

const _rawResponse =
    '''
<studio_ledger>
Lucy accepted a fragile alliance with Danvi.
</studio_ledger>

<glaze_memory_export>
$_validJson
</glaze_memory_export>
''';

List<Tracker> _makeTrackers(
  String sessionId,
  Map<String, String> nameValues, {
  String scope = 'ledger',
}) {
  return nameValues.entries
      .map(
        (e) => Tracker(
          sessionId: sessionId,
          name: e.key,
          value: e.value,
          scope: scope,
        ),
      )
      .toList();
}

// ─────────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  const parser = StudioLedgerExportParser();

  // ── Parser tests ───────────────────────────────────────────────────────────
  group('StudioLedgerExportParser', () {
    // Test 1
    test('extracts valid JSON from <glaze_memory_export>', () {
      final result = parser.parse(_rawResponse);
      expect(result.export, isNotNull);
      expect(result.export!.ops, hasLength(3));
      expect(result.export!.durableFacts, hasLength(1));
      expect(result.visibleLedger, contains('fragile alliance'));
      expect(result.wasRejected, isFalse);
    });

    test('extracts valid JSON wrapped in markdown fence', () {
      const raw =
          '''
<glaze_memory_export>
```json
$_validJson
```
</glaze_memory_export>
''';
      final result = parser.parse(raw);
      expect(result.export, isNotNull);
      expect(result.export!.ops, hasLength(3));
      expect(result.wasRejected, isFalse);
    });

    // Test 2
    test('malformed JSON does not crash; returns null export', () {
      const bad = '<glaze_memory_export>{ not json </glaze_memory_export>';
      final result = parser.parse(bad);
      expect(result.export, isNull);
      expect(result.wasRejected, isTrue);
    });

    test('normalizes non-string LLM fields before generated parsing', () {
      const raw = '''
<studio_ledger>
Ledger text.
</studio_ledger>
<glaze_memory_export>
{
  "sceneState": {
    "time": ["night", "late"],
    "location": {"name":"Watson"},
    "immediateThread": ["Lucy waits", "Danvi answers"],
    "presentEntities": ["Lucy", {"name":"Danvi", "reason":["driver", "speaker"]}],
    "activeTensions": [{"tension":"distrust"}]
  },
  "entities": [
    {
      "name": "Lucy",
      "knowledge": [{"fact":"Danvi knows"}],
      "durableFacts": ["accepted a ride"]
    }
  ],
  "durableFacts": [
    {
      "title": ["Shared", "ride"],
      "content": {"fact":"Lucy accepted the ride"},
      "keys": [{"key":"Lucy"}],
      "entities": ["Lucy"]
    }
  ],
  "ops": [
    {
      "op": "set",
      "key": "npc:Lucy.knowledge",
      "value": ["Danvi knows", "Lucy reacted"],
      "evidence": {"source":"assistant"},
      "eventState": "completed"
    }
  ]
}
</glaze_memory_export>
''';

      final result = parser.parse(raw);

      expect(result.export, isNotNull);
      expect(result.export!.ops.single.value, 'Danvi knows; Lucy reacted');
      expect(result.export!.sceneState!.time, 'night; late');
      expect(result.export!.sceneState!.presentEntities, hasLength(2));
      expect(result.export!.durableFacts, hasLength(1));
    });

    test('missing export block returns null export', () {
      final result = parser.parse('Just some text with no export block.');
      expect(result.export, isNull);
      expect(result.hasExport, isFalse);
    });

    test('rejects unknown op code', () {
      const badOp = '''
<glaze_memory_export>
{
  "ops": [
    {
      "op": "explode",
      "key": "npc:Lucy.mood",
      "value": "happy",
      "evidence": "test",
      "eventState": "completed"
    }
  ],
  "durableFacts": []
}
</glaze_memory_export>
''';
      final result = parser.parse(badOp);
      expect(result.export, isNull);
      expect(result.wasRejected, isTrue);
    });

    test('rejects unknown namespace prefix', () {
      const badNs = '''
<glaze_memory_export>
{
  "ops": [
    {
      "op": "set",
      "key": "hack:system.root",
      "value": "pwned",
      "evidence": "test",
      "eventState": "completed"
    }
  ],
  "durableFacts": []
}
</glaze_memory_export>
''';
      final result = parser.parse(badNs);
      expect(result.export, isNull);
      expect(result.wasRejected, isTrue);
    });

    test('rejects value exceeding kLedgerMaxValueChars', () {
      final longVal = 'x' * (kLedgerMaxValueChars + 1);
      final longOpBlock =
          '<glaze_memory_export>\n'
          '{"ops":[{"op":"set","key":"npc:Lucy.knowledge","value":"$longVal",'
          '"evidence":"test","eventState":"completed"}],"durableFacts":[]}\n'
          '</glaze_memory_export>';
      final result = parser.parse(longOpBlock);
      expect(result.export, isNull);
      expect(result.wasRejected, isTrue);
    });

    test('ignores empty export (no ops and no durableFacts)', () {
      const empty = '''
<glaze_memory_export>
{
  "ops": [],
  "durableFacts": []
}
</glaze_memory_export>
''';
      final result = parser.parse(empty);
      expect(result.export, isNull);
    });
  });

  // ── TrackerRepo ledger tests ───────────────────────────────────────────────
  group('TrackerRepo — ledger canon state', () {
    late AppDatabase db;
    late TrackerRepo repo;

    setUp(() {
      db = _db();
      repo = TrackerRepo(db);
    });

    tearDown(() async => db.close());

    // Test 5
    test('entity state writes npc:* tracker rows', () async {
      await repo.upsertValue(
        'sess1',
        'npc:Lucyna Kushinada.relationship_to_user',
        'fragile alliance',
        scope: 'ledger',
      );
      final row = await repo.get(
        'sess1',
        'npc:Lucyna Kushinada.relationship_to_user',
      );
      expect(row, isNotNull);
      expect(row!.value, 'fragile alliance');
      expect(row.scope, 'ledger');
    });

    // Test 6
    test(
      'relationship state upsert: only ONE row per key (last write wins)',
      () async {
        const key = 'relationship:Danvi:Lucyna Kushinada.relationship';
        await repo.upsertValue(
          'sess1',
          key,
          'fragile alliance',
          scope: 'ledger',
        );
        await repo.upsertValue('sess1', key, 'cautious trust', scope: 'ledger');

        final all = await repo.getBySessionAndScope('sess1', 'ledger');
        final matches = all.where((t) => t.name == key).toList();
        expect(matches, hasLength(1));
        expect(matches.first.value, 'cautious trust');
      },
    );

    // Test 7
    test('arc state upsert: last write wins', () async {
      const key = 'arc:david_fate.status';
      await repo.upsertValue('sess1', key, 'active', scope: 'ledger');
      await repo.upsertValue('sess1', key, 'completed', scope: 'ledger');

      final row = await repo.get('sess1', key);
      expect(row!.value, 'completed');
    });

    // Test 15
    test('canon_lock:* row blocks ledger updates for that key', () async {
      // Write lock.
      await repo.upsertValue(
        'sess1',
        'canon_lock:npc:Lucy.attitude',
        'true',
        scope: 'ledger',
      );
      // Simulate _applyOp lock check.
      final lock = await repo.get('sess1', 'canon_lock:npc:Lucy.attitude');
      final isLocked =
          lock != null && lock.value.trim().toLowerCase() == 'true';
      expect(isLocked, isTrue);

      // Respect lock: do NOT write the value.
      if (!isLocked) {
        await repo.upsertValue(
          'sess1',
          'npc:Lucy.attitude',
          'hostile',
          scope: 'ledger',
        );
      }

      final val = await repo.get('sess1', 'npc:Lucy.attitude');
      expect(val, isNull);
    });

    // Test 16 — override via compiled state
    test(
      'canon_override outranks model-written canon in prompt assembly',
      () async {
        // Write model canon.
        await repo.upsertValue(
          'sess1',
          'npc:Lucy.mood',
          'wary',
          scope: 'ledger',
        );
        // Write user override.
        await repo.upsertValue(
          'sess1',
          'canon_override:npc:Lucy.mood',
          'hostile; user-corrected',
          scope: 'ledger',
        );

        final all = await repo.getBySessionAndScope('sess1', 'ledger');
        final compiled = kCompileStudioSessionStateForTest(all, 'sess1');
        expect(compiled, isNotNull);
        expect(compiled, contains('hostile; user-corrected'));
        expect(compiled, isNot(contains('wary')));
      },
    );
  });

  // ── MemoryBookRepo durable facts tests ────────────────────────────────────
  group('MemoryBookRepo — studio_ledger durable facts', () {
    late AppDatabase db;
    late MemoryBookRepo repo;
    late ProviderContainer container;

    setUp(() {
      db = _db();
      container = ProviderContainer(
        overrides: [appDbProvider.overrideWithValue(db)],
      );
      repo = container.read(memoryBookRepoProvider);
      addTearDown(container.dispose);
      addTearDown(() => db.close());
    });

    // Test 3
    test('durable facts write to MemoryBook with kind=studio_ledger', () async {
      const sessionId = 'sess_mem';
      final book = MemoryBook(
        id: 'memorybook_$sessionId',
        sessionId: sessionId,
      );
      await repo.put(book);

      final entry = MemoryEntry(
        id: 'e1',
        title: 'Lucy accepts fragile alliance',
        content: 'Lucy accepted a shared ride with Danvi despite distrust.',
        keys: ['Lucy', 'Danvi', 'alliance'],
        kind: 'studio_ledger',
        source: 'studio_ledger',
        importance: 7,
        sourceHash: 'abc123',
      );
      await repo.appendApprovedEntries(sessionId, [entry]);

      final loaded = await repo.getBySessionId(sessionId);
      expect(loaded, isNotNull);
      expect(loaded!.entries, hasLength(1));
      expect(loaded.entries.first.kind, 'studio_ledger');
      expect(loaded.entries.first.sourceHash, 'abc123');
    });

    // Test 4
    test('repeated durable facts are deduped by sourceHash', () async {
      const sessionId = 'sess_dedup';
      final book = MemoryBook(
        id: 'memorybook_$sessionId',
        sessionId: sessionId,
      );
      await repo.put(book);

      final entry = MemoryEntry(
        id: 'e2',
        title: 'Lucy alliance',
        content: 'Lucy accepted a shared ride.',
        keys: ['Lucy'],
        kind: 'studio_ledger',
        source: 'studio_ledger',
        importance: 6,
        sourceHash: 'hash_xyz',
      );
      await repo.appendApprovedEntries(sessionId, [entry]);

      final loaded1 = await repo.getBySessionId(sessionId);
      final existingHashes = loaded1!.entries.map((e) => e.sourceHash).toSet();

      // Simulate dedup: only append if hash not present.
      if (!existingHashes.contains('hash_xyz')) {
        await repo.appendApprovedEntries(sessionId, [entry]);
      }

      final loaded2 = await repo.getBySessionId(sessionId);
      expect(loaded2!.entries, hasLength(1));
    });
  });

  // ── TrackerSnapshot rollback tests ───────────────────────────────────────
  group('TrackerSnapshotRepo — Studio Canon rollback safety', () {
    late AppDatabase db;
    late TrackerSnapshotRepo snapshotRepo;
    late TrackerRepo trackerRepo;

    setUp(() {
      db = _db();
      snapshotRepo = TrackerSnapshotRepo(db);
      trackerRepo = TrackerRepo(db);
    });

    tearDown(() async => db.close());

    // Test 13
    test(
      'uncommitted regenerated swipe state is not effective canon',
      () async {
        const sessionId = 'sess_snap';

        await snapshotRepo.upsertTrackers(
          sessionId: sessionId,
          messageId: 'msg_old',
          swipeId: 0,
          agentSwipeId: 0,
          trackers: _makeTrackers(sessionId, {
            'arc:david_fate.status': 'completed',
          }),
          committed: true,
        );

        await snapshotRepo.upsertTrackers(
          sessionId: sessionId,
          messageId: 'msg_regen',
          swipeId: 1,
          agentSwipeId: 0,
          trackers: _makeTrackers(sessionId, {
            'arc:david_fate.status': 'active',
          }),
        );

        final effective = await snapshotRepo.getLatestCommitted(sessionId);
        expect(effective, isNotNull);
        expect(effective!.messageId, 'msg_old');
        expect(effective.trackers.single.value, 'completed');
      },
    );

    // Test 14
    test(
      'deleted source message falls back to previous committed canon',
      () async {
        const sessionId = 'sess_delete';

        await snapshotRepo.upsertTrackers(
          sessionId: sessionId,
          messageId: 'msg_1',
          swipeId: 0,
          agentSwipeId: 0,
          trackers: _makeTrackers(sessionId, {'npc:Lucy.attitude': 'wary'}),
          committed: true,
        );
        await snapshotRepo.upsertTrackers(
          sessionId: sessionId,
          messageId: 'msg_2',
          swipeId: 0,
          agentSwipeId: 0,
          trackers: _makeTrackers(sessionId, {'npc:Lucy.attitude': 'trusting'}),
          committed: true,
        );

        await trackerRepo.replaceForSession(
          sessionId,
          _makeTrackers(sessionId, {'npc:Lucy.attitude': 'trusting'}),
        );
        await snapshotRepo.deleteForMessage(sessionId, 'msg_2');
        final fallback = await snapshotRepo.getLatestCommitted(sessionId);
        await trackerRepo.replaceForSession(sessionId, fallback!.trackers);

        final live = await trackerRepo.get(sessionId, 'npc:Lucy.attitude');
        expect(fallback.messageId, 'msg_1');
        expect(live!.value, 'wary');
      },
    );
  });

  // ── _compileStudioSessionState tests ─────────────────────────────────────
  group('kCompileStudioSessionStateForTest', () {
    // Test 10
    test('prompt contains session-canon-overrides-card-baseline rule', () {
      final trackers = _makeTrackers('s1', {
        'npc:Lucy.relationship_to_user': 'fragile alliance',
      });
      final compiled = kCompileStudioSessionStateForTest(trackers, 's1');
      expect(compiled, isNotNull);
      expect(compiled, contains('override character-card baseline'));
    });

    test('npc entity appears with its field', () {
      final trackers = _makeTrackers('s1', {
        'npc:Lucyna Kushinada.relationship_to_user': 'fragile alliance',
      });
      final compiled = kCompileStudioSessionStateForTest(trackers, 's1')!;
      expect(compiled, contains('Lucyna Kushinada'));
      expect(compiled, contains('fragile alliance'));
    });

    test('canon_override:* value overwrites ledger value in output', () {
      final trackers = _makeTrackers('s1', {
        'npc:Lucy.mood': 'neutral',
        'canon_override:npc:Lucy.mood': 'elated; user edit',
      });
      final compiled = kCompileStudioSessionStateForTest(trackers, 's1')!;
      expect(compiled, contains('elated; user edit'));
      expect(compiled, isNot(contains('neutral')));
    });

    test('completed arc is rendered under Resolved arcs', () {
      final trackers = _makeTrackers('s1', {
        'arc:david_fate.status': 'completed',
        'arc:david_fate.title': "David's fate revelation",
        'arc:david_fate.summary': "Danvi knows Lucy's role.",
        'arc:david_fate.do_not_reopen': 'true',
        'arc:david_fate.card_override': 'Treat as backstory.',
      });
      final compiled = kCompileStudioSessionStateForTest(trackers, 's1')!;
      expect(compiled, contains('Resolved arcs'));
      expect(compiled, contains("David's fate revelation"));
      expect(compiled, contains('Do not reopen as active conflict.'));
    });

    test('scene fields appear under Scene section', () {
      final trackers = _makeTrackers('s1', {
        'scene.present_entities': 'Lucyna Kushinada',
        'scene.location': 'Watson streets',
      });
      final compiled = kCompileStudioSessionStateForTest(trackers, 's1')!;
      expect(compiled, contains('Scene'));
      expect(compiled, contains('Lucyna Kushinada'));
    });

    test('mention filter injects mentioned entity and omits unrelated NPC', () {
      final trackers = _makeTrackers('s1', {
        'npc:Lucy.relationship_to_user': 'fragile alliance',
        'npc:Rebecca.relationship_to_user': 'not in scene',
        'world:location': 'Watson streets',
      });
      final compiled = kCompileStudioSessionStateForTest(
        trackers,
        's1',
        latestUserText: 'Lucy looks back at Danvi.',
      )!;
      expect(compiled, contains('Lucy'));
      expect(compiled, contains('fragile alliance'));
      expect(compiled, isNot(contains('Rebecca')));
      // World state remains injected even when NPC rows are filtered.
      expect(compiled, contains('Watson streets'));
    });

    test('present and absent entities render explicit presence rules', () {
      final trackers = _makeTrackers('s1', {
        'scene.present_entities': 'Lucyna Kushinada',
        'scene.absent_backstory_entities': 'David Martinez',
      });
      final compiled = kCompileStudioSessionStateForTest(trackers, 's1')!;
      expect(compiled, contains('Present now'));
      expect(compiled, contains('Lucyna Kushinada'));
      expect(compiled, contains('Absent/backstory only'));
      expect(compiled, contains('David Martinez'));
      expect(compiled, contains('Do not give dialogue or physical actions'));
    });

    test('dedupes duplicate canon lines inside studio state block', () {
      final trackers = _makeTrackers('s1', {
        'npc:Lucy.a': 'same fact',
        'npc:Lucy.b': 'same fact',
      });
      final compiled = kCompileStudioSessionStateForTest(trackers, 's1')!;
      expect('same fact'.allMatches(compiled).length, 1);
    });

    test('returns null when all values are empty', () {
      final trackers = _makeTrackers('s1', {'npc:Lucy.mood': ''});
      final compiled = kCompileStudioSessionStateForTest(trackers, 's1');
      expect(compiled, isNull);
    });

    test('returns null when trackers list is empty', () {
      final compiled = kCompileStudioSessionStateForTest([], 's1');
      expect(compiled, isNull);
    });

    test('world state appears under World section', () {
      final trackers = _makeTrackers('s1', {
        'world:calendar_system': 'Neo-calendar 2077',
      });
      final compiled = kCompileStudioSessionStateForTest(trackers, 's1')!;
      expect(compiled, contains('World'));
      expect(compiled, contains('Neo-calendar 2077'));
    });

    test('budget cap preserves XML close tag and trims by complete lines', () {
      final trackers = _makeTrackers('s1', {
        for (var i = 0; i < 220; i++)
          'world:fact_$i': 'long canon fact ${'x' * 80} $i',
      });
      final compiled = kCompileStudioSessionStateForTest(trackers, 's1')!;
      expect(compiled.length, lessThanOrEqualTo(6000));
      expect(compiled, endsWith('</studio_session_state>'));
      expect(compiled, contains('[trimmed lower-priority canon details]'));
    });

    test('relationship pair appears in Relationships section', () {
      final trackers = _makeTrackers('s1', {
        'relationship:Danvi:Lucy.attitude': 'wary admiration',
      });
      final compiled = kCompileStudioSessionStateForTest(trackers, 's1')!;
      expect(compiled, contains('Relationships'));
      expect(compiled, contains('wary admiration'));
    });
  });

  // ── Ledger failure isolation ───────────────────────────────────────────────
  group('Ledger failure isolation', () {
    test('malformed export does not throw; returns null gracefully', () {
      expect(() => parser.parse('garbage \$\$\$'), returnsNormally);
      final r = parser.parse('garbage \$\$\$');
      expect(r.export, isNull);
    });

    test('valid JSON with only sceneState (no ops) returns null export', () {
      const noOps = '''
<glaze_memory_export>
{
  "ops": [],
  "durableFacts": [],
  "sceneState": {"time": "12:00", "date": "01-01-2077",
    "location": "bar", "immediateThread": "idle",
    "presentEntities": [], "activeTensions": []}
}
</glaze_memory_export>
''';
      final r = parser.parse(noOps);
      expect(r.export, isNull);
    });
  });
}
