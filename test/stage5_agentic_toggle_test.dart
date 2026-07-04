import 'package:flutter_test/flutter_test.dart';

import 'package:glaze_flutter/core/models/studio_config.dart';

void main() {
  group('Stage 5 — StudioConfig defaults', () {
    test('StudioConfig: defaults are correct', () {
      const config = StudioConfig(sessionId: 's1');
      expect(config.enabled, isFalse);
      expect(config.studioPresetId, 'default');
    });

    test('studioPresetId can be overridden', () {
      const config = StudioConfig(
        sessionId: 's1',
        studioPresetId: 'custom',
      );
      expect(config.studioPresetId, 'custom');
    });
  });
}
