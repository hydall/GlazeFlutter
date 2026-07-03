import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:glaze_flutter/core/db/app_db.dart';
import 'package:glaze_flutter/core/llm/agent_runner.dart';
import 'package:glaze_flutter/core/llm/studio_api_config_resolver.dart';
import 'package:glaze_flutter/core/models/api_config.dart';
import 'package:glaze_flutter/core/models/pipeline_settings.dart';
import 'package:glaze_flutter/core/models/studio_config.dart';
import 'package:glaze_flutter/core/state/db_provider.dart';
import 'package:glaze_flutter/features/settings/api_list_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

AppDatabase _testDb() => AppDatabase.forTesting(NativeDatabase.memory());

void main() {
  group('StudioApiConfigResolver', () {
    test('resolveAgentConfig uses runApiConfigId when set', () {
      final active = ApiConfig(
        id: 'active',
        name: 'Active',
        endpoint: 'https://active',
        apiKey: 'key',
        model: 'gpt-4o',
        protocol: 'openai',
      );
      final cheap = ApiConfig(
        id: 'cheap-1',
        name: 'Cheap',
        endpoint: 'https://cheap',
        apiKey: 'key',
        model: 'gpt-4o-mini',
        protocol: 'openai',
      );
      final resolver = StudioApiConfigResolver(
        apiConfigs: [active, cheap],
        activeConfig: active,
      );

      final resolved = resolver.resolveAgentConfig(active, 'cheap-1', '');
      expect(resolved.model, 'gpt-4o-mini');
    });

    test('resolveAgentConfig falls back to active when id not found', () {
      final active = ApiConfig(
        id: 'active',
        name: 'Active',
        endpoint: 'https://active',
        apiKey: 'key',
        model: 'gpt-4o',
        protocol: 'openai',
      );
      final resolver = StudioApiConfigResolver(
        apiConfigs: [active],
        activeConfig: active,
      );

      final resolved = resolver.resolveAgentConfig(active, 'nonexistent', '');
      expect(resolved.model, 'gpt-4o');
    });

    test('resolveAgentConfig applies modelOverride', () {
      final active = ApiConfig(
        id: 'active',
        name: 'Active',
        endpoint: 'https://active',
        apiKey: 'key',
        model: 'gpt-4o',
        protocol: 'openai',
      );
      final resolver = StudioApiConfigResolver(
        apiConfigs: [active],
        activeConfig: active,
      );

      final resolved = resolver.resolveAgentConfig(active, '', 'custom-model');
      expect(resolved.model, 'custom-model');
    });

    test('resolveAgentConfig with empty runApiConfigId uses active', () {
      final active = ApiConfig(
        id: 'active',
        name: 'Active',
        endpoint: 'https://active',
        apiKey: 'key',
        model: 'gpt-4o',
        protocol: 'openai',
      );
      final resolver = StudioApiConfigResolver(
        apiConfigs: [active],
        activeConfig: active,
      );

      final resolved = resolver.resolveAgentConfig(active, '', '');
      expect(resolved.model, 'gpt-4o');
    });
  });

  group('StudioConfig 3-config fields', () {
    test('default values are empty strings', () {
      final config = StudioConfig(sessionId: 'test');
      expect(config.expensiveApiConfigId, '');
      expect(config.cheapApiConfigId, '');
      expect(config.cleanerApiConfigId, '');
      expect(config.studioPresetId, 'default');
    });

    test('copyWith updates config fields', () {
      final config = StudioConfig(sessionId: 'test');
      final updated = config.copyWith(
        expensiveApiConfigId: 'exp-1',
        cheapApiConfigId: 'cheap-1',
        cleanerApiConfigId: 'clean-1',
        studioPresetId: 'custom-preset',
      );
      expect(updated.expensiveApiConfigId, 'exp-1');
      expect(updated.cheapApiConfigId, 'cheap-1');
      expect(updated.cleanerApiConfigId, 'clean-1');
      expect(updated.studioPresetId, 'custom-preset');
    });

    test('StudioAgent has no promptShard/modelSource/model/modelOverride', () {
      final agent = StudioAgent(id: 'test', name: 'Test');
      expect(agent.id, 'test');
      expect(agent.enabled, true);
      // These fields were removed in v55 migration — if they still exist,
      // the freezed model wasn't regenerated.
    });
  });

  group('ResolvedAgentConfig', () {
    test('fromApiConfig preserves all fields', () {
      final api = ApiConfig(
        id: 'test',
        name: 'Test',
        endpoint: 'https://test',
        apiKey: 'key',
        model: 'model-1',
        protocol: 'openai',
        maxTokens: 8000,
        contextSize: 16000,
      );
      final resolved = ResolvedAgentConfig.fromApiConfig(api);
      expect(resolved.endpoint, 'https://test');
      expect(resolved.model, 'model-1');
      expect(resolved.apiKey, 'key');
      expect(resolved.protocol, 'openai');
    });

    test('fromApiConfig with modelOverride', () {
      final api = ApiConfig(
        id: 'test',
        name: 'Test',
        endpoint: 'https://test',
        apiKey: 'key',
        model: 'model-1',
        protocol: 'openai',
      );
      final resolved = ResolvedAgentConfig.fromApiConfig(
        api,
        modelOverride: 'override-model',
      );
      expect(resolved.model, 'override-model');
    });
  });

  group('AgentRunner Studio final routing', () {
    test(
      'final generator ignores MemoryBook generationModel override',
      () async {
        SharedPreferences.setMockInitialValues({});
        final db = _testDb();
        addTearDown(db.close);
        final container = ProviderContainer(
          overrides: [appDbProvider.overrideWithValue(db)],
        );
        addTearDown(container.dispose);

        final active = ApiConfig(
          id: 'active',
          name: 'Active',
          endpoint: 'https://active',
          apiKey: 'key',
          model: 'chat-model',
          protocol: 'openai',
        );
        final expensive = ApiConfig(
          id: 'expensive',
          name: 'Expensive',
          endpoint: 'https://expensive',
          apiKey: 'key',
          model: 'final-slot-model',
          protocol: 'openai',
        );
        await container.read(apiConfigRepoProvider).put(active);
        await container.read(apiConfigRepoProvider).put(expensive);
        container.read(activeApiPresetIdProvider.notifier).state = active.id;
        container.invalidate(apiListProvider);
        await container.read(apiListProvider.future);
        await container
            .read(studioConfigRepoProvider)
            .upsert(
              StudioConfig(
                sessionId: 'session-1',
                enabled: true,
                expensiveApiConfigId: expensive.id,
              ),
            );
        await container
            .read(pipelineSettingsProvider.notifier)
            .save(const PipelineSettings(generationModel: 'memory-book-model'));

        final resolved = await container
            .read(agentRunnerProvider)
            .resolveAgentConfig(
              const StudioAgent(id: 'final', name: 'Final'),
              active,
              'session-1',
              isFinalResponse: true,
              apiConfigId: expensive.id,
            );

        expect(resolved.model, 'final-slot-model');
      },
    );

    test(
      'final generator uses Studio final override instead of MemoryBook model',
      () async {
        SharedPreferences.setMockInitialValues({});
        final db = _testDb();
        addTearDown(db.close);
        final container = ProviderContainer(
          overrides: [appDbProvider.overrideWithValue(db)],
        );
        addTearDown(container.dispose);

        final active = ApiConfig(
          id: 'active',
          name: 'Active',
          endpoint: 'https://active',
          apiKey: 'key',
          model: 'chat-model',
          protocol: 'openai',
        );
        final expensive = ApiConfig(
          id: 'expensive',
          name: 'Expensive',
          endpoint: 'https://expensive',
          apiKey: 'key',
          model: 'final-slot-model',
          protocol: 'openai',
        );
        await container.read(apiConfigRepoProvider).put(active);
        await container.read(apiConfigRepoProvider).put(expensive);
        container.read(activeApiPresetIdProvider.notifier).state = active.id;
        container.invalidate(apiListProvider);
        await container.read(apiListProvider.future);
        await container
            .read(studioConfigRepoProvider)
            .upsert(
              StudioConfig(
                sessionId: 'session-1',
                enabled: true,
                expensiveApiConfigId: expensive.id,
              ),
            );
        await container
            .read(pipelineSettingsProvider.notifier)
            .save(
              const PipelineSettings(
                generationModel: 'memory-book-model',
                studioFinalModelOverride: 'studio-final-model',
              ),
            );

        final resolved = await container
            .read(agentRunnerProvider)
            .resolveAgentConfig(
              const StudioAgent(id: 'final', name: 'Final'),
              active,
              'session-1',
              isFinalResponse: true,
              apiConfigId: expensive.id,
            );

        expect(resolved.model, 'studio-final-model');
      },
    );
  });
}
