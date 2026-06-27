import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/agent_operation_record.dart';
import '../models/chat_message.dart';
import '../models/character.dart';
import '../models/persona.dart';
import '../models/pipeline_settings.dart';
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
/// [ChatRepo.appendCleanerSwipe] for the atomic DB update.
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
  Future<PostCleanerResult> runCleaner({
    required String sessionId,
    required PipelineSettings settings,
    required String assistantText,
    List<String> broadcastBlocks = const [],
    List<ChatMessage> recentMessages = const [],
    List<String>? auditIssues,
    CancelToken? cancelToken,
    void Function(String accumulatedText)? onCleanedChunk,
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
        auditIssues: auditIssues,
        cancelToken: token,
        onCleanedChunk: onCleanedChunk,
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
    required PipelineSettings settings,
    required String assistantText,
    List<String> broadcastBlocks = const [],
    List<ChatMessage> recentMessages = const [],
    List<String>? auditIssues,
    required CancelToken cancelToken,
    void Function(String accumulatedText)? onCleanedChunk,
  }) async {
    final prompt = buildCleanerPrompt(
      assistantText: assistantText,
      broadcastBlocks: broadcastBlocks,
      recentMessages: recentMessages,
      auditIssues: auditIssues,
      maxCharsPerMessage: settings.postCleanerMaxCharsPerMessage,
    );

    final effectiveMaxTokens = settings.postCleanerMaxTokens > 0
        ? settings.postCleanerMaxTokens
        : (assistantText.length ~/ 2).clamp(1000, 16000);

    // When the caller passes an onCleanedChunk callback, stream the rewrite
    // so the UI can render it progressively instead of replacing the text in
    // one shot. Otherwise use the non-streaming path (same as before).
    if (onCleanedChunk != null) {
      return _llm.callStreamWithLog(
        config: config,
        prompt: prompt,
        maxTokens: effectiveMaxTokens,
        temperature: settings.postCleanerTemperature,
        timeoutMs: _llm.resolveCleanerTimeout(settings),
        cancelToken: cancelToken,
        onChunk: onCleanedChunk,
      );
    }

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
  /// against the recent chat history. Public for testing.
  @visibleForTesting
  static String buildCleanerPrompt({
    required String assistantText,
    List<String> broadcastBlocks = const [],
    List<ChatMessage> recentMessages = const [],
    List<String>? auditIssues,
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

    // Character consistency notes from the auditor — explicit fix instructions.
    // Only added when the auditor found concrete contradictions.
    if (auditIssues != null && auditIssues.isNotEmpty) {
      buffer
        ..writeln('CHARACTER CONSISTENCY NOTES (from auditor — fix these):')
        ..writeln(auditIssues.map((i) => '- $i').join('\n'))
        ..writeln()
        ..writeln(
          'Apply minimal fixes for these issues while also cleaning style.',
        )
        ..writeln(
          'Do not add new content to resolve them. Prefer deletion or neutral '
          'rewording.',
        )
        ..writeln();
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

    // Continuity rules — only when history is available.
    if (recentMessages.isNotEmpty) {
      buffer
        ..writeln('Continuity rules:')
        ..writeln(
          '- Before editing style, silently check the assistant response '
          'against RECENT CHAT HISTORY.',
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

  /// Applies the cleaned text to the session: appends a new green swipe
  /// carrying [cleanedText] to the last assistant message via
  /// [ChatRepo.appendCleanerSwipe]. The original text remains available as the
  /// previous swipe.
  Future<void> applyCleanedText({
    required String sessionId,
    required String messageId,
    required String cleanedText,
  }) async {
    final chatRepo = _ref.read(chatRepoProvider);
    final updated = await chatRepo.appendCleanerSwipe(
      sessionId: sessionId,
      messageId: messageId,
      cleanedText: cleanedText,
    );
    if (!updated) return;

    // Refresh cache + reactive streams.
    final session = await chatRepo.getById(sessionId);
    if (session != null) {
      ChatSessionService.updateCache(session);
    }
    _ref.invalidate(chatHistoryProvider);
  }

  /// Pass 0: Character/World Auditor.
  ///
  /// Diagnostic sidecar pass that checks [assistantText] against the full
  /// generation context (character card, persona, lorebooks, memory, summary,
  /// arcs, entities, recent history) and returns a compact list of
  /// contradictions. Does NOT rewrite text.
  ///
  /// Returns:
  /// - `[]` — no contradictions found.
  /// - `['issue 1', ...]` — list of specific contradictions.
  /// - `null` — audit call failed, JSON unparseable, or was aborted. Caller
  ///   should skip audit notes and run the cleaner as Phase 1.
  Future<List<String>?> runCharacterAudit({
    required String assistantText,
    required Character character,
    Persona? persona,
    String? lorebooksContent,
    String? memoryContent,
    String? summaryContent,
    String? arcContent,
    String? entitiesContent,
    List<ChatMessage> recentMessages = const [],
    required PipelineSettings settings,
    CancelToken? cancelToken,
  }) async {
    if (assistantText.trim().isEmpty) return const [];

    final token = cancelToken ?? CancelToken();
    if (token.isCancelled) return null;

    try {
      final config = await _llm.resolveConfigForCleaner(
        settings,
        errorLabel: 'post-cleaner-audit',
      );
      if (token.isCancelled) return null;

      final prompt = buildAuditPrompt(
        assistantText: assistantText,
        character: character,
        persona: persona,
        lorebooksContent: lorebooksContent,
        memoryContent: memoryContent,
        summaryContent: summaryContent,
        arcContent: arcContent,
        entitiesContent: entitiesContent,
        recentMessages: recentMessages,
        maxCharsPerMessage: settings.postCleanerMaxCharsPerMessage,
      );

      // Auditor: cheap, JSON-only, low temperature, small token budget.
      final outcome = await _llm.callOnceWithLog(
        config: config,
        prompt: prompt,
        maxTokens: 1024,
        temperature: 0.0,
        timeoutMs: _llm.resolveCleanerTimeout(settings),
        cancelToken: token,
      );

      if (token.isCancelled) return null;

      final text = outcome.text;
      if (text == null || text.trim().isEmpty) {
        if (!outcome.isOk) return null;
        return const [];
      }

      return parseAuditJson(text);
    } on TimeoutException {
      return null;
    } catch (e) {
      if (token.isCancelled ||
          (e is DioException && CancelToken.isCancel(e))) {
        return null;
      }
      debugPrint('[PostCleanerAudit] error: $e');
      return null;
    }
  }

  /// Builds the auditor prompt. The auditor checks the assistant response
  /// against all provided context and returns a compact JSON list of
  /// contradictions. Public for testing.
  @visibleForTesting
  static String buildAuditPrompt({
    required String assistantText,
    required Character character,
    Persona? persona,
    String? lorebooksContent,
    String? memoryContent,
    String? summaryContent,
    String? arcContent,
    String? entitiesContent,
    List<ChatMessage> recentMessages = const [],
    int maxCharsPerMessage = 3000,
  }) {
    final buffer = StringBuffer()
      ..writeln(
        'You are a continuity auditor for a roleplay story. Your job is to '
        'find contradictions between the assistant response and the provided '
        'context.',
      )
      ..writeln();

    // Character profile.
    buffer.writeln('CHARACTER PROFILE:');
    buffer.writeln('Name: ${character.name}');
    final desc = character.description?.trim() ?? '';
    if (desc.isNotEmpty) buffer.writeln('Description: $desc');
    final pers = character.personality?.trim() ?? '';
    if (pers.isNotEmpty) buffer.writeln('Personality: $pers');
    final scen = character.scenario?.trim() ?? '';
    if (scen.isNotEmpty) buffer.writeln('Scenario: $scen');
    final phi = character.postHistoryInstructions?.trim() ?? '';
    if (phi.isNotEmpty) buffer.writeln('Post-history instructions: $phi');
    buffer.writeln();

    // User persona.
    if (persona != null) {
      buffer.writeln('USER PERSONA:');
      buffer.writeln('Name: ${persona.name}');
      final pp = persona.prompt?.trim() ?? '';
      if (pp.isNotEmpty) buffer.writeln('Description: $pp');
      buffer.writeln();
    }

    // Lorebooks / world context.
    final lore = lorebooksContent?.trim() ?? '';
    if (lore.isNotEmpty) {
      buffer
        ..writeln('INJECTED WORLD/LORE CONTEXT:')
        ..writeln(lore)
        ..writeln();
    }

    // Memory context.
    final mem = memoryContent?.trim() ?? '';
    if (mem.isNotEmpty) {
      buffer
        ..writeln('INJECTED MEMORY CONTEXT:')
        ..writeln(mem)
        ..writeln();
    }

    // Summary.
    final sum = summaryContent?.trim() ?? '';
    if (sum.isNotEmpty) {
      buffer
        ..writeln('SUMMARY:')
        ..writeln(sum)
        ..writeln();
    }

    // Arcs.
    final arcs = arcContent?.trim() ?? '';
    if (arcs.isNotEmpty) {
      buffer
        ..writeln('ARCS:')
        ..writeln(arcs)
        ..writeln();
    }

    // Entities.
    final ents = entitiesContent?.trim() ?? '';
    if (ents.isNotEmpty) {
      buffer
        ..writeln('ENTITIES:')
        ..writeln(ents)
        ..writeln();
    }

    // Recent chat history.
    if (recentMessages.isNotEmpty) {
      final history = _formatRecentMessages(recentMessages, maxCharsPerMessage);
      if (history.isNotEmpty) {
        buffer
          ..writeln('RECENT CHAT HISTORY:')
          ..writeln(history)
          ..writeln();
      }
    }

    buffer
      ..writeln('ASSISTANT RESPONSE TO AUDIT:')
      ..writeln(assistantText)
      ..writeln()
      ..writeln('Instructions:')
      ..writeln('- Check the response against ALL provided context.')
      ..writeln(
        '- Report ONLY direct contradictions: wrong names, wrong '
        'relationships, wrong locations, personality conflicts, world-fact '
        'errors, persona identity errors.',
      )
      ..writeln('- Do NOT report style issues, cliches, or prose quality.')
      ..writeln(
        '- Do NOT suggest fixes or rewrites. Only describe the contradiction.',
      )
      ..writeln('- If no contradictions found, return: {"ok": true}')
      ..writeln(
        '- If contradictions found, return: {"ok": false, "issues": ["...", "..."]}',
      )
      ..writeln()
      ..writeln('Return ONLY the JSON, no other text.');

    return buffer.toString();
  }

  /// Parses the auditor JSON response.
  ///
  /// - `{"ok": true}` → `[]`
  /// - `{"ok": false, "issues": [...]}` → list of strings
  /// - malformed / unparseable → `null` (skip audit)
  @visibleForTesting
  static List<String>? parseAuditJson(String raw) {
    var text = raw.trim();
    if (text.isEmpty) return null;

    // Some models wrap JSON in ``` fences or prose. Extract the first
    // balanced `{...}` block.
    final start = text.indexOf('{');
    if (start < 0) return null;
    final end = text.lastIndexOf('}');
    if (end <= start) return null;
    text = text.substring(start, end + 1);

    try {
      final parsed = jsonDecode(text);
      if (parsed is! Map<String, dynamic>) return null;
      final ok = parsed['ok'];
      if (ok == true) return const [];
      if (ok == false) {
        final issues = parsed['issues'];
        if (issues is List) {
          return issues
              .whereType<String>()
              .where((s) => s.trim().isNotEmpty)
              .toList();
        }
        return null;
      }
      return null;
    } catch (_) {
      return null;
    }
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
