import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glaze_flutter/core/db/app_db.dart';
import 'package:glaze_flutter/core/models/memory_book.dart';
import 'package:glaze_flutter/core/state/db_provider.dart';
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
              memoryMode: 'balanced',
            ),
          );

      final prefs = await SharedPreferences.getInstance();
      final json =
          jsonDecode(prefs.getString('memorySettings')!)
              as Map<String, dynamic>;

      expect(json['maxInjectedTokens'], 6000);
      expect(json['memoryBudgetPreset'], 'medium');
      expect(json['memoryMode'], 'balanced');
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
      expect(settings.memoryMode, 'fast');
    },
  );

  test('memory global settings persists advanced selector tuning', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container
        .read(memoryGlobalSettingsProvider.notifier)
        .save(
          const MemoryGlobalSettings(
            diversityAware: false,
            diversityPenalty: 0.3,
            recencyBoost: false,
            recencyHalfLifeDays: 2,
            importanceBoost: false,
            importanceWeight: 1.25,
            sourceWindowExclusion: false,
            factualContinuityGuardEnabled: true,
            queryIncludeAssistant: false,
            queryRecentTurns: 4,
            queryMaxChars: 750,
          ),
        );

    final prefs = await SharedPreferences.getInstance();
    final json =
        jsonDecode(prefs.getString('memorySettings')!) as Map<String, dynamic>;

    expect(json['diversityAware'], false);
    expect(json['diversityPenalty'], 0.3);
    expect(json['recencyBoost'], false);
    expect(json['recencyHalfLifeDays'], 2);
    expect(json['importanceBoost'], false);
    expect(json['importanceWeight'], 1.25);
    expect(json['sourceWindowExclusion'], false);
    expect(json['factualContinuityGuardEnabled'], true);
    expect(json['queryIncludeAssistant'], false);
    expect(json['queryRecentTurns'], 4);
    expect(json['queryMaxChars'], 750);
  });

  test('new memory books inherit advanced selector tuning', () async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final container = ProviderContainer(
      overrides: [appDbProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);
    addTearDown(db.close);

    await container
        .read(memoryGlobalSettingsProvider.notifier)
        .save(
          const MemoryGlobalSettings(
            diversityAware: false,
            memoryMode: 'balanced',
            recencyBoost: false,
            importanceWeight: 1.5,
            sourceWindowExclusion: false,
            factualContinuityGuardEnabled: true,
            queryIncludeAssistant: false,
            queryRecentTurns: 3,
            queryMaxChars: 900,
          ),
        );

    final repo = container.read(memoryBookRepoProvider);
    final book = await repo.ensureForSession('session_advanced');

    expect(book.settings.diversityAware, false);
    expect(book.settings.memoryMode, 'balanced');
    expect(book.settings.recencyBoost, false);
    expect(book.settings.importanceWeight, 1.5);
    expect(book.settings.sourceWindowExclusion, false);
    expect(book.settings.factualContinuityGuardEnabled, true);
    expect(book.settings.queryIncludeAssistant, false);
    expect(book.settings.queryRecentTurns, 3);
    expect(book.settings.queryMaxChars, 900);
  });

  test('memory book settings update persists selector inputs', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final container = ProviderContainer(
      overrides: [appDbProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);
    addTearDown(db.close);

    final repo = container.read(memoryBookRepoProvider);
    await repo.put(const MemoryBook(id: 'mb1', sessionId: 'session_update'));
    await repo.updateSettings(
      'session_update',
      const MemoryBookSettings(
        memoryMode: 'balanced',
        diversityAware: false,
        factualContinuityGuardEnabled: true,
        queryIncludeAssistant: false,
        queryRecentTurns: 5,
        queryMaxChars: 1250,
      ),
    );

    final updated = await repo.getBySessionId('session_update');
    expect(updated!.settings.diversityAware, false);
    expect(updated.settings.memoryMode, 'balanced');
    expect(updated.settings.factualContinuityGuardEnabled, true);
    expect(updated.settings.queryIncludeAssistant, false);
    expect(updated.settings.queryRecentTurns, 5);
    expect(updated.settings.queryMaxChars, 1250);
  });
}
