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
import '../utils/think_tags.dart';
import '../../features/chat/chat_session_service.dart';
import '../../features/chat_history/chat_history_provider.dart';
import 'aux_llm_client.dart';
import 'aux_retry_runner.dart';

/// POST-cleaner service (Stage 4).
///
/// After generation completes, this service rewrites the final assistant
/// message to remove clichés, repetitive phrasings, and common AI-isms.
/// The rewrite is silent — the text in chat is replaced without a diff or
/// swipe UI. The original text is preserved as a swipe so the user can
/// still access it.
///
/// Uses [AuxLlmClient] for the auxiliary LLM call and
/// [ChatRepo.appendAgentSwipe] for the atomic DB update.
/// Falls back to the original text on any error.
class PostCleanerService {
  final Ref _ref;
  final AuxLlmClient _llm;

  PostCleanerService(this._ref) : _llm = AuxLlmClient(_ref);

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
    String studioApiConfigId = '',
    bool useStudioApiConfigSlot = false,
  }) async {
    // Post-cleaner is always-on (hardcoded in backend). The postCleanerEnabled
    // toggle was removed from the UI — the cleaner always runs when Studio is
    // enabled. The old early-return on !settings.postCleanerEnabled is gone.

    // Strip any hidden reasoning (`<think>…</think>` / `<thinking>…`) that the
    // generator left inside the saved message content. If it reaches the
    // cleaner prompt the model often echoes / re-expands it, blowing the
    // output length past the safety ratio (→ silently skipped, no swipe). We
    // clean the visible prose only and compare lengths against this stripped
    // baseline, not the raw stored text.
    assistantText = stripThinkTags(assistantText);

    final token = cancelToken ?? CancelToken();
    if (token.isCancelled) {
      return PostCleanerResult(status: 'aborted', cleanedText: assistantText);
    }

    if (assistantText.trim().isEmpty) {
      return PostCleanerResult(status: 'ok', cleanedText: assistantText);
    }

    try {
      final config = useStudioApiConfigSlot || studioApiConfigId.isNotEmpty
          ? await _llm.resolveStudioSlotConfig(
              studioApiConfigId,
              errorLabel: 'post-cleaner',
            )
          : await _llm.resolveConfigForCleaner(
              settings,
              errorLabel: 'post-cleaner',
            );
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

      // Also strip reasoning the cleaner model itself may have emitted in its
      // reply (some sidecar models wrap output in raw `<think>` blocks).
      final cleaned = outcome.text == null
          ? null
          : stripThinkTags(outcome.text!);
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
            model: config.model,
          );
        }
        return PostCleanerResult(
          status: 'ok',
          cleanedText: assistantText,
          attempts: outcome.attempts,
          totalElapsedMs: outcome.totalElapsedMs,
          model: config.model,
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
          model: config.model,
        );
      }

      // Safety: reject the rewrite if it dropped protected markup that was
      // present in the original assistant response. Cheap presence-only check
      // (ported from Marinara `text-rewrite-safety.ts`): if the original had
      // inline HTML/XML tags or fenced code blocks and the cleaned version no
      // longer has any, the cleaner stripped formatting it was told to
      // preserve — keep the original. Also protects meta-OOC blocks
      // (e.g. `<lumiaooc>`, `<oocnote>`, any `<*ooc*>` — meta-commentary
      // emitted by the Main Responder under the Studio meta-weaver
      // architecture) — if the original had one and the cleaned version
      // dropped it, keep the original. This guards against the common
      // LLM failure mode of flattening formatting when asked to "rewrite for
      // clarity". Does NOT verify the *same* tags/fences survive, just that
      // *some* survive — structural equality is the cleaner prompt's job.
      if (textRewriteDropsProtectedMarkup(assistantText, cleaned) ||
          lumiaoocDropped(assistantText, cleaned)) {
        debugPrint(
          '[PostCleaner] skipped: rewrite dropped protected markup '
          '(HTML/XML tags or fenced code blocks present in original but '
          'absent in cleaned)',
        );
        return PostCleanerResult(
          status: 'skipped',
          cleanedText: assistantText,
          attempts: outcome.attempts,
          totalElapsedMs: outcome.totalElapsedMs,
          model: config.model,
        );
      }

      return PostCleanerResult(
        status: 'ok',
        cleanedText: cleaned,
        originalText: assistantText,
        wasCleaned: cleaned != assistantText,
        attempts: outcome.attempts,
        totalElapsedMs: outcome.totalElapsedMs,
        model: config.model,
      );
    } on TimeoutException {
      return PostCleanerResult(status: 'timeout', cleanedText: assistantText);
    } catch (e) {
      if (token.isCancelled || (e is DioException && CancelToken.isCancel(e))) {
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

  /// Returns true if [original] had inline HTML/XML tags or fenced code blocks
  /// and [edited] no longer has any. Used as a pre-application guard for the
  /// cleaner result: if the rewrite flattened formatting the prompt told the
  /// cleaner to preserve, we keep the original.
  ///
  /// - Inline HTML/XML tags: matches `</?[a-zA-Z][^>]*>` (a `<` followed by an
  ///   optional `/` and a letter — excludes our `==...==` markdown markers
  ///   and inline `code` single backticks).
  /// - Fenced code blocks: matches the triple-backtick fence ```` ``` ````.
  ///
  /// Presence-only check — does NOT verify the *same* tags/fences survive,
  /// only that *some* survive. Structural preservation is the cleaner
  /// prompt's responsibility; this guard only catches the catastrophic case
  /// of the cleaner stripping ALL formatting.
  @visibleForTesting
  static bool textRewriteDropsProtectedMarkup(String original, String edited) {
    final originalHasTags = _hasHtmlOrXmlTag(original);
    final originalHasFences = _hasFencedBlock(original);
    if (!originalHasTags && !originalHasFences) return false;
    if (originalHasTags && !_hasHtmlOrXmlTag(edited)) return true;
    if (originalHasFences && !_hasFencedBlock(edited)) return true;
    return false;
  }

  static bool _hasHtmlOrXmlTag(String text) {
    return RegExp(r'</?[a-zA-Z][^>]*>').hasMatch(text);
  }

  static bool _hasFencedBlock(String text) {
    return text.contains('```');
  }

  /// True if [original] contained a meta-OOC block (e.g. `<lumiaooc>`,
  /// `<oocnote>`, `<metaooc>`, or any tag whose name contains "ooc") and
  /// [edited] no longer has any. The meta-OOC block is meta-commentary
  /// addressed to the user outside the roleplay — it is NOT prose to be
  /// cleaned. The cleaner is instructed to preserve it verbatim; this guard
  /// catches the case where the cleaner stripped it anyway. The detection is
  /// generalized: any `<...ooc...>` tag (case-insensitive) counts, so custom
  /// meta-personas with custom wrappers are preserved too. See
  /// docs/plans/PLAN_STUDIO_PROMPT_FILTERING.md §Part C.
  @visibleForTesting
  static bool lumiaoocDropped(String original, String edited) {
    final pattern = RegExp(r'<\w*ooc\w*>', caseSensitive: false);
    if (!pattern.hasMatch(original)) return false;
    if (pattern.hasMatch(edited)) return false;
    return true;
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

  Future<AuxCallOutcome> _askLlmForCleanedText({
    required AuxApiConfig config,
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
      bannedWords: settings.postCleanerBannedWords,
      avoidInstructions: settings.postCleanerAvoidInstructions,
      styleInstructions: settings.postCleanerStyleInstructions,
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
        omitReasoning: settings.postCleanerDisableReasoning,
      );
    }

    return _llm.callOnceWithLog(
      config: config,
      prompt: prompt,
      maxTokens: effectiveMaxTokens,
      temperature: settings.postCleanerTemperature,
      timeoutMs: _llm.resolveCleanerTimeout(settings),
      cancelToken: cancelToken,
      omitReasoning: settings.postCleanerDisableReasoning,
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
    String bannedWords = '',
    String avoidInstructions = '',
    String styleInstructions = '',
  }) {
    final rules = broadcastBlocks
        .map((b) => b.trim())
        .where((b) => b.isNotEmpty)
        .toList();

    final buffer = StringBuffer()
      ..writeln(
        'You are a faithful prose editor for a roleplay story. Your job is to '
        'clean up the following assistant response: remove clichés and common '
        'AI-isms, smooth repetitive phrasings, and fix local continuity '
        'errors — while PRESERVING the original voice, energy, imagery, and '
        'emotional texture. The text you receive was written with intent; '
        'your edits should refine it, not flatten it. Keep what is vivid, '
        'specific, and alive; only strip what is generic, overused, or '
        'contradictory.',
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
          'Do not add new content to resolve them. Prefer rephrasing that '
          'preserves the prose\'s voice; only delete or neutralize when '
          'rephrasing would bloat the text.',
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

    // Global prose-guardian style overrides (Marinara `banned`/`avoid`/
    // `prefer` port). User-defined cross-chat style rules that supplement
    // the preset's broadcastBlocks. Only added when at least one field is
    // non-empty. The user sets these once globally (e.g. "never use the
    // word 'ozone'", "avoid starting consecutive responses with dialogue",
    // "prefer terse, hardboiled prose") and they apply to every chat.
    final hasBanned = bannedWords.trim().isNotEmpty;
    final hasAvoid = avoidInstructions.trim().isNotEmpty;
    final hasStyle = styleInstructions.trim().isNotEmpty;
    if (hasBanned || hasAvoid || hasStyle) {
      buffer
        ..writeln(
          'GLOBAL STYLE OVERRIDES (user-defined cross-chat rules — apply '
          'ALONGSIDE the authoritative rules above; do not contradict them):',
        )
        ..writeln();
      if (hasBanned) {
        buffer
          ..writeln(
            'BANNED WORDS (never use these, even if the original has them):',
          )
          ..writeln(bannedWords.trim())
          ..writeln();
      }
      if (hasAvoid) {
        buffer
          ..writeln('AVOID (specific patterns to steer away from):')
          ..writeln(avoidInstructions.trim())
          ..writeln();
      }
      if (hasStyle) {
        buffer
          ..writeln('PREFER (style direction to lean into):')
          ..writeln(styleInstructions.trim())
          ..writeln();
      }
    }

    buffer
      ..writeln('Rules:')
      ..writeln('- Keep the same meaning, events, and character voices.')
      ..writeln(
        '- PRESERVE vivid, original imagery and figurative language. '
        'Metaphors, sensory details, and specific textures are NOT filler '
        '— keep them.',
      )
      ..writeln(
        '- Remove or rephrase ONLY overused AI-isms and clichés (e.g. "a '
        'shiver ran down", "a dance of", "symphony of", "tapestry of", '
        '"couldn\'t help but", "a mix of", "sent shivers", "palpable '
        'tension"). Do NOT remove original metaphors or unique phrasings '
        'just because they are figurative.',
      )
      ..writeln(
        '- Remove redundant repetition of the SAME idea within a few '
        'sentences — but do not compress distinct beats into one.',
      )
      ..writeln('- Do NOT add new content, events, or dialogue.')
      ..writeln(
        '- Do NOT change the POV, tense, or the output language. Preserve the '
        'language and formatting required by the authoritative rules above.',
      )
      ..writeln(
        '- Keep the same approximate length. Do not shorten the text by '
        'removing imagery or descriptive passages — only by removing '
        'genuine filler.',
      )
      ..writeln(
        '- PRESERVE all inline HTML / formatting markup VERBATIM. This includes '
        '<font color="...">, <i>, <b>, <em>, <strong>, <mark>, <sub>, <sup>, '
        'and any other inline tags. These tags carry the user\'s styling '
        '(colored thoughts, colored speech, emphasis) and are NOT markdown to '
        'be stripped. Rewrite the prose INSIDE the tags if needed, but never '
        'remove, move, or alter the tags themselves, and never collapse '
        '<font><i>...</i></font> into plain text. If a sentence with colored '
        'markup is rephrased, keep the tags around the rephrased text in the '
        'same nesting order.',
      )
      ..writeln(
        '- PRESERVE OOC (out-of-character) blocks VERBATIM. OOC blocks are '
        'meta-commentary addressed to the user outside the roleplay — they '
        'are NOT prose to be cleaned. They may be wrapped in `((...))`, '
        '`[OOC: ...]`, `(OOC: ...)`, `((OOC: ...))`, or appear as clearly '
        'meta lines (e.g. "((Ghost in the machine: ...))", narrator notes to '
        'the user, system-style asides). Do not remove, rephrase, translate, '
        'reformat, or alter OOC blocks in any way. Clean only the in-roleplay '
        'prose around them. If the entire response is an OOC block, return it '
        'unchanged.',
      )
      ..writeln(
        '- PRESERVE meta-OOC blocks VERBATIM. A meta-OOC block is any tag '
        'whose name contains "ooc" (e.g. `<lumiaooc>`, `<oocnote>`, '
        '`<metaooc>`, `<sisterooc>`). It is meta-commentary from the '
        'meta-persona to the user outside the roleplay — NOT narrative prose. '
        'Do not rewrite, move, rephrase, translate, reformat, or delete it. '
        'Clean only the in-roleplay prose around it. If the response contains '
        'a meta-OOC block, keep it exactly as-is in the same position.',
      )
      ..writeln(
        '- Return ONLY the cleaned text, no explanation. Inline HTML tags '
        'described above are part of the content, not markdown fences — keep '
        'them. OOC blocks are also part of the content — keep them verbatim. '
        'Do not wrap the output in ``` fences.',
      )
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
          '- Prefer minimal edits: fix the contradiction while keeping the '
          'sentence vivid. Rephrase rather than delete when possible; only '
          'shorten or neutralize when rephrasing would bloat the text.',
        )
        ..writeln(
          '- If correcting a continuity issue requires adding a new '
          'paragraph or scene event, do not fix it — only clean style.',
        )
        ..writeln();
    }

    buffer
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

  /// Applies the cleaned text to the session: appends a blue 'cleaned' agent
  /// swipe carrying [cleanedText] to the last assistant message via
  /// [ChatRepo.appendAgentSwipe]. The original 'final' text remains available
  /// as the parent swipe and is lazy-migrated on first clean.
  ///
  /// [genTime] is the cleaner's own elapsed time (e.g. `"12.3s"`), surfaced as
  /// a per-swipe badge on the cleaned sub-swipe (Fix 3). [tokens] is the
  /// cleaned text's token count (Fix 4). When null, the badge is omitted by
  /// the mapper and renderer — pass non-null to keep the badge visible.
  ///
  /// After the append, clones the parent agent-swipe's tracker snapshot into
  /// the new 'cleaned' anchor so navigating to the blue sub-swipe restores the
  /// correct tracker state (the cleaner rewrites prose, not trackers).
  Future<void> applyCleanedText({
    required String sessionId,
    required String messageId,
    required String cleanedText,
    String? genTime,
    int? tokens,
  }) async {
    final chatRepo = _ref.read(chatRepoProvider);
    final updated = await chatRepo.appendAgentSwipe(
      sessionId: sessionId,
      messageId: messageId,
      content: cleanedText,
      kind: 'cleaned',
      genTime: genTime,
      tokens: tokens,
    );
    if (!updated) return;

    // Refresh cache + reactive streams.
    final session = await chatRepo.getById(sessionId);
    if (session != null) {
      ChatSessionService.updateCache(session);
    }
    _ref.invalidate(chatHistoryProvider);

    // Clone the parent agent-swipe's tracker snapshot into the new 'cleaned'
    // anchor. The cleaner rewrites prose — tracker state is unchanged, so the
    // 'cleaned' sub-swipe inherits the parent 'final's trackers. Read the
    // post-append message to get the exact swipeId + new agentSwipeId (handles
    // lazy-backfill for legacy messages).
    try {
      final msg = session?.messages.where((m) => m.id == messageId).firstOrNull;
      if (msg == null || msg.agentSwipeId <= 0) return;
      final parentAgentSwipeId = msg.agentSwipeId - 1;
      final snapshotRepo = _ref.read(trackerSnapshotRepoProvider);
      final parent = await snapshotRepo.getByAnchor(
        sessionId: sessionId,
        messageId: messageId,
        swipeId: msg.swipeId,
        agentSwipeId: parentAgentSwipeId,
      );
      if (parent != null) {
        await snapshotRepo.upsertTrackers(
          sessionId: sessionId,
          messageId: messageId,
          swipeId: msg.swipeId,
          agentSwipeId: msg.agentSwipeId,
          trackers: parent.trackers,
        );
      }
    } catch (e) {
      debugPrint('[PostCleaner] snapshot clone failed: $e');
    }
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
    String studioApiConfigId = '',
    bool useStudioApiConfigSlot = false,
  }) async {
    if (assistantText.trim().isEmpty) return const [];

    final token = cancelToken ?? CancelToken();
    if (token.isCancelled) return null;

    try {
      final config = useStudioApiConfigSlot || studioApiConfigId.isNotEmpty
          ? await _llm.resolveStudioSlotConfig(
              studioApiConfigId,
              errorLabel: 'post-cleaner-audit',
            )
          : await _llm.resolveConfigForAudit(
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
      if (token.isCancelled || (e is DioException && CancelToken.isCancel(e))) {
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
  final String? model;

  const PostCleanerResult({
    required this.status,
    required this.cleanedText,
    this.originalText,
    this.wasCleaned = false,
    this.error,
    this.attempts = const [],
    this.totalElapsedMs = 0,
    this.model,
  });
}
