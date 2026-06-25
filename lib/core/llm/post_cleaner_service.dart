import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/memory_book.dart';
import '../state/db_provider.dart';
import '../../features/chat/chat_session_service.dart';
import '../../features/chat_history/chat_history_provider.dart';
import 'sidecar_llm_client.dart';

/// POST-cleaner service (Stage 4).
///
/// After generation completes, this service rewrites the final assistant
/// message to remove clichés, repetitive phrasings, and common AI-isms.
/// The rewrite is silent — the text in chat is replaced without a diff or
/// swipe UI. The original text is preserved as a swipe so the user can
/// still access it.
///
/// Uses [SidecarLlmClient] for the sidecar LLM call and
/// [ChatRepo.appendSwipeToMessage] for the atomic DB update.
/// Falls back to the original text on any error.
class PostCleanerService {
  final Ref _ref;
  final SidecarLlmClient _llm;

  PostCleanerService(this._ref) : _llm = SidecarLlmClient(_ref);

  /// Run the POST-cleaner on the last assistant message.
  ///
  /// Returns the cleaned text, or the original if cleaning was disabled,
  /// failed, or the LLM returned an empty/refusal response.
  /// [broadcastBlocks] are verbatim cross-cutting preset rules (output language
  /// + prose-quality guards) captured at Studio build time. When present they
  /// drive the cleaner using the user's OWN rules instead of the hardcoded
  /// English-only cliché list, and pin the output language so the rewrite does
  /// not silently translate or break language-specific formatting.
  Future<PostCleanerResult> runCleaner({
    required String sessionId,
    required MemoryBookSettings settings,
    required String assistantText,
    List<String> broadcastBlocks = const [],
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
      final config =
          await _llm.resolveConfig(settings, errorLabel: 'post-cleaner');
      if (token.isCancelled) {
        return PostCleanerResult(status: 'aborted', cleanedText: assistantText);
      }

      final cleaned = await _askLlmForCleanedText(
        config: config,
        settings: settings,
        assistantText: assistantText,
        broadcastBlocks: broadcastBlocks,
        cancelToken: token,
      );

      if (token.isCancelled) {
        return PostCleanerResult(status: 'aborted', cleanedText: assistantText);
      }

      if (cleaned == null || cleaned.trim().isEmpty) {
        return PostCleanerResult(status: 'ok', cleanedText: assistantText);
      }

      // Safety: if the cleaned text is drastically shorter or longer, skip.
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
    required SidecarApiConfig config,
    required MemoryBookSettings settings,
    required String assistantText,
    List<String> broadcastBlocks = const [],
    required CancelToken cancelToken,
  }) async {
    final prompt = buildCleanerPrompt(
      assistantText: assistantText,
      broadcastBlocks: broadcastBlocks,
    );

    final raw = await _llm.callOnce(
      config: config,
      prompt: prompt,
      maxTokens: (assistantText.length ~/ 3).clamp(500, 8000),
      temperature: 0.3,
      timeoutMs: settings.sidecarTimeoutMs,
      cancelToken: cancelToken,
    );

    final cleaned = raw.trim();
    return cleaned.isEmpty ? null : cleaned;
  }

  /// Builds the POST-cleaner prompt. When [broadcastBlocks] are supplied the
  /// user's own language + prose-quality rules (captured verbatim at Studio
  /// build time) are injected and take precedence over the built-in defaults,
  /// so the rewrite respects the preset's language and anti-cliché/anti-slop
  /// rules instead of a hardcoded English-only list. Public for testing.
  @visibleForTesting
  static String buildCleanerPrompt({
    required String assistantText,
    List<String> broadcastBlocks = const [],
  }) {
    final rules = broadcastBlocks
        .map((b) => b.trim())
        .where((b) => b.isNotEmpty)
        .toList();

    final buffer = StringBuffer()
      ..writeln(
        'You are a prose editor for a roleplay story. Your job is to clean up '
        'the following assistant response by removing clichés, repetitive '
        'phrasings, and common AI-isms.',
      )
      ..writeln();

    if (rules.isNotEmpty) {
      buffer
        ..writeln(
          'AUTHORITATIVE RULES (from the active preset — follow these exactly; '
          'they OVERRIDE the generic guidance below, especially for output '
          'language and formatting):',
        )
        ..writeln()
        ..writeln(rules.join('\n\n---\n\n'))
        ..writeln();
    }

    buffer
      ..writeln('Rules:')
      ..writeln('- Keep the same meaning, events, and character voices.')
      ..writeln(
        '- Remove or rephrase overused phrases and AI-isms (e.g. "a shiver ran '
        'down", "a dance of", "symphony of", "tapestry of", "couldn\'t help '
        'but", "a mix of", "sent shivers", "palpable tension").',
      )
      ..writeln('- Remove redundant descriptions and filler.')
      ..writeln('- Do NOT add new content, events, or dialogue.')
      ..writeln(
        '- Do NOT change the POV, tense, or the output language. Preserve the '
        'language and formatting required by the authoritative rules above.',
      )
      ..writeln('- Keep the same approximate length.')
      ..writeln('- Return ONLY the cleaned text, no explanation, no markdown.')
      ..writeln()
      ..writeln('Assistant response to clean:')
      ..write(assistantText);

    return buffer.toString();
  }

  /// Applies the cleaned text to the session: updates the last assistant
  /// message content in DB (atomically via [ChatRepo.appendSwipeToMessage])
  /// and invalidates the chat history provider.
  Future<void> applyCleanedText({
    required String sessionId,
    required String messageId,
    required String cleanedText,
    required String originalText,
  }) async {
    final chatRepo = _ref.read(chatRepoProvider);
    final updated = await chatRepo.appendSwipeToMessage(
      sessionId: sessionId,
      messageId: messageId,
      newContent: cleanedText,
      previousContent: originalText,
    );
    if (!updated) return;

    // Refresh cache + reactive streams.
    final session = await chatRepo.getById(sessionId);
    if (session != null) {
      ChatSessionService.updateCache(session);
    }
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
