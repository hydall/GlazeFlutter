import 'package:flutter_test/flutter_test.dart';

import 'package:glaze_flutter/core/models/pipeline_settings.dart';
import 'package:glaze_flutter/core/models/studio_config.dart';

void main() {
  group('Stage 5 — Agentic advanced toggle defaults', () {
    test('MemoryBookSettings: all agentic features off by default', () {
      const settings = PipelineSettings();
      expect(settings.agenticWriteEnabled, isFalse);
      expect(settings.postCleanerEnabled, isFalse);
    });

    test('StudioConfig: routingMode defaults to verbatim', () {
      const config = StudioConfig(sessionId: 's1');
      expect(config.routingMode, 'verbatim');
    });

    test('MemoryBookSettings: can enable all agentic features', () {
      const settings = PipelineSettings(
        agenticWriteEnabled: true,
        postCleanerEnabled: true,
      );
      expect(settings.agenticWriteEnabled, isTrue);
      expect(settings.postCleanerEnabled, isTrue);
    });

    test('StudioConfig: can switch to compiled routing', () {
      const config = StudioConfig(
        sessionId: 's1',
        routingMode: 'compiled',
      );
      expect(config.routingMode, 'compiled');
    });
  });

  group('Stage 5 — Feature independence', () {
    test('write-loop and POST-cleaner are independent toggles', () {
      const writeOnly = PipelineSettings(
        agenticWriteEnabled: true,
        postCleanerEnabled: false,
      );
      const cleanerOnly = PipelineSettings(
        agenticWriteEnabled: false,
        postCleanerEnabled: true,
      );
      const bothOff = PipelineSettings();
      const bothOn = PipelineSettings(
        agenticWriteEnabled: true,
        postCleanerEnabled: true,
      );

      expect(writeOnly.agenticWriteEnabled && !writeOnly.postCleanerEnabled, isTrue);
      expect(!cleanerOnly.agenticWriteEnabled && cleanerOnly.postCleanerEnabled, isTrue);
      expect(!bothOff.agenticWriteEnabled && !bothOff.postCleanerEnabled, isTrue);
      expect(bothOn.agenticWriteEnabled && bothOn.postCleanerEnabled, isTrue);
    });

    test('routingMode is independent from MemoryBook features', () {
      const config = StudioConfig(
        sessionId: 's1',
        routingMode: 'compiled',
      );
      const settings = PipelineSettings(
        agenticWriteEnabled: true,
        postCleanerEnabled: true,
      );
      // routingMode lives on StudioConfig, not PipelineSettings
      expect(config.routingMode, 'compiled');
      expect(settings.agenticWriteEnabled, isTrue);
      expect(settings.postCleanerEnabled, isTrue);
    });
  });

  group('Stage 5 — Default UX (invisible by default)', () {
    // The design principle: everything is OFF by default. The user must
    // explicitly enable each feature. This is the "invisible by default +
    // power-user toggle" UX from docs/PLAN_AGENTIC_STUDIO.md §7.

    test('no agentic feature is on without explicit opt-in', () {
      const settings = PipelineSettings();
      const config = StudioConfig(sessionId: 's1');

      expect(settings.agenticWriteEnabled, isFalse);
      expect(settings.postCleanerEnabled, isFalse);
      expect(config.enabled, isFalse);
      // routingMode='verbatim' is the default but it's not an "agentic"
      // feature — it's just how decomposition works. It's always on.
    });

    test('copyWith preserves existing toggles when updating one', () {
      const initial = PipelineSettings(
        agenticWriteEnabled: true,
        postCleanerEnabled: false,
      );
      final updated = initial.copyWith(postCleanerEnabled: true);

      expect(updated.agenticWriteEnabled, isTrue);
      expect(updated.postCleanerEnabled, isTrue);
    });
  });
}
