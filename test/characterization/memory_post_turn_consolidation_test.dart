import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:glaze_flutter/core/db/app_db.dart';
import 'package:glaze_flutter/core/db/repositories/memory_book_repo.dart';
import 'package:glaze_flutter/core/db/repositories/memory_consolidation_repo.dart';
import 'package:glaze_flutter/core/llm/memory_post_turn_service.dart';
import 'package:glaze_flutter/core/models/memory_book.dart';
import 'package:glaze_flutter/core/models/pipeline_settings.dart';
import 'package:glaze_flutter/core/state/db_provider.dart';
import 'package:glaze_flutter/core/state/memory_agent_providers.dart';
import 'package:glaze_flutter/core/state/memory_settings_provider.dart';

/// §1: verifies that `runPostTurn` triggers consolidation when cadence +
/// threshold are met. Previously the docstring claimed step 4 = consolidation
/// but the method body never called it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  late AppDatabase db;
  late ProviderContainer container;
  late MemoryBookRepo bookRepo;
  late MemoryConsolidationRepo consolRepo;
  late MemoryPostTurnService service;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(overrides: [appDbProvider.overrideWithValue(db)]);
    bookRepo = container.read(memoryBookRepoProvider);
    consolRepo = container.read(memoryConsolidationRepoProvider);
    service = container.read(memoryPostTurnServiceProvider);
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  /// Enables memory globally in balanced mode (fast mode short-circuits
  /// runPostTurn before consolidation). Call at the start of each test.
  Future<void> enableMemory() async {
    await container.read(memoryGlobalSettingsProvider.notifier).save(
      const MemoryGlobalSettings(enabled: true, memoryMode: 'balanced'),
    );
  }

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  group('MemoryPostTurnService §1 consolidation wiring', () {
    test(
      'consolidation triggered when enabled + threshold met + cadence allows',
      () async {
        await enableMemory();
        // Seed a memory book with 6 active entries (threshold = 5).
        final book = MemoryBook(
          id: 'mb_s1',
          sessionId: 's1',
          settings: const MemoryBookSettings(
            enabled: true,
            memoryMode: 'balanced',
            cadenceInterval: 1,
          ),
          entries: List.generate(
            6,
            (i) => MemoryEntry(
              id: 'm$i',
              content: 'entry $i content with enough text to score',
              messageRange: MessageRange(start: i, end: i + 1),
            ),
          ),
        );
        await bookRepo.put(book);

        // Override pipeline settings to enable consolidation with
        // source='custom' but empty endpoint → consolidateSession saves an
        // error row (observable side effect proving it was called).
        await container
            .read(pipelineSettingsProvider.notifier)
            .save(const PipelineSettings(
              consolidationEnabled: true,
              consolidationThreshold: 5,
              consolidationSource: 'custom',
              consolidationEndpoint: '',
              consolidationModel: '',
            ));

        await service.runPostTurn('s1');

        // Give fire-and-forget internals a tick to settle.
        await Future<void>.delayed(Duration.zero);

        final consolidations = await consolRepo.getBySessionId('s1');
        // If consolidation was wired, at least one row (error or ok) exists.
        expect(
          consolidations,
          isNotEmpty,
          reason:
              'runPostTurn should trigger consolidation when enabled + '
              'threshold met + cadence allows',
        );
      },
    );

    test('consolidation skipped when disabled', () async {
      await enableMemory();
      final book = MemoryBook(
        id: 'mb_s2',
        sessionId: 's2',
        settings: const MemoryBookSettings(
          enabled: true,
          memoryMode: 'balanced',
          cadenceInterval: 1,
        ),
        entries: List.generate(
          6,
          (i) => MemoryEntry(
            id: 'm2_$i',
            content: 'entry $i content with enough text to score',
            messageRange: MessageRange(start: i, end: i + 1),
          ),
        ),
      );
      await bookRepo.put(book);

      await container.read(pipelineSettingsProvider.notifier).save(
        const PipelineSettings(consolidationEnabled: false),
      );

      await service.runPostTurn('s2');
      await Future<void>.delayed(Duration.zero);

      final consolidations = await consolRepo.getBySessionId('s2');
      expect(consolidations, isEmpty);
    });
  });
}
