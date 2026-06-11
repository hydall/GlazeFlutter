import 'package:flutter_test/flutter_test.dart';
import 'package:glaze_flutter/core/llm/memory_classifier_schema.dart';

void main() {
  test('classifier output schema parses bounded structured output', () {
    final output = MemoryClassifierOutput.fromJson({
      'needsMemory': true,
      'reliableCandidateFound': false,
      'confidence': 1.4,
      'queryExpansion': [' bridge ', '', 12, 'Sable'],
      'reasons': ['old promise', null, 'weak retrieval'],
    });

    expect(output.needsMemory, isTrue);
    expect(output.reliableCandidateFound, isFalse);
    expect(output.confidence, 1.0);
    expect(output.queryExpansion, ['bridge', 'Sable']);
    expect(output.reasons, ['old promise', 'weak retrieval']);
    expect(output.toJson(), {
      'needsMemory': true,
      'reliableCandidateFound': false,
      'confidence': 1.0,
      'queryExpansion': ['bridge', 'Sable'],
      'reasons': ['old promise', 'weak retrieval'],
    });
  });

  test('classifier output schema falls back safely for invalid fields', () {
    final output = MemoryClassifierOutput.fromJson({
      'needsMemory': 'yes',
      'reliableCandidateFound': 1,
      'confidence': 'high',
      'queryExpansion': 'bridge',
      'reasons': null,
    });

    expect(output.needsMemory, isFalse);
    expect(output.reliableCandidateFound, isFalse);
    expect(output.confidence, 0);
    expect(output.queryExpansion, isEmpty);
    expect(output.reasons, isEmpty);
  });
}
