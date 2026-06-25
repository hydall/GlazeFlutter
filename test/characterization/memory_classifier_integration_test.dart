import 'package:flutter_test/flutter_test.dart';

import 'package:glaze_flutter/core/llm/memory_needs_classifier_service.dart';
import 'package:glaze_flutter/core/llm/memory_classifier_schema.dart';
import 'package:glaze_flutter/core/models/memory_book.dart';

void main() {
  group('MemoryNeedsClassifierService integration (Track 1)', () {
    test('disabled when classifierEnabled is false', () async {
      final service = MemoryNeedsClassifierService((_, __) async => '{}');
      final result = await service.classify(MemoryClassifierRequest(
        settings: const MemoryBookSettings(classifierEnabled: false),
        currentText: 'remember the bridge?',
      ));
      expect(result.status, 'disabled');
    });

    test('parses valid JSON output', () async {
      const json = '''
{"needsMemory": true, "reliableCandidateFound": true, "confidence": 0.85, "queryExpansion": ["bridge", "promise"], "reasons": ["user references old event"]}
''';
      final service = MemoryNeedsClassifierService((_, __) async => json);
      final result = await service.classify(MemoryClassifierRequest(
        settings: const MemoryBookSettings(classifierEnabled: true),
        currentText: 'remember the bridge?',
        candidateTitles: ['Bridge collapse'],
      ));
      expect(result.status, 'ok');
      expect(result.output!.needsMemory, isTrue);
      expect(result.output!.reliableCandidateFound, isTrue);
      expect(result.output!.confidence, closeTo(0.85, 0.001));
      expect(result.output!.queryExpansion, contains('bridge'));
    });

    test('returns invalid_output for non-JSON response', () async {
      final service =
          MemoryNeedsClassifierService((_, __) async => 'not json');
      final result = await service.classify(MemoryClassifierRequest(
        settings: const MemoryBookSettings(
          classifierEnabled: true,
          classifierTimeoutMs: 5000,
        ),
        currentText: 'test',
      ));
      expect(result.status, 'invalid_output');
    });

    test('returns timeout on slow response', () async {
      final service = MemoryNeedsClassifierService((_, __) async {
        await Future.delayed(const Duration(milliseconds: 200));
        return '{}';
      });
      final result = await service.classify(MemoryClassifierRequest(
        settings: const MemoryBookSettings(
          classifierEnabled: true,
          classifierTimeoutMs: 50,
        ),
        currentText: 'test',
      ));
      expect(result.status, 'timeout');
    });
  });

  group('MemoryClassifierOutput schema', () {
    test('fromJson parses all fields', () {
      final json = {
        'needsMemory': true,
        'reliableCandidateFound': false,
        'confidence': 0.42,
        'queryExpansion': ['old', 'bridge'],
        'reasons': ['indirect reference'],
      };
      final output = MemoryClassifierOutput.fromJson(json);
      expect(output.needsMemory, isTrue);
      expect(output.reliableCandidateFound, isFalse);
      expect(output.confidence, 0.42);
      expect(output.queryExpansion, ['old', 'bridge']);
      expect(output.reasons, ['indirect reference']);
    });

    test('fromJson handles missing optional fields', () {
      final output = MemoryClassifierOutput.fromJson({});
      expect(output.needsMemory, isFalse);
      expect(output.reliableCandidateFound, isFalse);
      expect(output.confidence, 0.0);
      expect(output.queryExpansion, isEmpty);
      expect(output.reasons, isEmpty);
    });
  });
}
