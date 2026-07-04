import 'package:flutter_test/flutter_test.dart';
import 'package:glaze_flutter/core/models/pipeline_settings.dart';

void main() {
  group('PipelineSettings memory cadence', () {
    test('memoryDedupThreshold defaults to 0.85', () {
      const settings = PipelineSettings();
      expect(settings.memoryPipeline.memoryDedupThreshold, 0.85);
    });

    test('hardcoded every-5-turns cadence suppresses turns 1-4, allows turn 5', () {
      // Cadence is hardcoded: the write-loop runs every 5 assistant turns.
      // Simulate the cadence check logic from generation_pipeline.dart.
      String? checkCadence(int assistantTurnCount) {
        const n = 5;
        if (n > 1 && assistantTurnCount % n != 0) {
          return 'skipping — not a multiple';
        }
        return null;
      }

      expect(checkCadence(1), isNotNull);
      expect(checkCadence(2), isNotNull);
      expect(checkCadence(3), isNotNull);
      expect(checkCadence(4), isNotNull);
      expect(checkCadence(5), isNull);
      expect(checkCadence(10), isNull);
      expect(checkCadence(6), isNotNull);
    });
  });
}
