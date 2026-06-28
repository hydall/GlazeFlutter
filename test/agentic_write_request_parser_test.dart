import 'package:flutter_test/flutter_test.dart';

import 'package:glaze_flutter/core/llm/agentic_write_request_parser.dart';

/// §3: tests for AgenticWriteRequestParser.parseWriteResponse (the JSON
/// parsing helper extracted from askLlmForWrites). The retry-on-invalid-JSON
/// logic itself is exercised in the characterization suite; here we verify
/// the parser handles valid, invalid, and edge-case LLM output.
void main() {
  group('parseWriteResponse', () {
    test('parses valid JSON with trackers + memories', () {
      final text = '''
{
  "trackers": [
    {"name": "mood", "value": "happy", "scope": "chat"},
    {"name": "location", "value": "tavern"}
  ],
  "memories": [
    {"title": "Lucy reveals the chip", "content": "She showed a hidden chip", "keys": ["Lucy", "chip"]}
  ]
}
''';
      final response = AgenticWriteRequestParser.parseWriteResponse(text);
      expect(response, isNotNull);
      expect(response!.trackerRequests.length, 2);
      expect(response.trackerRequests.first.name, 'mood');
      expect(response.trackerRequests.first.value, 'happy');
      expect(response.memoryRequests.length, 1);
      expect(response.memoryRequests.first.title, 'Lucy reveals the chip');
      expect(response.memoryRequests.first.keys, ['Lucy', 'chip']);
    });

    test('returns null for invalid JSON', () {
      final response = AgenticWriteRequestParser.parseWriteResponse(
        'This is not JSON at all.',
      );
      expect(response, isNull);
    });

    test('returns null for JSON wrapped in markdown fences', () {
      final text = '''
```json
{"trackers": [], "memories": []}
```
''';
      final response = AgenticWriteRequestParser.parseWriteResponse(text);
      expect(response, isNull);
    });

    test('returns null when top-level is not a Map', () {
      final response = AgenticWriteRequestParser.parseWriteResponse(
        '[1, 2, 3]',
      );
      expect(response, isNull);
    });

    test('parses empty trackers + memories', () {
      final response = AgenticWriteRequestParser.parseWriteResponse(
        '{"trackers": [], "memories": []}',
      );
      expect(response, isNotNull);
      expect(response!.trackerRequests, isEmpty);
      expect(response.memoryRequests, isEmpty);
    });

    test('skips tracker entries with empty name or value', () {
      final text = '''
{
  "trackers": [
    {"name": "", "value": "x"},
    {"name": "mood", "value": ""},
    {"name": "location", "value": "tavern"}
  ],
  "memories": []
}
''';
      final response = AgenticWriteRequestParser.parseWriteResponse(text);
      expect(response, isNotNull);
      expect(response!.trackerRequests.length, 1);
      expect(response.trackerRequests.first.name, 'location');
    });

    test('skips memory entries with empty title or content', () {
      final text = '''
{
  "trackers": [],
  "memories": [
    {"title": "", "content": "x"},
    {"title": "Valid", "content": ""}
  ]
}
''';
      final response = AgenticWriteRequestParser.parseWriteResponse(text);
      expect(response, isNotNull);
      expect(response!.memoryRequests, isEmpty);
    });

    test('parses existingEntryId for append-only update', () {
      final text = '''
{
  "trackers": [],
  "memories": [
    {"title": "Update", "content": "new fact", "keys": ["k"], "existingEntryId": "mem_abc"}
  ]
}
''';
      final response = AgenticWriteRequestParser.parseWriteResponse(text);
      expect(response, isNotNull);
      expect(response!.memoryRequests.length, 1);
      expect(response.memoryRequests.first.existingEntryId, 'mem_abc');
    });
  });
}
