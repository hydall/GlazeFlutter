import 'package:flutter_test/flutter_test.dart';
import 'package:glaze_flutter/core/models/api_config.dart';

void main() {
  test('last reasoning history setting is backward-compatible', () {
    final config = ApiConfig.fromJson(const {'id': 'api'});

    expect(config.includeLastReasoning, isFalse);
  });
}
