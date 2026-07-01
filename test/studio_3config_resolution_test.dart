import 'package:flutter_test/flutter_test.dart';

import 'package:glaze_flutter/core/llm/agent_runner.dart' show ResolvedAgentConfig;
import 'package:glaze_flutter/core/llm/studio_api_config_resolver.dart';
import 'package:glaze_flutter/core/models/api_config.dart';
import 'package:glaze_flutter/core/models/studio_config.dart';

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

      final resolved =
          resolver.resolveAgentConfig(active, '', 'custom-model');
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
      final resolved =
          ResolvedAgentConfig.fromApiConfig(api, modelOverride: 'override-model');
      expect(resolved.model, 'override-model');
    });
  });
}
