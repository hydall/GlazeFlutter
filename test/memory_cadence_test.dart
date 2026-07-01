import 'package:flutter_test/flutter_test.dart';

import 'package:glaze_flutter/core/models/pipeline_settings.dart';

void main() {
  group('PipelineSettings memory cadence defaults', () {
    test('agenticWriteRunMode defaults to every_n', () {
      const settings = PipelineSettings();
      expect(settings.agenticWriteRunMode, 'every_n');
    });

    test('runAgenticEveryN defaults to 5', () {
      const settings = PipelineSettings();
      expect(settings.runAgenticEveryN, 5);
    });

    test('memoryDedupAutoEnabled defaults to false', () {
      const settings = PipelineSettings();
      expect(settings.memoryDedupAutoEnabled, false);
    });

    test('memoryDedupThreshold defaults to 0.85', () {
      const settings = PipelineSettings();
      expect(settings.memoryDedupThreshold, 0.85);
    });

    test('cadence every_n with N=5 suppresses turns 1-4, allows turn 5', () {
      const settings = PipelineSettings(
        agenticWriteRunMode: 'every_n',
        runAgenticEveryN: 5,
      );

      // Simulate the cadence check logic from generation_pipeline.dart.
      String? checkCadence(int assistantTurnCount) {
        switch (settings.agenticWriteRunMode) {
          case 'disabled':
            return 'skipping';
          case 'manual':
            return 'skipping';
          case 'every_n':
            final n = settings.runAgenticEveryN < 1
                ? 1
                : settings.runAgenticEveryN;
            if (n > 1 && assistantTurnCount % n != 0) {
              return 'skipping — not a multiple';
            }
            return null;
          case 'every_turn':
          default:
            return null;
        }
      }

      // Turns 1-4 should be suppressed.
      expect(checkCadence(1), isNotNull);
      expect(checkCadence(2), isNotNull);
      expect(checkCadence(3), isNotNull);
      expect(checkCadence(4), isNotNull);

      // Turn 5 should run.
      expect(checkCadence(5), isNull);

      // Turn 10 should run.
      expect(checkCadence(10), isNull);

      // Turn 6 should be suppressed.
      expect(checkCadence(6), isNotNull);
    });

    test('legacy every_turn mode runs every turn', () {
      const settings = PipelineSettings(
        agenticWriteRunMode: 'every_turn',
        runAgenticEveryN: 1,
      );

      String? checkCadence(int assistantTurnCount) {
        switch (settings.agenticWriteRunMode) {
          case 'every_n':
            final n = settings.runAgenticEveryN < 1
                ? 1
                : settings.runAgenticEveryN;
            if (n > 1 && assistantTurnCount % n != 0) {
              return 'skipping';
            }
            return null;
          case 'every_turn':
          default:
            return null;
        }
      }

      expect(checkCadence(1), isNull);
      expect(checkCadence(2), isNull);
      expect(checkCadence(3), isNull);
    });
  });
}
