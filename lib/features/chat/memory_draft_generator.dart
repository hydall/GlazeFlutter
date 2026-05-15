import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/llm/sse_client.dart';
import '../../core/models/memory_book.dart';
import '../../core/services/memory_prompt_presets.dart';
import '../../core/state/memory_settings_provider.dart';
import '../settings/api_list_provider.dart';

class MemoryDraftGenerator {
  final WidgetRef _ref;
  final SseClient _client = SseClient();

  MemoryDraftGenerator(this._ref);

  Future<MemoryDraft> generate({
    required MemoryDraft draft,
    required MemoryBookSettings settings,
    required String historyText,
    CancelToken? cancelToken,
  }) async {
    final customPrompts = MemoryPromptPreset.fromJsonList(
      _ref.read(memoryGlobalSettingsProvider).customPrompts,
    );
    final template = MemoryPromptPresets.resolve(settings.promptPreset, customPrompts);
    var prompt = template.replaceAll('{{history}}', historyText);
    if (!template.contains('{{history}}')) {
      prompt = '$prompt\n\n$historyText';
    }

    final isCustom = settings.generationSource == 'custom';
    String endpoint;
    String apiKey;
    String model;

    if (isCustom) {
      endpoint = settings.generationEndpoint;
      apiKey = settings.generationApiKey;
      model = settings.generationModel;
    } else {
      final chatConfig = _ref.read(activeApiConfigProvider);
      if (chatConfig == null) {
        throw Exception('No chat API config available');
      }
      endpoint = chatConfig.endpoint;
      apiKey = chatConfig.apiKey;
      model = settings.generationModel.isNotEmpty
          ? settings.generationModel
          : chatConfig.model;
    }

    if (endpoint.isEmpty || model.isEmpty) {
      throw Exception('API not configured for memory generation');
    }

    final maxTokens = (settings.generationMaxTokens != null && settings.generationMaxTokens! > 0)
        ? settings.generationMaxTokens!
        : 2000;
    final temperature = settings.generationTemperature ?? 0.4;

    final completer = Completer<String>();

    await _client.streamChatCompletion(
      endpoint: endpoint,
      apiKey: apiKey,
      model: model,
      messages: [
        {'role': 'user', 'content': prompt},
      ],
      maxTokens: maxTokens,
      temperature: temperature,
      topP: 1.0,
      stream: false,
      cancelToken: cancelToken,
      onComplete: (text, _) {
        if (!completer.isCompleted) completer.complete(text);
      },
      onError: (error) {
        if (!completer.isCompleted) completer.completeError(error);
      },
    );

    final result = await completer.future;
    return _parseDraftResult(draft, result);
  }

  MemoryDraft _parseDraftResult(MemoryDraft draft, String raw) {
    String content = raw;
    List<String> keys = [];

    final memoryMatch = RegExp(r'Memory:\s*(.*?)(?=\nKeys:|$)', dotAll: true).firstMatch(raw);
    final keysMatch = RegExp(r'Keys:\s*(.*?)$', dotAll: true).firstMatch(raw);

    if (memoryMatch != null) {
      content = memoryMatch.group(1)!.trim();
    }
    if (keysMatch != null) {
      keys = keysMatch
          .group(1)!
          .split(',')
          .map((k) => k.trim().toLowerCase())
          .where((k) => k.isNotEmpty)
          .toList();
    }

    return draft.copyWith(
      content: content,
      keys: keys,
      status: 'pending_approval',
      generatedAt: DateTime.now().millisecondsSinceEpoch,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }
}
