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
            classifierEnabled: true,
            classifierSource: 'custom',
            classifierModel: 'classifier-mini',
            classifierEndpoint: 'https://classifier.example/v1',
            classifierApiKey: 'classifier-key',
            classifierTimeoutMs: 3500,
            sidecarEnabled: true,
            sidecarSource: 'custom',
            sidecarModel: 'sidecar-mini',
            sidecarEndpoint: 'https://sidecar.example/v1',
            sidecarApiKey: 'sidecar-key',
            sidecarTimeoutMs: 4500,
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
    expect(json['classifierEnabled'], true);
    expect(json['classifierSource'], 'custom');
    expect(json['classifierModel'], 'classifier-mini');
    expect(json['classifierEndpoint'], 'https://classifier.example/v1');
    expect(json['classifierApiKey'], 'classifier-key');
    expect(json['classifierTimeoutMs'], 3500);
    expect(json['sidecarEnabled'], true);
    expect(json['sidecarSource'], 'custom');
    expect(json['sidecarModel'], 'sidecar-mini');
    expect(json['sidecarEndpoint'], 'https://sidecar.example/v1');
    expect(json['sidecarApiKey'], 'sidecar-key');
    expect(json['sidecarTimeoutMs'], 4500);
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
            classifierEnabled: true,
            classifierModel: 'classifier-mini',
            classifierTimeoutMs: 3500,
            sidecarEnabled: true,
            sidecarModel: 'sidecar-mini',
            sidecarTimeoutMs: 4500,
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
    expect(book.settings.classifierEnabled, true);
    expect(book.settings.classifierModel, 'classifier-mini');
    expect(book.settings.classifierTimeoutMs, 3500);
    expect(book.settings.sidecarEnabled, true);
    expect(book.settings.sidecarModel, 'sidecar-mini');
    expect(book.settings.sidecarTimeoutMs, 4500);
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
        classifierEnabled: true,
        classifierSource: 'current',
        classifierModel: 'classifier-mini',
        classifierTimeoutMs: 3000,
        sidecarEnabled: true,
        sidecarSource: 'current',
        sidecarModel: 'sidecar-mini',
        sidecarTimeoutMs: 5000,
        queryIncludeAssistant: false,
        queryRecentTurns: 5,
        queryMaxChars: 1250,
      ),
    );

    final updated = await repo.getBySessionId('session_update');
    expect(updated!.settings.diversityAware, false);
    expect(updated.settings.memoryMode, 'balanced');
    expect(updated.settings.factualContinuityGuardEnabled, true);
    expect(updated.settings.classifierEnabled, true);
    expect(updated.settings.classifierSource, 'current');
    expect(updated.settings.classifierModel, 'classifier-mini');
    expect(updated.settings.classifierTimeoutMs, 3000);
    expect(updated.settings.sidecarEnabled, true);
    expect(updated.settings.sidecarSource, 'current');
    expect(updated.settings.sidecarModel, 'sidecar-mini');
    expect(updated.settings.sidecarTimeoutMs, 5000);
    expect(updated.settings.queryIncludeAssistant, false);
    expect(updated.settings.queryRecentTurns, 5);
    expect(updated.settings.queryMaxChars, 1250);
  });

  test('legacy memory entries recover messageRange from range title', () {
    final entry = MemoryEntry.fromJson({
      'id': 'mem_legacy',
      'title': '91-105',
      'content': 'remembered events',
      'keys': <String>[],
      'messageIds': <String>['m1'],
      'status': 'active',
    });

    expect(entry.messageRange, const MessageRange(start: 91, end: 105));
  });
}
