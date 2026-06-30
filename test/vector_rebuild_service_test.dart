import 'package:flutter_test/flutter_test.dart';

import 'package:glaze_flutter/core/llm/vector_rebuild_service.dart';

void main() {
  group('vectorRebuildDelayForRate', () {
    test('returns zero delay when rate limit is disabled', () {
      expect(vectorRebuildDelayForRate(0), Duration.zero);
      expect(vectorRebuildDelayForRate(-5), Duration.zero);
    });

    test('converts vectors per minute into inter-task delay', () {
      expect(vectorRebuildDelayForRate(60), const Duration(seconds: 1));
      expect(vectorRebuildDelayForRate(30), const Duration(seconds: 2));
    });
  });
}
