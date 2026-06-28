import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:glaze_flutter/core/db/app_db.dart';
import 'package:glaze_flutter/core/db/repositories/memory_consolidation_repo.dart';
import 'package:glaze_flutter/core/llm/memory_consolidation_service.dart';
import 'package:glaze_flutter/core/state/db_provider.dart';
import 'package:glaze_flutter/core/state/memory_agent_providers.dart';
import 'package:glaze_flutter/core/models/memory_book.dart';
import 'package:glaze_flutter/core/models/memory_graph.dart';
import 'package:glaze_flutter/core/models/pipeline_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  late AppDatabase db;
  late MemoryConsolidationRepo repo;
  late ProviderContainer container;
  late MemoryConsolidationService service;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = MemoryConsolidationRepo(db);
    container = ProviderContainer(overrides: [
      appDbProvider.overrideWithValue(db),
    ]);
    service = container.read(memoryConsolidationServiceProvider);
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  group('MemoryConsolidationService (Phase G5)', () {
    test('disabled when consolidationEnabled is false', () async {
      final entries = [
        MemoryEntry(id: 'm1', content: 'x ' * 20),
        MemoryEntry(id: 'm2', content: 'y ' * 20),
      ];
      final result = await service.consolidateSession(
        's1',
        entries,
        settings: const PipelineSettings(consolidationEnabled: false),
      );
      expect(result, 0);
    });

    test('skips when below threshold', () async {
      final entries = [
        MemoryEntry(id: 'm1', content: 'x ' * 20),
        MemoryEntry(id: 'm2', content: 'y ' * 20),
      ];
      final result = await service.consolidateSession(
        's1',
        entries,
        settings: const PipelineSettings(
          consolidationEnabled: true,
          consolidationThreshold: 5,
        ),
      );
      expect(result, 0);
    });

    test('error status saved when API not configured', () async {
      final entries = List.generate(
        6,
        (i) => MemoryEntry(
          id: 'm$i',
          content: 'entry $i content here',
          messageRange: MessageRange(start: i, end: i + 1),
        ),
      );
      await service.consolidateSession(
        's1',
        entries,
        settings: const PipelineSettings(
          consolidationEnabled: true,
          consolidationThreshold: 5,
          consolidationSource: 'custom',
          consolidationEndpoint: '',
          consolidationModel: '',
        ),
      );
      final consolidations = await repo.getBySessionId('s1');
      expect(consolidations, isNotEmpty);
      expect(consolidations.first.status, 'error');
      expect(consolidations.first.errorMessage, isNotEmpty);
    });

    test(
      'error status saved when source=current but no active API config',
      () async {
        // §2: source='current' now resolves via activeApiConfigProvider.
        // With no API configs in the container, it throws "No chat API config
        // available", which the service catches and saves as an error status.
        final entries = List.generate(
          6,
          (i) => MemoryEntry(
            id: 'm$i',
            content: 'entry $i content here',
            messageRange: MessageRange(start: i, end: i + 1),
          ),
        );
        await service.consolidateSession(
          's1',
          entries,
          settings: const PipelineSettings(
            consolidationEnabled: true,
            consolidationThreshold: 5,
            consolidationSource: 'current',
          ),
        );
        final consolidations = await repo.getBySessionId('s1');
        expect(consolidations, isNotEmpty);
        expect(consolidations.first.status, 'error');
        expect(consolidations.first.errorMessage, contains('No chat API config'));
      },
    );

    test('can retry failed consolidation', () async {
      final entry = MemoryConsolidation(
        id: 'failed1',
        chatSessionId: 's1',
        tier: 1,
        title: 'Failed',
        summary: '',
        status: 'error',
        errorMessage: 'timeout',
      );
      await repo.upsert(entry);
      final status = await repo.getBySessionId('s1');
      expect(status.first.status, 'error');

      await repo.updateStatus('failed1', 'ok', null);
      final updated = await repo.getBySessionId('s1');
      expect(updated.first.status, 'ok');
      expect(updated.first.errorMessage, '');
    });
  });
}
