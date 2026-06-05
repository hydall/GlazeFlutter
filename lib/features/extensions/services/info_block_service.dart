import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/repositories/info_blocks_repository.dart';
import '../../../core/llm/sse_client.dart';
import '../../../core/models/api_config.dart';
import '../../../core/models/chat_message.dart';
import '../../../core/models/character.dart';
import '../../../core/state/db_provider.dart';
import '../../settings/api_list_provider.dart';
import '../models/block_config.dart';
import '../models/info_block.dart';

final infoBlockServiceProvider = Provider<InfoBlockService>(
  (ref) => InfoBlockService(ref),
);

class InfoBlockService {
  InfoBlockService(this._ref);

  final Ref _ref;

  InfoBlocksRepository get _repo =>
      InfoBlocksRepository(_ref.read(appDbProvider));

  /// Generates the text content for a single infoblock block.
  /// Returns null if generation failed or was cancelled.
  /// [previousOutput] is the content produced by the preceding block in the
  /// chain (used as additional context when non-null).
  Future<String?> generateSingleBlockContent({
    required String sessionId,
    required String messageId,
    required List<ChatMessage> messages,
    required BlockConfig blockConfig,
    required Character? character,
    required String? persona,
    required String? previousOutput,
    CancelToken? cancelToken,
  }) async {
    if (cancelToken?.isCancelled == true) return null;

    // Build context from recent messages (fixed window of last 10).
    final contextMessages = _buildContextMessages(messages, 10);

    // Build injected history: last `injectLastN` assistant messages that
    // already have a block result for this block name.
    final injectedHistory = await _buildInjectedHistory(
      sessionId: sessionId,
      messages: messages,
      blockConfig: blockConfig,
    );

    // Build prompt.
    final prompt = _buildInfoblockPrompt(
      blockConfig: blockConfig,
      character: character,
      persona: persona,
      contextMessages: contextMessages,
      previousBlockHistory: injectedHistory,
      previousOutput: previousOutput,
    );

    // Resolve API config.
    final apiConfigId = blockConfig.apiConfigId;
    if (apiConfigId.isEmpty) {
      debugPrint('[InfoBlockService] No API config for block "${blockConfig.name}"');
      return null;
    }

    final apiConfigs = await _ref.read(apiListProvider.future);
    final apiConfig = apiConfigs.where((c) => c.id == apiConfigId).firstOrNull;
    if (apiConfig == null) {
      debugPrint('[InfoBlockService] API config not found: $apiConfigId');
      return null;
    }

    if (cancelToken?.isCancelled == true) return null;

    return _callLLM(
      apiConfig: apiConfig,
      blockConfig: blockConfig,
      prompt: prompt,
      cancelToken: cancelToken,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Context helpers
  // ─────────────────────────────────────────────────────────────────────────

  List<ChatMessage> _buildContextMessages(List<ChatMessage> messages, int count) {
    if (messages.isEmpty) return [];
    final startIdx = (messages.length - count).clamp(0, messages.length);
    return messages.sublist(startIdx);
  }

  /// Collects past results of this block from the last [injectLastN] assistant
  /// messages — used to give the model memory of its previous outputs.
  Future<List<InfoBlock>> _buildInjectedHistory({
    required String sessionId,
    required List<ChatMessage> messages,
    required BlockConfig blockConfig,
  }) async {
    if (blockConfig.injectLastN <= 0 || !blockConfig.inject) return [];

    final assistantMessages = messages
        .where((m) => m.role == 'assistant')
        .toList();

    final lastN = assistantMessages.length > blockConfig.injectLastN
        ? assistantMessages.sublist(
            assistantMessages.length - blockConfig.injectLastN)
        : assistantMessages;

    final results = <InfoBlock>[];
    for (final msg in lastN) {
      final blocks = await _repo.getByMessageId(sessionId, msg.id);
      results.addAll(blocks.where((b) => b.blockName == blockConfig.name));
    }
    return results;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Prompt building
  // ─────────────────────────────────────────────────────────────────────────

  String _buildInfoblockPrompt({
    required BlockConfig blockConfig,
    required Character? character,
    required String? persona,
    required List<ChatMessage> contextMessages,
    required List<InfoBlock> previousBlockHistory,
    required String? previousOutput,
  }) {
    final buffer = StringBuffer();

    if (blockConfig.prompt.isNotEmpty) {
      buffer.writeln('Instructions:');
      buffer.writeln(blockConfig.prompt);
      buffer.writeln();
    }

    if (character != null) {
      buffer.writeln('Character: ${character.name}');
      if (character.description != null && character.description!.isNotEmpty) {
        buffer.writeln('Description: ${character.description}');
      }
      buffer.writeln();
    }

    if (persona != null && persona.isNotEmpty) {
      buffer.writeln('User Persona: $persona');
      buffer.writeln();
    }

    if (contextMessages.isNotEmpty) {
      buffer.writeln('Recent conversation:');
      for (final msg in contextMessages) {
        final role = msg.role == 'user' ? 'USER' : 'ASSISTANT';
        buffer.writeln('$role: ${msg.content}');
      }
      buffer.writeln();
    }

    if (previousBlockHistory.isNotEmpty) {
      buffer.writeln('Previous <${blockConfig.name}> outputs (for continuity):');
      for (final block in previousBlockHistory) {
        buffer.writeln('<${blockConfig.name}>');
        buffer.writeln(block.content);
        buffer.writeln('</${blockConfig.name}>');
      }
      buffer.writeln();
    }

    if (previousOutput != null && previousOutput.isNotEmpty) {
      buffer.writeln('Output from previous block in chain:');
      buffer.writeln(previousOutput);
      buffer.writeln();
    }

    buffer.writeln('Output the infoblock in the following format:');
    buffer.writeln('<${blockConfig.name}>');
    buffer.writeln('... block content ...');
    buffer.writeln('</${blockConfig.name}>');

    return buffer.toString();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // LLM call
  // ─────────────────────────────────────────────────────────────────────────

  Future<String?> _callLLM({
    required ApiConfig apiConfig,
    required BlockConfig blockConfig,
    required String prompt,
    CancelToken? cancelToken,
  }) async {
    const systemPrompt =
        'You are an AI assistant that generates structured infoblocks describing current scene state.';

    final messages = [
      {'role': 'system', 'content': systemPrompt},
      {'role': 'user', 'content': prompt},
    ];

    try {
      final sseClient = SseClient();
      final completer = Completer<String>();

      await sseClient.streamChatCompletion(
        endpoint: apiConfig.endpoint,
        apiKey: apiConfig.apiKey,
        model: blockConfig.model.isNotEmpty ? blockConfig.model : apiConfig.model,
        messages: messages,
        maxTokens: apiConfig.maxTokens,
        temperature: apiConfig.temperature,
        topP: apiConfig.topP,
        stream: false,
        cancelToken: cancelToken,
        onComplete: (text, reasoning, {rawResponseJson}) {
          if (!completer.isCompleted) completer.complete(text);
        },
        onError: (error) {
          if (!completer.isCompleted) completer.completeError(error);
        },
      );

      return await completer.future;
    } catch (e) {
      if (cancelToken?.isCancelled == true) return null;
      debugPrint('[InfoBlockService] LLM call failed: $e');
      return null;
    }
  }
}
