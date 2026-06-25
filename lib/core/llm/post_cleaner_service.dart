import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/memory_book.dart';
import '../state/db_provider.dart';
import '../utils/time_helpers.dart';
import '../../features/chat/chat_session_service.dart';
import '../../features/chat_history/chat_history_provider.dart';
import '../../features/settings/api_list_provider.dart';
import 'transport/chat_transport_request.dart';
import 'transport/llm_protocol.dart';
import 'transport/transport_factory.dart';

/// POST-cleaner service (Stage 4).
///
/// After generation completes, this service rewrites the final assistant
/// message to remove clichés, repetitive phrasings, and common AI-isms.
/// The rewrite is silent — the text in chat is replaced without a diff or
/// swipe UI. The original text is preserved as the previous swipe so the
/// user can still access it. "What changed" is visible in the request
/// preview (via studioOutputs / memoryCoverage diagnostics).
///
/// Uses the sidecar JSON approach (same as agentic write-loop): one
/// non-streaming LLM call. Falls back to the original text on any error.
class PostCleanerService {
  final Ref _ref;

  PostCleanerService(this._ref);

  /// Run the POST-cleaner on the last assistant message in [session].
  ///
  /// Returns the cleaned text, or the original if cleaning was disabled,
  /// failed, or the LLM returned an empty/refusal response.
  Future<PostCleanerResult> runCleaner({
    required String sessionId,
    required MemoryBookSettings settings,
    required String assistantText,
    CancelToken? cancelToken,
  }) async {
    if (!settings.postCleanerEnabled) {
      return PostCleanerResult(status: 'disabled', cleanedText: assistantText);
    }

    final token = cancelToken ?? CancelToken();
    if (token.isCancelled) {
      return PostCleanerResult(status: 'aborted', cleanedText: assistantText);
    }

    if (assistantText.trim().isEmpty) {
      return PostCleanerResult(status: 'ok', cleanedText: assistantText);
    }

    try {
      final cleaned = await _askLlmForCleanedText(
        settings: settings,
        assistantText: assistantText,
        cancelToken: token,
      );

      if (token.isCancelled) {
        return PostCleanerResult(status: 'aborted', cleanedText: assistantText);
      }

      if (cleaned == null || cleaned.trim().isEmpty) {
        return PostCleanerResult(status: 'ok', cleanedText: assistantText);
      }

      // Safety: if the cleaned text is drastically shorter or longer, skip.
      // The cleaner should refine, not rewrite from scratch.
      final ratio = cleaned.length / assistantText.length;
      if (ratio < 0.3 || ratio > 3.0) {
        debugPrint(
          '[PostCleaner] skipped: length ratio $ratio out of bounds '
          '(original=${assistantText.length}, cleaned=${cleaned.length})',
        );
        return PostCleanerResult(status: 'skipped', cleanedText: assistantText);
      }

      return PostCleanerResult(
        status: 'ok',
        cleanedText: cleaned,
        originalText: assistantText,
        wasCleaned: cleaned != assistantText,
      );
    } on TimeoutException {
      return PostCleanerResult(status: 'timeout', cleanedText: assistantText);
    } catch (e) {
      if (token.isCancelled ||
          (e is DioException && CancelToken.isCancel(e))) {
        return PostCleanerResult(status: 'aborted', cleanedText: assistantText);
      }
      debugPrint('[PostCleaner] error: $e');
      return PostCleanerResult(
        status: 'error',
        cleanedText: assistantText,
        error: '$e',
      );
    }
  }

  Future<String?> _askLlmForCleanedText({
    required MemoryBookSettings settings,
    required String assistantText,
    required CancelToken cancelToken,
  }) async {
    final isCustom = settings.sidecarSource == 'custom';
    String endpoint;
    String apiKey;
    String model;
    String protocol;

    if (isCustom) {
      endpoint = settings.sidecarEndpoint;
      apiKey = settings.sidecarApiKey;
      model = settings.sidecarModel;
      protocol = LlmProtocol.openai;
    } else {
      await _ref.read(apiListProvider.future);
      final chatConfig = _ref.read(activeApiConfigProvider);
      if (chatConfig == null) {
        throw Exception('No chat API config available for post-cleaner');
      }
      endpoint = chatConfig.endpoint ?? '';
      apiKey = chatConfig.apiKey ?? '';
      model = settings.sidecarModel.isNotEmpty
          ? settings.sidecarModel
          : (chatConfig.model ?? '');
      protocol = chatConfig.protocol;
    }

    if (endpoint.isEmpty || model.isEmpty) {
      throw Exception('Post-cleaner API not configured');
    }

    final prompt = '''You are a prose editor for a roleplay story. Your job is to clean up the following assistant response by removing clichés, repetitive phrasings, and common AI-isms.

Rules:
- Keep the same meaning, events, and character voices.
- Remove or rephrase: "a shiver ran down", "a dance of", "symphony of", "tapestry of", "couldn't help but", "a mix of", "sent shivers", "palpable tension", and similar overused phrases.
- Remove redundant descriptions and filler.
- Do NOT add new content, events, or dialogue.
- Do NOT change the POV, tense, or language.
- Keep the same approximate length.
- Return ONLY the cleaned text, no explanation, no markdown.

Assistant response to clean:
$assistantText''';

    final completer = Completer<String>();
    final transport = pickChatTransport(protocol);

    transport.stream(
      request: ChatTransportRequest(
        endpoint: endpoint,
        apiKey: apiKey,
        model: model,
        messages: [
          {'role': 'user', 'content': prompt},
        ],
        maxTokens: (assistantText.length ~/ 3).clamp(500, 8000),
        temperature: 0.3,
        topP: 1.0,
        stream: false,
      ),
      cancelToken: cancelToken,
      onComplete: (text, _, {rawResponseJson}) {
        if (!completer.isCompleted) completer.complete(text);
      },
      onError: (error) {
        if (!completer.isCompleted) completer.completeError(error);
      },
    );

    final raw = await completer.future.timeout(
      Duration(milliseconds: settings.sidecarTimeoutMs),
    );

    final cleaned = raw.trim();
    if (cleaned.isEmpty) return null;
    return cleaned;
  }

  /// Applies the cleaned text to the session: updates the last assistant
  /// message content in DB and invalidates the chat history provider.
  Future<void> applyCleanedText({
    required String sessionId,
    required String messageId,
    required String cleanedText,
    required String originalText,
  }) async {
    final chatRepo = _ref.read(chatRepoProvider);
    final session = await chatRepo.getById(sessionId);
    if (session == null) return;

    final messages = List<dynamic>.from(session.messages);
    var updated = false;
    for (var i = messages.length - 1; i >= 0; i--) {
      final msg = messages[i];
      if (msg is Map<String, dynamic> && msg['id'] == messageId) {
        // Preserve original as a swipe if swipes exist.
        final swipes = msg['swipes'] as List<dynamic>?;
        if (swipes != null && swipes.length > 1) {
          // Keep the original as the previous swipe, set cleaned as current.
          swipes[swipes.length - 1] = originalText;
          swipes.add(cleanedText);
          msg['swipes'] = swipes;
          msg['swipeId'] = swipes.length - 1;
        } else {
          // No swipes: add original + cleaned.
          msg['swipes'] = [originalText, cleanedText];
          msg['swipeId'] = 1;
        }
        msg['content'] = cleanedText;
        updated = true;
        break;
      }
    }

    if (!updated) return;

    final updatedSession = session.copyWith(
      messages: messages.cast(),
      updatedAt: currentTimestampSeconds(),
    );
    await chatRepo.put(updatedSession);
    ChatSessionService.updateCache(updatedSession);
    _ref.invalidate(chatHistoryProvider);
  }
}

/// Result of a POST-cleaner run.
class PostCleanerResult {
  final String status;
  final String cleanedText;
  final String? originalText;
  final bool wasCleaned;
  final String? error;

  const PostCleanerResult({
    required this.status,
    required this.cleanedText,
    this.originalText,
    this.wasCleaned = false,
    this.error,
  });
}
