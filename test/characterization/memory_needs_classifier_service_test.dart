import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glaze_flutter/core/llm/memory_needs_classifier_service.dart';
import 'package:glaze_flutter/core/models/memory_book.dart';

void main() {
  const enabledSettings = MemoryBookSettings(
    classifierEnabled: true,
    classifierTimeoutMs: 50,
  );

  test('returns disabled without calling the classifier client', () async {
    var called = false;
    final service = MemoryNeedsClassifierService((_, _) async {
      called = true;
      return '{}';
    });

    final result = await service.classify(
      const MemoryClassifierRequest(
        settings: MemoryBookSettings(classifierEnabled: false),
        currentText: 'remember?',
      ),
    );

    expect(result.status, 'disabled');
    expect(result.output, isNull);
    expect(called, isFalse);
  });

  test('parses valid classifier output', () async {
    final service = MemoryNeedsClassifierService((request, _) async {
      expect(request.currentText, 'remember the bridge?');
      return '{"needsMemory":true,"reliableCandidateFound":false,"confidence":0.8,"queryExpansion":["bridge"],"reasons":["old reference"]}';
    });

    final result = await service.classify(
      const MemoryClassifierRequest(
        settings: enabledSettings,
        currentText: 'remember the bridge?',
      ),
    );

    expect(result.status, 'ok');
    expect(result.usedModel, isTrue);
    expect(result.output!.needsMemory, isTrue);
    expect(result.output!.confidence, 0.8);
    expect(result.output!.queryExpansion, ['bridge']);
  });

  test('invalid output falls back without throwing', () async {
    final service = MemoryNeedsClassifierService((_, _) async => 'not json');

    final result = await service.classify(
      const MemoryClassifierRequest(
        settings: enabledSettings,
        currentText: 'remember?',
      ),
    );

    expect(result.status, 'invalid_output');
    expect(result.output, isNull);
  });

  test('timeout falls back without throwing', () async {
    final service = MemoryNeedsClassifierService((_, _) async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      return '{}';
    });

    final result = await service.classify(
      const MemoryClassifierRequest(
        settings: enabledSettings,
        currentText: 'remember?',
      ),
    );

    expect(result.status, 'timeout');
    expect(result.output, isNull);
  });

  test('cancelled token returns aborted and ignores late output', () async {
    final cancelToken = CancelToken();
    final service = MemoryNeedsClassifierService((_, _) async {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      return '{"needsMemory":true,"reliableCandidateFound":true,"confidence":1}';
    });

    final future = service.classify(
      const MemoryClassifierRequest(
        settings: enabledSettings,
        currentText: 'remember?',
      ),
      cancelToken: cancelToken,
    );
    cancelToken.cancel('test abort');

    final result = await future;
    expect(result.status, 'aborted');
    expect(result.output, isNull);
  });
}
