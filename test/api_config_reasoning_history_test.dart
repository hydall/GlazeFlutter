import 'package:flutter_test/flutter_test.dart';
import 'package:glaze_flutter/core/models/api_config.dart';

void main() {
  test('reasoning settings are backward-compatible', () {
    final config = ApiConfig.fromJson(const {'id': 'api'});

    expect(config.includeLastReasoning, isFalse);
    expect(config.showNativeReasoning, isTrue);
    expect(config.omitTopK, isFalse);
    expect(config.omitFrequencyPenalty, isFalse);
    expect(config.omitPresencePenalty, isFalse);
  });

  test('legacy omitReasoning controls the initial visibility default', () {
    final visible = ApiConfig.fromJson(const {
      'id': 'visible',
      'omitReasoning': false,
    });
    final hidden = ApiConfig.fromJson(const {
      'id': 'hidden',
      'omitReasoning': true,
    });

    expect(visible.showNativeReasoning, isTrue);
    expect(hidden.showNativeReasoning, isFalse);
  });
}
