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
import '../../../core/utils/id_generator.dart';
import '../../settings/api_list_provider.dart';
import '../models/block_config.dart';
import '../models/extension_preset.dart';
import '../models/info_block.dart';

final infoBlockServiceProvider = Provider<InfoBlockService>(
  (ref) => InfoBlockService(ref),
);

class InfoBlockService {
  InfoBlockService(this._ref);

  final Ref _ref;

  InfoBlocksRepository get _repo =>
      InfoBlocksRepository(_ref.read(appDbProvider));

  /// Generates infoblocks after assistant response
  Future<List<InfoBlock>> generateBlocks({
    required String sessionId,
    required String messageId,
    required List<ChatMessage> messages,
    required ExtensionPreset preset,
    required Character character,
    required String? persona,
    CancelToken? cancelToken,
  }) async {
    final results = <InfoBlock>[];

    final infoBlocks = preset.blocks.where(
      (b) => b.enabled && b.type == BlockType.infoblock,
    );

    for (final blockConfig in infoBlocks) {
      if (cancelToken?.isCancelled == true) break;

      try {
        final block = await _generateSingleBlock(
          sessionId: sessionId,
          messageId: messageId,
          messages: messages,
          blockConfig: blockConfig,
          preset: preset,
          character: character,
          persona: persona,
          cancelToken: cancelToken,
        );

        if (block != null) {
          await _repo.insert(block);
          results.add(block);
        }
      } catch (e) {
        debugPrint('[InfoBlockService] Error generating block ${blockConfig.name}: $e');
      }
    }

    return results;
  }

  Future<InfoBlock?> _generateSingleBlock({
    required String sessionId,
    required String messageId,
    required List<ChatMessage> messages,
    required BlockConfig blockConfig,
    required ExtensionPreset preset,
    required Character? character,
    required String? persona,
    CancelToken? cancelToken,
  }) async {
    // Build context from recent messages
    final contextMessages = _buildContextMessages(
      messages,
      blockConfig.contextMessageCount,
    );

    // Get recent blocks of same type
    final recentBlocks = await _repo.getRecentBlocks(
      sessionId,
      blockConfig.name,
      blockConfig.contextBlockCount,
    );

    // Build prompt for infoblock generation
    final prompt = _buildInfoblockPrompt(
      blockConfig: blockConfig,
      character: character,
      persona: persona,
      contextMessages: contextMessages,
      recentBlocks: recentBlocks,
    );

    // Get API config
    final apiConfigId = blockConfig.apiConfigId;
    if (apiConfigId.isEmpty) {
      debugPrint('[InfoBlockService] No API config specified for block ${blockConfig.name}');
      return null;
    }

    final apiConfigs = await _ref.read(apiListProvider.future);
    final apiConfig = apiConfigs.where((c) => c.id == apiConfigId).firstOrNull;
    if (apiConfig == null) {
      debugPrint('[InfoBlockService] API config not found: $apiConfigId');
      return null;
    }

    // Call LLM to generate infoblock content
    final content = await _callLLMForInfoblock(
      apiConfig: apiConfig,
      blockConfig: blockConfig,
      prompt: prompt,
      cancelToken: cancelToken,
    );

    if (content == null || content.isEmpty) {
      debugPrint('[InfoBlockService] Empty content generated for block ${blockConfig.name}');
      return null;
    }

    return InfoBlock(
      id: generateId(),
      sessionId: sessionId,
      messageId: messageId,
      blockId: blockConfig.id,
      blockName: blockConfig.name,
      blockType: 'infoblock',
      content: content,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  List<ChatMessage> _buildContextMessages(
    List<ChatMessage> messages,
    int count,
  ) {
    if (messages.isEmpty) return [];

    final startIdx = (messages.length - count).clamp(0, messages.length);
    return messages.sublist(startIdx);
  }

  String _buildInfoblockPrompt({
    required BlockConfig blockConfig,
    required Character? character,
    required String? persona,
    required List<ChatMessage> contextMessages,
    required List<InfoBlock> recentBlocks,
  }) {
    final buffer = StringBuffer();

    // Block-specific instructions
    if (blockConfig.prompt.isNotEmpty) {
      buffer.writeln('Instructions:');
      buffer.writeln(blockConfig.prompt);
      buffer.writeln();
    }

    // Character info
    if (character != null) {
      buffer.writeln('Character: ${character.name}');
      if (character.description != null && character.description!.isNotEmpty) {
        buffer.writeln('Description: ${character.description}');
      }
      buffer.writeln();
    }

    // Persona info
    if (persona != null && persona.isNotEmpty) {
      buffer.writeln('User Persona: $persona');
      buffer.writeln();
    }

    // Recent context
    if (contextMessages.isNotEmpty) {
      buffer.writeln('Recent conversation:');
      for (final msg in contextMessages) {
        final role = msg.role == 'user' ? 'USER' : 'ASSISTANT';
        buffer.writeln('$role: ${msg.content}');
      }
      buffer.writeln();
    }

    // Recent blocks of same type
    if (recentBlocks.isNotEmpty) {
      buffer.writeln('Previous <${blockConfig.name}> blocks:');
      buffer.writeln('<${blockConfig.name}>');
      for (final block in recentBlocks) {
        buffer.writeln(block.content);
      }
      buffer.writeln('</${blockConfig.name}>');
      buffer.writeln();
    }

    // Output format
    buffer.writeln('Output the infoblock in the following format:');
    buffer.writeln('<${blockConfig.name}>');
    buffer.writeln('... block content ...');
    buffer.writeln('</${blockConfig.name}>');

    return buffer.toString();
  }

  Future<String?> _callLLMForInfoblock({
    required ApiConfig apiConfig,
    required BlockConfig blockConfig,
    required String prompt,
    CancelToken? cancelToken,
  }) async {
    const systemPrompt = 'You are an AI assistant that generates structured infoblocks describing current scene state.';

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
        model: blockConfig.model.isNotEmpty
            ? blockConfig.model
            : apiConfig.model,
        messages: messages,
        maxTokens: apiConfig.maxTokens,
        temperature: apiConfig.temperature,
        topP: apiConfig.topP,
        stream: false,
        cancelToken: cancelToken,
        onComplete: (text, reasoning, {rawResponseJson}) {
          if (!completer.isCompleted) {
            completer.complete(text);
          }
        },
        onError: (error) {
          if (!completer.isCompleted) {
            completer.completeError(error);
          }
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
