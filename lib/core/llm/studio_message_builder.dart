import '../models/studio_config.dart';
import 'beauty_shard_instruction.dart';
import 'history_assembler.dart';
import 'macro_engine.dart';
import 'prompt_builder.dart';
import 'studio_brief_deduper.dart';
import 'studio_context_bucketizer.dart';
import 'studio_prompt_text.dart';
import 'studio_request_preset.dart';
import 'studio_stage_brief.dart';

/// Builds the per-agent, batch, and final-generator message lists for the
/// Studio chat-time pipeline. Extracted from `MemoryStudioService` (plan §2.7).
///
/// Owns the macro-expansion, history-limiting, role-normalization, and
/// post-gen `<assistant_response>` injection concerns. Pure aside from the
/// injected specialists (`StudioContextBucketizer`, `StudioPromptText`,
/// `StudioBriefDeduper`); behavior preserved verbatim.
class StudioMessageBuilder {
  final StudioContextBucketizer _bucketizer;
  final StudioPromptText _promptText;
  final StudioBriefDeduper _briefDeduper;

  const StudioMessageBuilder(
    this._bucketizer,
    this._promptText,
    this._briefDeduper,
  );

  /// Build the message list for a single agent run (pre-gen tracker,
  /// post-processing tracker, or final generator). [mainResponse] non-empty
  /// marks a post-processing tracker (Feature 6): the generator's reply is
  /// appended as an `<assistant_response>` block at the END of the list so
  /// the tracker can rewrite it.
  List<Map<String, dynamic>> buildAgentMessages({
    required StudioAgent agent,
    required PromptResult promptResult,
    required PromptPayload promptPayload,
    required StudioConfig config,
    required List<StudioStageBrief> priorBriefs,
    required bool isFinalResponse,
    String mainResponse = '',
    int finalContextOverride = 0,
  }) {
    final studioPreset = studioRequestPresetById(
      isFinalResponse ? config.finalStudioPresetId : config.agentStudioPresetId,
      finalPreset: isFinalResponse,
      overrides: config.studioPresetOverrides,
    );
    final context = _bucketizer.bucketize(
      promptResult,
      promptPayload: promptPayload,
      studioConfig: config,
    );
    final blocks = studioPreset.blocks.where((b) => b.enabled).toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    final messages = <Map<String, dynamic>>[];

    for (final block in blocks) {
      switch (block.kind) {
        case 'agent_instruction':
          // Each PromptShardBlock becomes its own API message (cache-friendly,
          // structured — see docs/plans/PLAN_STUDIO_SHARD_BLOCKS.md). Macro
          // expansion is applied per-block so `{{char}}`/`{{user}}` resolve.
          for (final shard in agent.promptShard) {
            final expanded = _expandStudioBlockContent(
              shard.content,
              promptPayload: promptPayload,
              promptResult: promptResult,
              context: context,
            ).trim();
            if (expanded.isEmpty) continue;
            messages.add({
              'role': _normalizeInstructionRole(
                shard.role.isNotEmpty ? shard.role : agent.role,
              ),
              'content': expanded,
            });
          }
          // Preset's agent_instruction block content + runtime envelope +
          // final-responder contract follow as the final control message.
          final control = StringBuffer();
          control.writeln(
            _expandStudioBlockContent(
              block.content,
              promptPayload: promptPayload,
              promptResult: promptResult,
              context: context,
            ).trim(),
          );
          if (!isFinalResponse) {
            control
              ..writeln()
              ..writeln(_promptText.intermediateRuntimeEnvelope(agent));
          }
          if (isFinalResponse) {
            control
              ..writeln()
              ..writeln(_promptText.finalBriefUsageNote());
            final styleContract = _promptText.finalHardStyleContract(config);
            if (styleContract.isNotEmpty) {
              control
                ..writeln()
                ..writeln(styleContract);
            }
            if (_hasEnabledBeautyShard(config)) {
              final macroCtx = MacroContext(
                charName: promptPayload.character.name,
                userName: promptPayload.persona?.name ?? 'User',
                personaPrompt: promptPayload.persona?.prompt,
                sessionVars: promptPayload.sessionVars,
                globalVars: promptPayload.globalVars,
                charId: promptPayload.character.id,
                sessionId: promptPayload.sessionId ?? '',
              );
              final expanded = replaceMacros(
                beautyShardFinalMarkerContract,
                macroCtx,
              ).text;
              control
                ..writeln()
                ..writeln(expanded);
            }
          }
          final controlText = control.toString().trim();
          if (controlText.isNotEmpty) {
            messages.add({
              'role': _normalizeInstructionRole(
                block.role.isNotEmpty ? block.role : agent.role,
              ),
              'content': controlText,
            });
          }
          break;
        case 'previous_agents':
          if (!isFinalResponse) break;
          final sanitized = priorBriefs
              .where((b) => b.brief.trim().isNotEmpty)
              .map((b) => _briefDeduper.sanitizePriorBriefForFinal(b, config))
              .toList();
          final deduped = _briefDeduper.dedupePriorBriefs(sanitized);
          messages.addAll(
            deduped
                .where((b) => b.brief.trim().isNotEmpty)
                .map(
                  (b) => {
                    'role': _normalizeInstructionRole(block.role),
                    'content': 'Studio agent brief: ${b.agentName}\n${b.brief}',
                  },
                ),
          );
          break;
        case 'static_context':
          messages.addAll(context.staticContext.map((m) => m.toApiMap()));
          break;
        case 'chat_history':
          final history = isFinalResponse
              ? limitFinalHistory(context.history, config,
                  pipelineOverride: finalContextOverride)
              : limitTrackerHistory(context.history, agent.contextSize);
          messages.addAll(history.map((m) => m.toApiMap()));
          break;
        case 'dynamic_context':
          messages.addAll(context.dynamicContext.map((m) => m.toApiMap()));
          break;
        default:
          final promptMessages = context.messagesForKind(block.kind);
          if (promptMessages.isNotEmpty) {
            messages.addAll(promptMessages.map((m) => m.toApiMap()));
            break;
          }
          final content = _expandStudioBlockContent(
            block.content,
            promptPayload: promptPayload,
            promptResult: promptResult,
            context: context,
          ).trim();
          if (content.isNotEmpty) {
            messages.add({
              'role': _normalizeInstructionRole(block.role),
              'content': content,
            });
          }
      }
    }

    // Feature 6 — post-processing trackers receive the generator's response
    // as an `<assistant_response>` block appended at the END of the message
    // list. This is the Marinara `context.mainResponse` injection: the
    // tracker's prompt shard instructs it to rewrite/edit the response, and
    // the response itself is provided here as read-only source material. We
    // append rather than prepend so the tracker's instructions (earlier
    // blocks) come first and the response-to-edit is the last thing the
    // model sees before generating.
    if (mainResponse.trim().isNotEmpty) {
      messages.add({
        'role': 'user',
        'content':
            '<assistant_response>\n${mainResponse.trim()}\n</assistant_response>\n\n'
            'The text above inside <assistant_response> is the generator\'s '
            'current reply. Edit, rewrite, or fix it according to your '
            'instructions. Output ONLY the final rewritten reply (no '
            'explanations, no <assistant_response> wrapper, no markdown '
            'fences). If no edit is needed, output the text verbatim.',
      });
    }

    return messages;
  }

  /// Shared messages for a batch: `static_context` + `dynamic_context` +
  /// `chat_history` (trimmed to [batchContextSize]). The per-agent
  /// `agent_instruction` blocks are NOT here — they go into `<agent_task>`
  /// XML in the batch system prompt.
  ///
  /// Phase 6.1 — cache-friendly order: `static_context` (char card, persona,
  /// scenario — stable across turns) FIRST, then `dynamic_context` (MemoryBook
  /// injection, worldInfo, summary — stable within a scene), then
  /// `chat_history` (volatile, last). Combined with the batch system prompt
  /// layout (`<role>` + `<lore>` prefix, `<agents>` tail), this gives the
  /// provider's prompt cache a long stable prefix to hit on subsequent turns.
  List<Map<String, dynamic>> buildSharedBatchMessages({
    required StudioConfig config,
    required StudioContextBuckets context,
    required PromptPayload promptPayload,
    required PromptResult promptResult,
    required int batchContextSize,
  }) {
    final messages = <Map<String, dynamic>>[];
    messages.addAll(context.staticContext.map((m) => m.toApiMap()));
    messages.addAll(context.dynamicContext.map((m) => m.toApiMap()));
    final history = limitTrackerHistory(context.history, batchContextSize);
    messages.addAll(history.map((m) => m.toApiMap()));
    return messages;
  }

  /// Per-agent task text: the agent's `promptShard` + the preset's
  /// `agent_instruction` block content + the runtime envelope (lane contract).
  /// Already macro-expanded.
  String buildPerAgentTaskText({
    required StudioAgent agent,
    required StudioConfig config,
    required PromptResult promptResult,
    required PromptPayload promptPayload,
    required StudioContextBuckets context,
  }) {
    final studioPreset = studioRequestPresetById(
      config.agentStudioPresetId,
      finalPreset: false,
      overrides: config.studioPresetOverrides,
    );
    final blocks =
        studioPreset.blocks
            .where((b) => b.enabled && b.kind == 'agent_instruction')
            .toList()
          ..sort((a, b) => a.order.compareTo(b.order));
    final buf = StringBuffer();
    final shardParts = <String>[];
    for (final shard in agent.promptShard) {
      final expanded = _expandStudioBlockContent(
        shard.content,
        promptPayload: promptPayload,
        promptResult: promptResult,
        context: context,
      ).trim();
      if (expanded.isNotEmpty) shardParts.add(expanded);
    }
    final promptShard = shardParts.join('\n\n');
    if (promptShard.isNotEmpty) {
      buf.writeln(promptShard);
      buf.writeln();
    }
    for (final block in blocks) {
      final content = _expandStudioBlockContent(
        block.content,
        promptPayload: promptPayload,
        promptResult: promptResult,
        context: context,
      ).trim();
      if (content.isNotEmpty) {
        buf.writeln(content);
        buf.writeln();
      }
    }
    buf.writeln(_promptText.intermediateRuntimeEnvelope(agent));
    return buf.toString().trim();
  }

  /// Role text for the `<role>` element: the shared role/instruction text
  /// from the preset's non-`agent_instruction` blocks (e.g. global rules,
  /// output language). Kept short — most guidance goes into per-agent
  /// `<agent_task>`.
  String batchRoleText(
    StudioConfig config,
    StudioContextBuckets context,
    PromptPayload promptPayload,
    PromptResult promptResult,
  ) {
    final studioPreset = studioRequestPresetById(
      config.agentStudioPresetId,
      finalPreset: false,
      overrides: config.studioPresetOverrides,
    );
    final blocks =
        studioPreset.blocks
            .where((b) => b.enabled && b.kind != 'agent_instruction')
            .where((b) => b.kind != 'static_context')
            .where((b) => b.kind != 'chat_history')
            .where((b) => b.kind != 'dynamic_context')
            .toList()
          ..sort((a, b) => a.order.compareTo(b.order));
    final buf = StringBuffer();
    for (final block in blocks) {
      final promptMessages = context.messagesForKind(block.kind);
      if (promptMessages.isNotEmpty) {
        for (final m in promptMessages) {
          if (m.content.isNotEmpty) buf.writeln(m.content);
        }
        continue;
      }
      final content = _expandStudioBlockContent(
        block.content,
        promptPayload: promptPayload,
        promptResult: promptResult,
        context: context,
      ).trim();
      if (content.isNotEmpty) {
        buf.writeln(content);
      }
    }
    return buf.toString().trim();
  }

  /// Cap how many trailing chat messages reach the FINAL responder.
  ///
  /// Intermediate agents always analyze the full transcript; the final writer
  /// is intentionally limited (default 15) so it relies on the compact agent
  /// briefs instead of re-reading the whole history. We keep the most recent
  /// [StudioConfig.maxFinalHistoryMessages] messages, which always preserves
  /// the current user turn (it is last). 0 (or negative) means no limit.
  List<PromptMessage> limitFinalHistory(
    List<PromptMessage> history,
    StudioConfig config, {
    int pipelineOverride = 0,
  }) {
    final limit = pipelineOverride > 0
        ? pipelineOverride
        : config.maxFinalHistoryMessages;
    if (limit <= 0 || history.length <= limit) return history;
    final trimmed = history.sublist(history.length - limit);
    return trimmed;
  }

  /// Hard cap on tracker context size (Marinara MAX_AGENT_CONTEXT_MESSAGES).
  static const maxTrackerContextSize = 200;

  /// Trim trailing chat history for a tracker (intermediate agent).
  ///
  /// Returns the last [contextSize] messages (clamped to
  /// `1..[maxTrackerContextSize]`), each truncated via
  /// [truncateAgentText] and stripped of HTML via [stripHtmlTags].
  ///
  /// Only the `chat_history` block is trimmed — `static_context` (card,
  /// persona, lorebooks) and `dynamic_context` (memory, summary, worldInfo)
  /// remain untouched. MemoryBook injection survives the refactor because it
  /// flows through `dynamic_context`, not `chat_history`. See
  /// docs/PLAN_AGENTIC_STUDIO.md Phase 3.
  List<PromptMessage> limitTrackerHistory(
    List<PromptMessage> history,
    int contextSize,
  ) {
    final normalized = contextSize.clamp(1, maxTrackerContextSize);
    if (history.length <= normalized) {
      return history
          .map(
            (m) => PromptMessage(
              role: m.role,
              content: truncateAgentText(stripHtmlTags(m.content), 2000),
            ),
          )
          .toList();
    }
    final trimmed = history.sublist(history.length - normalized);
    return trimmed
        .map(
          (m) => PromptMessage(
            role: m.role,
            content: truncateAgentText(stripHtmlTags(m.content), 2000),
          ),
        )
        .toList();
  }

  /// Port of Marinara `truncateAgentText`. If the text is longer than
  /// [maxChars], keeps the head (40%) + a trim marker + the tail (60%),
  /// preserving both the beginning and the end of the message. Character
  /// counting uses `String.runes` for Unicode/emoji safety.
  static const _trimMarker =
      '\n\n[Trimmed to keep this agent request compact]\n\n';

  String truncateAgentText(String text, int maxChars) {
    if (text.length <= maxChars) return text;
    final runes = text.runes.toList();
    if (runes.length <= maxChars) return text;
    final headCount = (maxChars * 0.4).round();
    final tailCount = maxChars - headCount;
    final head = String.fromCharCodes(runes.sublist(0, headCount));
    final tail = String.fromCharCodes(runes.sublist(runes.length - tailCount));
    return '$head$_trimMarker$tail';
  }

  /// Port of Marinara `stripHtmlTags`. Removes HTML/XML-like tags, collapses
  /// 3+ newlines to 2, trims. Conservative: only strips tags that start with
  /// a letter (avoids eating `==...==` custom markers or fenced code).
  static final _htmlTagRegex = RegExp(r'</?[a-zA-Z][^>]*>');
  static final _multiNewlineRegex = RegExp(r'\n{3,}');

  String stripHtmlTags(String text) {
    final stripped = text.replaceAll(_htmlTagRegex, '');
    final collapsed = stripped.replaceAll(_multiNewlineRegex, '\n\n');
    return collapsed.trim();
  }

  String _expandStudioBlockContent(
    String content, {
    required PromptPayload promptPayload,
    required PromptResult promptResult,
    required StudioContextBuckets context,
  }) {
    if (!content.contains('{')) return content;
    final macroCtx = MacroContext(
      charName: promptPayload.character.name,
      charDescription: promptPayload.character.description,
      charScenario: promptPayload.character.scenario,
      charPersonality: promptPayload.character.personality,
      charMesExample: promptPayload.character.mesExample,
      userName: promptPayload.persona?.name ?? 'User',
      personaPrompt: promptPayload.persona?.prompt,
      reasoningStart: promptPayload.preset?.reasoningStart,
      reasoningEnd: promptPayload.preset?.reasoningEnd,
      sessionVars: promptResult.sessionVars,
      globalVars: promptResult.globalVars,
      charId: promptPayload.character.id,
      sessionId: promptPayload.sessionId ?? '',
      summaryContent:
          promptPayload.summaryContent ?? context.joinKind('summary'),
      memoryContent:
          promptPayload.memoryMacroContent ??
          promptPayload.memoryContent ??
          context
              .joinKind('memory')
              .ifBlank(context.taggedDynamicContent('summary')),
      lorebooksContent:
          [
                context.joinKind('worldInfoBefore'),
                context.joinKind('worldInfoAfter'),
              ]
              .where((value) => value.trim().isNotEmpty)
              .join('\n\n')
              .ifBlank(context.taggedDynamicContent('lorebooks')),
      guidanceText: promptPayload.guidanceText,
      macroName: promptPayload.character.macroName,
      arcContent: promptPayload.arcContent,
      entitiesContent: promptPayload.entitiesContent,
    );
    return replaceMacros(content, macroCtx).text;
  }

  /// Normalize the role of a preset/shard INSTRUCTION block (not a chat
  /// history message). Preset blocks sometimes carry `role: "user"` (e.g. the
  /// Shino preset marks all instruction blocks as user), but in the Studio
  /// pipeline these are INSTRUCTIONS to the model, not user dialogue turns.
  /// Treating them as user messages can confuse models (especially Claude,
  /// which treats user messages as human turns to respond to, not instructions
  /// to follow). Force instruction blocks to `system` so the model treats them
  /// as authoritative directives.
  ///
  /// Assistant-role blocks (prefill) are always forced to `system` here too.
  /// They are already dropped from routing at build time
  /// (`studio_decomposition_service.dart`), but if any slip through (e.g. via
  /// a preset override or request-preset block), they must NOT become
  /// assistant messages mid-conversation — that would break the conversation
  /// flow. Assistant prefill is a transport-layer concern (API config prefix
  /// field), not a preset-block concern.
  ///
  /// Chat history (`chat_history` kind) and dynamic context (`dynamic_context`
  /// kind) go through `toApiMap()` and preserve their original user/assistant
  /// roles — those ARE conversation turns, not instructions.
  String _normalizeInstructionRole(String role) {
    return 'system';
  }

  bool _hasEnabledBeautyShard(StudioConfig config) {
    return config.agents.any((agent) {
      if (!agent.enabled) return false;
      final id = agent.id.toLowerCase();
      final name = agent.name.toLowerCase();
      final text = '$id\n$name';
      return id == 'beauty' ||
          text.contains('_beauty_') ||
          text.contains('beauty shard') ||
          name == 'beauty';
    });
  }
}

extension _BlankStringFallback on String {
  String ifBlank(String fallback) => trim().isEmpty ? fallback : this;
}
