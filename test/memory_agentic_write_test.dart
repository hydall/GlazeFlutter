import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:glaze_flutter/core/db/app_db.dart';
import 'package:glaze_flutter/core/db/repositories/tracker_repo.dart';
import 'package:glaze_flutter/core/llm/memory_agentic_policy.dart';
import 'package:glaze_flutter/core/llm/memory_agentic_service.dart';
import 'package:glaze_flutter/core/llm/memory_agentic_tools.dart';

AppDatabase _testDb() => AppDatabase.forTesting(NativeDatabase.memory());

void main() {
  group('MemoryAgenticToolDefinition', () {
    test('searchMemory returns valid OpenAI tool definition', () {
      final def = MemoryAgenticToolDefinition.searchMemory();
      expect(def['type'], 'function');
      expect(def['function']['name'], 'searchMemory');
      expect(def['function']['parameters']['required'], ['query']);
    });

    test('updateTracker returns valid tool definition', () {
      final def = MemoryAgenticToolDefinition.updateTracker();
      expect(def['type'], 'function');
      expect(def['function']['name'], 'updateTracker');
      final required = def['function']['parameters']['required'] as List;
      expect(required, containsAll(['name', 'value']));
    });

    test('writeMemory returns valid tool definition', () {
      final def = MemoryAgenticToolDefinition.writeMemory();
      expect(def['type'], 'function');
      expect(def['function']['name'], 'writeMemory');
      final required = def['function']['parameters']['required'] as List;
      expect(required, containsAll(['title', 'content']));
    });

    test('readOnlyTools returns only searchMemory', () {
      final tools = MemoryAgenticToolDefinition.readOnlyTools();
      expect(tools.length, 1);
      expect(tools.first['function']['name'], 'searchMemory');
    });

    test('writeTools returns updateTracker + writeMemory', () {
      final tools = MemoryAgenticToolDefinition.writeTools();
      expect(tools.length, 2);
      final names = tools.map((t) => t['function']['name']).toSet();
      expect(names, {'updateTracker', 'writeMemory'});
    });

    test('forPolicy returns empty when disabled', () {
      final policy = MemoryAgenticPolicy(const MemoryAgenticSettings(
        enabled: false,
      ));
      expect(MemoryAgenticToolDefinition.forPolicy(policy), isEmpty);
    });

    test('forPolicy returns read-only tools when readOnly', () {
      final policy = MemoryAgenticPolicy(const MemoryAgenticSettings(
        enabled: true,
        readOnly: true,
      ));
      final tools = MemoryAgenticToolDefinition.forPolicy(policy);
      expect(tools.length, 1);
      expect(tools.first['function']['name'], 'searchMemory');
    });

    test('forPolicy returns all tools when write enabled', () {
      final policy = MemoryAgenticPolicy(const MemoryAgenticSettings(
        enabled: true,
        readOnly: false,
        writeToolsEnabled: true,
      ));
      final tools = MemoryAgenticToolDefinition.forPolicy(policy);
      expect(tools.length, 3);
    });
  });

  group('MemoryAgenticPolicy — write tools', () {
    test('denies writeMemory when readOnly', () {
      final policy = MemoryAgenticPolicy(const MemoryAgenticSettings(
        enabled: true,
        readOnly: true,
      ));
      final decision = policy.canUse(MemoryAgenticTool.writeMemory);
      expect(decision.allowed, isFalse);
      expect(decision.reason, 'agentic_read_only');
    });

    test('denies writeTracker when writeToolsEnabled is false', () {
      final policy = MemoryAgenticPolicy(const MemoryAgenticSettings(
        enabled: true,
        readOnly: false,
        writeToolsEnabled: false,
      ));
      final decision = policy.canUse(MemoryAgenticTool.writeTracker);
      expect(decision.allowed, isFalse);
      expect(decision.reason, 'write_tools_disabled');
    });

    test('allows writeTracker when write enabled', () {
      final policy = MemoryAgenticPolicy(const MemoryAgenticSettings(
        enabled: true,
        readOnly: false,
        writeToolsEnabled: true,
        requireExplicitDiffApproval: false,
      ));
      final decision = policy.canUse(MemoryAgenticTool.writeTracker);
      expect(decision.allowed, isTrue);
    });

    test('allows writeMemory when write enabled', () {
      final policy = MemoryAgenticPolicy(const MemoryAgenticSettings(
        enabled: true,
        readOnly: false,
        writeToolsEnabled: true,
        requireExplicitDiffApproval: false,
      ));
      final decision = policy.canUse(MemoryAgenticTool.writeMemory);
      expect(decision.allowed, isTrue);
    });

    test('denies all when disabled', () {
      final policy = MemoryAgenticPolicy(const MemoryAgenticSettings(
        enabled: false,
      ));
      expect(
        policy.canUse(MemoryAgenticTool.writeMemory).allowed,
        isFalse,
      );
      expect(
        policy.canUse(MemoryAgenticTool.writeTracker).allowed,
        isFalse,
      );
      expect(
        policy.canUse(MemoryAgenticTool.inspectContext).allowed,
        isFalse,
      );
    });
  });

  group('TrackerWriteRequest', () {
    test('parses from JSON', () {
      final req = TrackerWriteRequest.fromJson({
        'name': 'mood',
        'value': 'happy',
        'scope': 'chat',
      });
      expect(req.name, 'mood');
      expect(req.value, 'happy');
      expect(req.scope, 'chat');
    });

    test('defaults scope to chat when missing', () {
      final req = TrackerWriteRequest.fromJson({
        'name': 'location',
        'value': 'tavern',
      });
      expect(req.scope, 'chat');
    });

    test('handles missing fields gracefully', () {
      final req = TrackerWriteRequest.fromJson({});
      expect(req.name, '');
      expect(req.value, '');
      expect(req.scope, 'chat');
    });
  });

  group('MemoryWriteRequest', () {
    test('parses from JSON with keys', () {
      final req = MemoryWriteRequest.fromJson({
        'title': 'Lucy reveals the chip',
        'content': 'Lucy showed a hidden microchip...',
        'keys': ['Lucy', 'chip', 'secret'],
      });
      expect(req.title, 'Lucy reveals the chip');
      expect(req.content, 'Lucy showed a hidden microchip...');
      expect(req.keys, ['Lucy', 'chip', 'secret']);
    });

    test('defaults keys to empty list', () {
      final req = MemoryWriteRequest.fromJson({
        'title': 'Test',
        'content': 'Content',
      });
      expect(req.keys, isEmpty);
    });
  });

  group('TrackerRepo — write integration', () {
    late AppDatabase db;
    late TrackerRepo repo;

    setUp(() {
      db = _testDb();
      repo = TrackerRepo(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('upsertValue writes a tracker that can be read back', () async {
      await repo.upsertValue(
        's1',
        'mood',
        'happy',
        provenance: 'memory_agent',
      );

      final got = await repo.get('s1', 'mood');
      expect(got, isNotNull);
      expect(got!.value, 'happy');
      expect(got.provenance, 'memory_agent');
      expect(got.scope, 'chat');
    });

    test('upsertValue overwrites existing tracker', () async {
      await repo.upsertValue('s1', 'mood', 'happy');
      await repo.upsertValue('s1', 'mood', 'angry');

      final got = await repo.get('s1', 'mood');
      expect(got!.value, 'angry');
    });

    test('multiple trackers from same agent coexist', () async {
      await repo.upsertValue('s1', 'mood', 'happy', provenance: 'agent');
      await repo.upsertValue('s1', 'location', 'tavern', provenance: 'agent');
      await repo.upsertValue('s1', 'relationship', 'allies',
          provenance: 'agent');

      final all = await repo.getBySessionId('s1');
      expect(all.length, 3);
    });
  });

  group('MemoryWriteLoopResult', () {
    test('disabled status has no writes', () {
      const result = MemoryWriteLoopResult(status: 'disabled');
      expect(result.totalWritten, 0);
      expect(result.anyWrites, isFalse);
    });

    test('counts writes from both trackers and memories', () {
      const result = MemoryWriteLoopResult(
        status: 'ok',
        trackerResult: TrackerWriteResult(written: 3),
        memoryResult: MemoryWriteResult(written: 1),
      );
      expect(result.totalWritten, 4);
      expect(result.anyWrites, isTrue);
    });
  });
}
