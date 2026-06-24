import 'package:flutter_test/flutter_test.dart';

import 'package:glaze_flutter/core/llm/memory_agentic_policy.dart';
import 'package:glaze_flutter/core/llm/memory_agentic_tools.dart';
import 'package:glaze_flutter/core/models/memory_book.dart';

void main() {
  group('MemoryAgenticToolDefinition (Phase 10)', () {
    test('searchMemory returns valid OpenAI tool definition', () {
      final tool = MemoryAgenticToolDefinition.searchMemory();
      expect(tool['type'], 'function');
      expect(tool['function']['name'], 'searchMemory');
      expect(tool['function']['parameters']['properties']['query']['type'], 'string');
    });

    test('readOnlyTools returns only searchMemory', () {
      final tools = MemoryAgenticToolDefinition.readOnlyTools();
      expect(tools, hasLength(1));
      expect(tools.first['function']['name'], 'searchMemory');
    });

    test('forPolicy returns empty when disabled', () {
      const policy = MemoryAgenticPolicy(MemoryAgenticSettings(enabled: false));
      final tools = MemoryAgenticToolDefinition.forPolicy(policy);
      expect(tools, isEmpty);
    });

    test('forPolicy returns read-only tools when enabled+readOnly', () {
      const policy = MemoryAgenticPolicy(
        MemoryAgenticSettings(enabled: true, readOnly: true),
      );
      final tools = MemoryAgenticToolDefinition.forPolicy(policy);
      expect(tools, hasLength(1));
    });
  });

  group('MemoryAgenticToolHandler (Phase 10)', () {
    test('denied when policy disabled', () {
      const policy = MemoryAgenticPolicy(MemoryAgenticSettings(enabled: false));
      const handler = MemoryAgenticToolHandler(policy);
      final result = handler.searchMemory(
        entries: const [],
        query: 'test',
        visibleMessageIds: const {},
      );
      expect(result.error, 'agentic_disabled');
      expect(result.hits, isEmpty);
    });

    test('returns hits for matching entries', () {
      const policy = MemoryAgenticPolicy(
        MemoryAgenticSettings(enabled: true, readOnly: true),
      );
      const handler = MemoryAgenticToolHandler(policy);
      final entries = [
        MemoryEntry(
          id: 'm1',
          title: 'Bridge collapse',
          content: 'The bridge collapsed into the river',
          keys: const ['bridge', 'river'],
        ),
        MemoryEntry(
          id: 'm2',
          title: 'Unrelated event',
          content: 'something else entirely',
        ),
      ];
      final result = handler.searchMemory(
        entries: entries,
        query: 'bridge',
        visibleMessageIds: const {},
        keywordMatchedTerms: const {
          'm1': ['bridge'],
        },
      );
      expect(result.hits, isNotEmpty);
      expect(result.hits.first.entryId, 'm1');
      expect(result.hits.first.title, 'Bridge collapse');
    });

    test('respects maxResults cap', () {
      const policy = MemoryAgenticPolicy(
        MemoryAgenticSettings(enabled: true, readOnly: true),
      );
      const handler = MemoryAgenticToolHandler(policy);
      final entries = List.generate(
        15,
        (i) => MemoryEntry(
          id: 'm$i',
          title: 'Entry $i',
          content: 'content $i ' * 10,
          keys: const ['key'],
        ),
      );
      final result = handler.searchMemory(
        entries: entries,
        query: 'key',
        visibleMessageIds: const {},
        maxResults: 3,
        keywordMatchedTerms: {
          for (final e in entries) e.id: ['key'],
        },
      );
      expect(result.hits.length, lessThanOrEqualTo(3));
    });

    test('excludes entries visible in prompt window', () {
      const policy = MemoryAgenticPolicy(
        MemoryAgenticSettings(enabled: true, readOnly: true),
      );
      const handler = MemoryAgenticToolHandler(policy);
      final entries = [
        MemoryEntry(
          id: 'm1',
          title: 'Visible',
          content: 'visible memory',
          messageIds: const ['visible_msg'],
        ),
        MemoryEntry(
          id: 'm2',
          title: 'Hidden',
          content: 'hidden memory',
          messageIds: const ['hidden_msg'],
        ),
      ];
      final result = handler.searchMemory(
        entries: entries,
        query: 'memory',
        visibleMessageIds: const {'visible_msg'},
        keywordMatchedTerms: const {
          'm1': ['memory'],
          'm2': ['memory'],
        },
      );
      expect(result.hits.any((h) => h.entryId == 'm1'), isFalse);
    });

    test('hits contain metadata but not full content', () {
      const policy = MemoryAgenticPolicy(
        MemoryAgenticSettings(enabled: true, readOnly: true),
      );
      const handler = MemoryAgenticToolHandler(policy);
      final entries = [
        MemoryEntry(
          id: 'm1',
          title: 'Test',
          content: 'full content here',
          keys: const ['test'],
        ),
      ];
      final result = handler.searchMemory(
        entries: entries,
        query: 'test',
        visibleMessageIds: const {},
        keywordMatchedTerms: const {
          'm1': ['test'],
        },
      );
      expect(result.hits, hasLength(1));
      final json = result.hits.first.toJson();
      expect(json['entryId'], 'm1');
      expect(json['title'], 'Test');
      expect(json.containsKey('content'), isFalse);
    });
  });

  group('MemoryAgenticPolicy (Phase 10)', () {
    test('write tools denied in read-only mode', () {
      const policy = MemoryAgenticPolicy(
        MemoryAgenticSettings(enabled: true, readOnly: true),
      );
      final decision = policy.canUse(MemoryAgenticTool.writeMemory);
      expect(decision.allowed, isFalse);
      expect(decision.reason, 'agentic_read_only');
    });

    test('write tools denied without diff approval', () {
      const policy = MemoryAgenticPolicy(
        MemoryAgenticSettings(
          enabled: true,
          readOnly: false,
          writeToolsEnabled: true,
          requireExplicitDiffApproval: true,
        ),
      );
      final decision = policy.canUse(MemoryAgenticTool.writeMemory);
      expect(decision.allowed, isFalse);
      expect(decision.reason, 'diff_approval_required');
    });

    test('write tools allowed with diff approval', () {
      const policy = MemoryAgenticPolicy(
        MemoryAgenticSettings(
          enabled: true,
          readOnly: false,
          writeToolsEnabled: true,
          requireExplicitDiffApproval: true,
        ),
      );
      final decision = policy.canUse(
        MemoryAgenticTool.writeMemory,
        explicitDiffApproved: true,
      );
      expect(decision.allowed, isTrue);
    });

    test('read tools always allowed when enabled', () {
      const policy = MemoryAgenticPolicy(
        MemoryAgenticSettings(enabled: true, readOnly: true),
      );
      final decision = policy.canUse(MemoryAgenticTool.inspectContext);
      expect(decision.allowed, isTrue);
    });
  });
}
