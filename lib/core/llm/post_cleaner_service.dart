import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/agent_operation_record.dart';
import '../models/chat_message.dart';
import '../models/memory_book.dart';
import '../state/db_provider.dart';
import '../../features/chat/chat_session_service.dart';
import '../../features/chat_history/chat_history_provider.dart';
import 'sidecar_llm_client.dart';
import 'sidecar_retry_runner.dart';

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
  /// [recentMessages] is the bounded chat history before the assistant response,
  /// used for conservative local continuity checks (who said what, who is
  /// present, clothing, positions, recent actions).
  /// [studioOutputs] are the controller notes that shaped the final response;
  /// they let the cleaner verify the response against the intended behavior and
  /// constraints.
  Future<PostCleanerResult> runCleaner({
    required String sessionId,
    required MemoryBookSettings settings,
    required String assistantText,
    List<String> broadcastBlocks = const [],
    List<ChatMessage> recentMessages = const [],
    List<Map<String, dynamic>> studioOutputs = const [],
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
          await _llm.resolveConfigForCleaner(settings, errorLabel: 'post-cleaner');
      if (token.isCancelled) {
        return PostCleanerResult(status: 'aborted', cleanedText: assistantText);
      }

      final outcome = await _askLlmForCleanedText(
        config: config,
        settings: settings,
        assistantText: assistantText,
        broadcastBlocks: broadcastBlocks,
        recentMessages: recentMessages,
        studioOutputs: studioOutputs,
        cancelToken: token,
      );

      if (token.isCancelled) {
        return PostCleanerResult(
          status: 'aborted',
          cleanedText: assistantText,
          attempts: outcome.attempts,
          totalElapsedMs: outcome.totalElapsedMs,
        );
      }

      final cleaned = outcome.text;
      if (cleaned == null || cleaned.trim().isEmpty) {
        if (!outcome.isOk) {
          return PostCleanerResult(
            status: _statusLabel(outcome.status),
            cleanedText: assistantText,
            error: outcome.attempts.isNotEmpty
                ? outcome.attempts.last.error
                : null,
            attempts: outcome.attempts,
            totalElapsedMs: outcome.totalElapsedMs,
          );
        }
        return PostCleanerResult(
          status: 'ok',
          cleanedText: assistantText,
          attempts: outcome.attempts,
          totalElapsedMs: outcome.totalElapsedMs,
        );
      }

      // Safety: if the cleaned text is drastically shorter or longer, skip.
      final ratio = cleaned.length / assistantText.length;
      if (ratio < 0.3 || ratio > 3.0) {
        debugPrint(
          '[PostCleaner] skipped: length ratio $ratio out of bounds '
          '(original=${assistantText.length}, cleaned=${cleaned.length})',
        );
        return PostCleanerResult(
          status: 'skipped',
          cleanedText: assistantText,
          attempts: outcome.attempts,
          totalElapsedMs: outcome.totalElapsedMs,
        );
      }

      return PostCleanerResult(
        status: 'ok',
        cleanedText: cleaned,
        originalText: assistantText,
        wasCleaned: cleaned != assistantText,
        attempts: outcome.attempts,
        totalElapsedMs: outcome.totalElapsedMs,
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

  static String _statusLabel(AgentOperationStatus status) {
    return switch (status) {
      AgentOperationStatus.ok => 'ok',
      AgentOperationStatus.disabled => 'disabled',
      AgentOperationStatus.aborted => 'aborted',
      AgentOperationStatus.timeout => 'timeout',
      AgentOperationStatus.httpError => 'error',
      AgentOperationStatus.invalidOutput => 'error',
      AgentOperationStatus.error => 'error',
    };
  }

  Future<SidecarCallOutcome> _askLlmForCleanedText({
    required SidecarApiConfig config,
    required MemoryBookSettings settings,
    required String assistantText,
    List<String> broadcastBlocks = const [],
    List<ChatMessage> recentMessages = const [],
    List<Map<String, dynamic>> studioOutputs = const [],
    required CancelToken cancelToken,
  }) async {
    final prompt = buildCleanerPrompt(
      assistantText: assistantText,
      broadcastBlocks: broadcastBlocks,
      recentMessages: recentMessages,
      studioOutputs: studioOutputs,
      maxCharsPerMessage: settings.postCleanerMaxCharsPerMessage,
    );

    final effectiveMaxTokens = settings.postCleanerMaxTokens > 0
        ? settings.postCleanerMaxTokens
        : (assistantText.length ~/ 2).clamp(1000, 16000);

    return _llm.callOnceWithLog(
      config: config,
      prompt: prompt,
      maxTokens: effectiveMaxTokens,
      temperature: settings.postCleanerTemperature,
      timeoutMs: _llm.resolveCleanerTimeout(settings),
      cancelToken: cancelToken,
    );
  }

  /// Builds the POST-cleaner prompt. When [broadcastBlocks] are supplied the
  /// user's own language + prose-quality rules (captured verbatim at Studio
  /// build time) are injected and take precedence over the built-in defaults,
  /// so the rewrite respects the preset's language and anti-cliché/anti-slop
  /// rules instead of a hardcoded English-only list. When [recentMessages] are
  /// supplied, the cleaner performs a conservative local continuity check
  /// against the recent chat history. When [studioOutputs] are supplied, the
  /// cleaner can verify the response against the controller notes that shaped
  /// the final generation. Public for testing.
  @visibleForTesting
  static String buildCleanerPrompt({
    required String assistantText,
    List<String> broadcastBlocks = const [],
    List<ChatMessage> recentMessages = const [],
    List<Map<String, dynamic>> studioOutputs = const [],
    int maxCharsPerMessage = 3000,
  }) {
    final rules = broadcastBlocks
        .map((b) => b.trim())
        .where((b) => b.isNotEmpty)
        .toList();

    final buffer = StringBuffer()
      ..writeln(
        'You are a conservative prose editor for a roleplay story. Your '
        'primary job is to clean up the following assistant response by '
        'removing clichés, repetitive phrasings, and common AI-isms.',
      )
      ..writeln();

    // Recent chat history — authoritative for local scene state.
    if (recentMessages.isNotEmpty) {
      final history = _formatRecentMessages(recentMessages, maxCharsPerMessage);
      if (history.isNotEmpty) {
        buffer
          ..writeln('RECENT CHAT HISTORY:')
          ..writeln(history)
          ..writeln();
      }
    }

    // Studio controller notes — authoritative for intended behavior/constraints.
    if (studioOutputs.isNotEmpty) {
      final notes = _formatStudioOutputs(studioOutputs);
      if (notes.isNotEmpty) {
        buffer
          ..writeln('STUDIO CONTROLLER NOTES:')
          ..writeln(notes)
          ..writeln();
      }
    }

    // Authoritative style rules from the active preset.
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
      ..writeln();

    // Continuity rules — only when history or Studio notes are available.
    if (recentMessages.isNotEmpty || studioOutputs.isNotEmpty) {
      buffer
        ..writeln('Continuity rules:')
        ..writeln(
          '- Before editing style, silently check the assistant response '
          'against RECENT CHAT HISTORY and STUDIO CONTROLLER NOTES.',
        )
        ..writeln(
          '- Fix only clear local continuity contradictions that are directly '
          'contradicted by the provided context: who said what, who is '
          'present, current position, clothing, held objects, object '
          'ownership, and recent actions.',
        )
        ..writeln('- If the context is ambiguous, keep the original wording.')
        ..writeln('- Do not invent missing details.')
        ..writeln(
          '- Do not add new events, explanations, dialogue, memories, or '
          'motivations.',
        )
        ..writeln(
          '- Prefer minimal edits: remove, shorten, or neutralize the '
          'incorrect phrase.',
        )
        ..writeln(
          '- If correcting a continuity issue requires adding a new '
          'paragraph or scene event, do not fix it — only clean style.',
        )
        ..writeln();
    }

    buffer
      ..writeln('- Return ONLY the cleaned text, no explanation, no markdown.')
      ..writeln()
      ..writeln('Assistant response to clean:')
      ..write(assistantText);

    return buffer.toString();
  }

  /// Formats recent chat messages into a compact literal block for the cleaner
  /// prompt. Each message is trimmed to [maxChars] characters to keep the
  /// prompt within a reasonable token budget.
  static const _kDefaultMaxMessageChars = 3000;

  static String _formatRecentMessages(
    List<ChatMessage> messages, [
    int maxChars = _kDefaultMaxMessageChars,
  ]) {
    final buf = StringBuffer();
    for (final m in messages) {
      if (m.content.trim().isEmpty) continue;
      final role = m.role == 'assistant' ? 'assistant' : 'user';
      final idSuffix = m.id.isNotEmpty ? ' #${m.id}' : '';
      var content = m.content;
      if (content.length > maxChars) {
        content = '${content.substring(0, maxChars)}…';
      }
      buf.writeln('[$role$idSuffix]');
      buf.writeln(content);
      buf.writeln();
    }
    return buf.toString().trimRight();
  }

  /// Formats Studio controller outputs into a compact block. Each entry
  /// includes the agent name and a trimmed content preview.
  static const _kMaxStudioOutputChars = 2000;

  static String _formatStudioOutputs(List<Map<String, dynamic>> outputs) {
    final buf = StringBuffer();
    for (final o in outputs) {
      final name = (o['name'] as String?)?.trim() ?? '';
      if (name.isEmpty) continue;
      var content = (o['content'] as String?)?.trim() ?? '';
      if (content.isEmpty) continue;
      if (content.length > _kMaxStudioOutputChars) {
        content = '${content.substring(0, _kMaxStudioOutputChars)}…';
      }
      buf.writeln('[$name]');
      buf.writeln(content);
      buf.writeln();
    }
    return buf.toString().trimRight();
  }

  /// Applies the cleaned text to the session: appends a `'cleaned'` agent
  /// sub-swipe (blue icon) to the last assistant message via
  /// [ChatRepo.appendAgentSwipe], preserving the original as a `'final'`
  /// sub-swipe. Does NOT touch the legacy `swipes[]` (green icons).
  Future<void> applyCleanedText({
    required String sessionId,
    required String messageId,
    required String cleanedText,
    required String originalText,
  }) async {
    final chatRepo = _ref.read(chatRepoProvider);
    final updated = await chatRepo.appendAgentSwipe(
      sessionId: sessionId,
      messageId: messageId,
      content: cleanedText,
      kind: 'cleaned',
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
  final List<AgentOperationAttempt> attempts;
  final int totalElapsedMs;

  const PostCleanerResult({
    required this.status,
    required this.cleanedText,
    this.originalText,
    this.wasCleaned = false,
    this.error,
    this.attempts = const [],
    this.totalElapsedMs = 0,
  });
}
