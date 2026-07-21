import 'package:flutter_test/flutter_test.dart';

import 'package:glaze_flutter/core/models/studio_agent_settings.dart';

void main() {
  test('last reasoning history setting is backward-compatible', () {
    expect(
      StudioAgentSettings.fromJson(const {}).studioFinalIncludeLastReasoning,
      isFalse,
    );

    final settings = StudioAgentSettings.fromJson(const {
      'studioFinalIncludeLastReasoning': true,
    });

    expect(settings.studioFinalIncludeLastReasoning, isTrue);
    expect(settings.toJson()['studioFinalIncludeLastReasoning'], isTrue);
  });
}
