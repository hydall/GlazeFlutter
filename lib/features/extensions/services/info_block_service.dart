import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/llm/sse_client.dart';
import '../../../core/models/api_config.dart';
import '../../../core/models/chat_message.dart';
import '../../../core/models/character.dart';
import '../../settings/api_list_provider.dart';
import '../models/block_config.dart';
import 'block_content_extractor.dart';
import 'ext_blocks_prompt_injection.dart';
import 'block_context_builder.dart';
import 'macro_expander.dart';

final infoBlockServiceProvider = Provider<InfoBlockService>(
  (ref) => InfoBlockService(ref),
);

class InfoBlockService {
  InfoBlockService(this._ref);

  final Ref _ref;

  /// Generates the text content for a single infoblock block.
  /// Returns `(content, error)` — on success `error` is null; on failure
  /// `content` is null and `error` describes what went wrong.
  Future<({String? content, String? error})> generateSingleBlockContent({
    required String sessionId,
    required String messageId,
    required List<ChatMessage> messages,
    required BlockConfig blockConfig,
    required Character? character,
    required String? persona,
    required String? previousOutput,
    CancelToken? cancelToken,
    void Function(String partial)? onStreamUpdate,
  }) async {
    if (cancelToken?.isCancelled == true) return (content: null, error: null);

    final messagesWithInject = await _ref
        .read(extBlocksPromptInjectionProvider)
        .injectIntoHistory(sessionId: sessionId, messages: messages);

    // Context is scoped to [messageId] — not the end of the session.
    final contextMessages = buildContextMessages(
      messages: messagesWithInject,
      anchorMessageId: messageId,
      count: blockConfig.contextMessageCount,
    );

    // Image / JS blocks run an LLM agent first; no XML template extract.
    final isRawAgent = blockConfig.type == BlockType.imageGen ||
        blockConfig.type == BlockType.jsRunner;
    final resolvedTemplate =
        isRawAgent ? '' : _resolveTemplate(blockConfig);
    final systemContent = _buildSystemMessage(
      blockConfig: blockConfig,
      template: resolvedTemplate,
      character: character,
      persona: persona,
    );
    final userContent = _buildUserMessage(
      blockConfig: blockConfig,
      character: character,
      persona: persona,
      contextMessages: contextMessages,
      previousOutput: previousOutput,
    );

    // Resolve API config.
    final apiConfigId = blockConfig.apiConfigId;
    if (apiConfigId.isEmpty) {
      debugPrint('[InfoBlockService] No API config for block "${blockConfig.name}"');
      return (content: null, error: 'API config not set for block "${blockConfig.name}"');
    }

    final apiConfigs = await _ref.read(apiListProvider.future);
    final apiConfig = apiConfigs.where((c) => c.id == apiConfigId).firstOrNull;
    if (apiConfig == null) {
      debugPrint('[InfoBlockService] API config not found: $apiConfigId');
      return (content: null, error: 'API config not found: $apiConfigId');
    }

    if (cancelToken?.isCancelled == true) return (content: null, error: null);

    String? rawResponse;
    try {
      rawResponse = await _callLLM(
        apiConfig: apiConfig,
        blockConfig: blockConfig,
        systemContent: systemContent,
        userContent: userContent,
        cancelToken: cancelToken,
        onStreamUpdate: onStreamUpdate,
      );
    } catch (e) {
      if (cancelToken?.isCancelled == true) return (content: null, error: null);
      return (content: null, error: e.toString());
    }

    if (cancelToken?.isCancelled == true) return (content: null, error: null);

    if (rawResponse == null || rawResponse.trim().isEmpty) {
      return (content: null, error: 'LLM returned empty response');
    }

    if (isRawAgent) {
      final raw = rawResponse.trim();
      if (raw.isEmpty) {
        return (
          content: null,
          error: blockConfig.type == BlockType.imageGen
              ? 'Image agent returned empty response'
              : 'JS agent returned empty response',
        );
      }
      return (content: raw, error: null);
    }

    final content = resolveBlockContent(
      rawResponse: rawResponse,
      blockConfig: blockConfig,
      resolvedTemplate: resolvedTemplate,
    );
    if (content == null) {
      return (
        content: null,
        error: resolvedTemplate.trim().isNotEmpty
            ? 'LLM returned empty block (no text inside <${blockTagName(blockConfig, resolvedTemplate)}> tags)'
            : 'LLM returned empty response',
      );
    }
    return (content: content, error: null);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Context helpers
  // ─────────────────────────────────────────────────────────────────────────

  /// Builds a [MacroContext] snapshot from the current block generation
  /// arguments. Used to expand `{{char}}` / `{{user}}` / `{{description}}`
  /// / `{{personality}}` / `{{scenario}}` in the LLM-bound prompt and in
  /// the post-LLM content (via [MacroExpander.expand]).
  MacroContext _macroContext({Character? character, String? persona}) {
    return MacroContext(character: character, persona: persona);
  }

  /// Returns the template sent to the LLM. Empty [blockConfig.template] means
  /// no XML wrapper — the full model reply is stored as-is.
  String _resolveTemplate(BlockConfig blockConfig) {
    final raw = blockConfig.template.trim();
    if (raw.isEmpty) return '';
    return raw.replaceAll('{{name}}', blockConfig.name);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Prompt building (system + user)
  // ─────────────────────────────────────────────────────────────────────────

  /// Builds the system message: shows the model the exact template layout it
  /// must produce, plus optional user-defined prompt instructions.
  /// Mirrors upstream `BlockService.getBlocksFullPrompt`.
  String _buildSystemMessage({
    required BlockConfig blockConfig,
    required String template,
    Character? character,
    String? persona,
  }) {
    if (blockConfig.type == BlockType.imageGen) {
      final prompt = blockConfig.prompt.trim();
      if (prompt.isNotEmpty) {
        return expand(prompt, _macroContext(character: character, persona: persona));
      }
      return 'Write the roleplay response, then append the visual HTML card with '
          '[IMG:GEN] / data-iig-instruction as instructed.';
    }

    final buffer = StringBuffer();

    if (template.isNotEmpty) {
      buffer.writeln('Output format — fill in the content between these tags:');
      buffer.writeln(template);
      buffer.writeln();
    } else {
      buffer.writeln(
        'Write the block content directly. Do not wrap the answer in XML tags unless asked.',
      );
      buffer.writeln();
    }

    if (blockConfig.prompt.isNotEmpty) {
      buffer.writeln('Instructions:');
      buffer.writeln(blockConfig.prompt);
      buffer.writeln();
    }
    return buffer.toString().trimRight();
  }

  /// Builds the user message: the conversation context, character, persona,
  /// and optional chained block output. The model is meant to fill in the
  /// template based on this material.
  String _buildUserMessage({
    required BlockConfig blockConfig,
    required Character? character,
    required String? persona,
    required List<ChatMessage> contextMessages,
    required String? previousOutput,
  }) {
    final buffer = StringBuffer();

    if (blockConfig.contextSystemPrompt.isNotEmpty) {
      final sysPrompt = expand(
        blockConfig.contextSystemPrompt,
        _macroContext(character: character, persona: persona),
      );
      buffer.writeln(sysPrompt);
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

    if (previousOutput != null && previousOutput.isNotEmpty) {
      buffer.writeln('Output from previous block in chain:');
      buffer.writeln(previousOutput);
      buffer.writeln();
    }

    return buffer.toString().trimRight();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // LLM call
  // ─────────────────────────────────────────────────────────────────────────

  Future<String?> _callLLM({
    required ApiConfig apiConfig,
    required BlockConfig blockConfig,
    required String systemContent,
    required String userContent,
    CancelToken? cancelToken,
    void Function(String accumulated)? onStreamUpdate,
  }) async {
    final messages = <Map<String, String>>[
      {'role': 'system', 'content': systemContent},
      {'role': 'user', 'content': userContent},
    ];

    final useStream = onStreamUpdate != null;

    try {
      final sseClient = SseClient();
      final completer = Completer<String>();
      final buffer = StringBuffer();

      await sseClient.streamChatCompletion(
        endpoint: apiConfig.endpoint,
        apiKey: apiConfig.apiKey,
        model: blockConfig.model.isNotEmpty ? blockConfig.model : apiConfig.model,
        messages: messages,
        maxTokens: apiConfig.maxTokens,
        temperature: apiConfig.temperature,
        topP: apiConfig.topP,
        stream: useStream,
        cancelToken: cancelToken,
        onUpdate: useStream
            ? (delta, _) {
                if (delta.isEmpty) return;
                buffer.write(delta);
                onStreamUpdate!(buffer.toString());
              }
            : null,
        onComplete: (text, reasoning, {rawResponseJson}) {
          if (!completer.isCompleted) completer.complete(text);
        },
        onError: (error) {
          if (!completer.isCompleted) completer.completeError(error);
        },
      );

      return await completer.future;
    } on DioException catch (e) {
      if (cancelToken?.isCancelled == true || CancelToken.isCancel(e)) {
        return null;
      }
      debugPrint('[InfoBlockService] LLM call failed: $e');
      rethrow;
    } catch (e) {
      if (cancelToken?.isCancelled == true) return null;
      debugPrint('[InfoBlockService] LLM call failed: $e');
      rethrow;
    }
  }
}
