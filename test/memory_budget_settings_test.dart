import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glaze_flutter/core/state/memory_settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'memory global settings persists maxInjectedTokens and preset',
    () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container
          .read(memoryGlobalSettingsProvider.notifier)
          .save(
            const MemoryGlobalSettings(
              maxInjectedTokens: 6000,
              memoryBudgetPreset: 'medium',
            ),
          );

      final prefs = await SharedPreferences.getInstance();
      final json =
          jsonDecode(prefs.getString('memorySettings')!)
              as Map<String, dynamic>;

      expect(json['maxInjectedTokens'], 6000);
      expect(json['memoryBudgetPreset'], 'medium');
    },
  );

  test(
    'memory global settings loads legacy percent-only data as auto',
    () async {
      SharedPreferences.setMockInitialValues({
        'memorySettings': jsonEncode({
          'maxInjectedEntries': 7,
          'injectionTarget': 'hard_block',
        }),
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(memoryGlobalSettingsProvider.notifier).load();

      final settings = container.read(memoryGlobalSettingsProvider);
      expect(settings.maxInjectedTokens, isNull);
      expect(settings.memoryBudgetPreset, 'auto');
    },
  );
}
