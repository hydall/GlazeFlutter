import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../db/repositories/memory_consolidation_repo.dart';
import '../models/memory_book.dart';
import '../models/memory_graph.dart';
import '../models/pipeline_settings.dart';
import '../utils/time_helpers.dart';
import 'transport/chat_transport_request.dart';
import 'transport/llm_protocol.dart';
import 'transport/transport_factory.dart';

/// Consolidation service (Phase G5). Tier 1 = scene summaries, Tier 2 = arc summaries.
///
/// Opt-in LLM feature with separate model config. On failure: saves error
/// status, shows to user with retry option (decision G). NO deterministic
/// fallback, NO silent skip.
class MemoryConsolidationService {
  final MemoryConsolidationRepo _repo;

  MemoryConsolidationService(this._repo);

  /// Consolidate unconsolidated entries for a session.
  /// Returns the number of consolidations created (0 if none or disabled).
  Future<int> consolidateSession(
    String sessionId,
    List<MemoryEntry> entries, {
    required PipelineSettings settings,
  }) async {
    if (!settings.consolidationEnabled) return 0;

    final active = entries
        .where((e) => e.status == 'active' && e.content.trim().isNotEmpty)
        .toList();
    if (active.length < settings.consolidationThreshold) return 0;

    // Check for existing Tier 1 consolidations to avoid re-processing
    final existing = await _repo.getBySessionId(sessionId, tier: 1);
    final consolidatedEntryIds = <String>{};
    for (final c in existing) {
      consolidatedEntryIds.addAll(c.sourceEntryIds);
    }

    final unconsolidated = active
        .where((e) => !consolidatedEntryIds.contains(e.id))
        .toList();
    if (unconsolidated.length < settings.consolidationThreshold) return 0;

    var created = 0;
    final now = currentTimestampSeconds();

    // Group entries by message range (5-10 per group)
    final groups = _groupEntries(unconsolidated, groupSize: 7);

    for (final group in groups) {
      if (group.length < 3) continue; // Skip tiny groups

      final entryIds = group.map((e) => e.id).toList();
      final consolidationId = 'consol_${sessionId}_${now}_$created';

      try {
        final result = await _callConsolidationLlm(
          group,
          settings: settings,
        );

        if (result == null) {
          await _repo.upsert(MemoryConsolidation(
            id: consolidationId,
            chatSessionId: sessionId,
            tier: 1,
            title: 'Consolidation failed',
            summary: '',
            sourceEntryIds: entryIds,
            messageRangeStart: group.first.messageRange?.start ?? 0,
            messageRangeEnd: group.last.messageRange?.end ?? 0,
            status: 'error',
            errorMessage: 'LLM returned empty response',
            sourceModel: settings.consolidationModel,
            createdAt: now,
            updatedAt: now,
          ));
          continue;
        }

          await _repo.upsert(MemoryConsolidation(
            id: consolidationId,
            chatSessionId: sessionId,
            tier: 1,
            title: (result['title'] as String?) ?? 'Scene summary',
            summary: (result['summary'] as String?) ?? '',
          sourceEntryIds: entryIds,
          messageRangeStart: group.first.messageRange?.start ?? 0,
          messageRangeEnd: group.last.messageRange?.end ?? 0,
          emotionalTags: _stringList(result['emotionalTags']),
          sourceModel: settings.consolidationModel,
          status: 'ok',
          createdAt: now,
          updatedAt: now,
        ));
        created++;
      } catch (e) {
        // Decision G: save error, show to user with retry
        await _repo.upsert(MemoryConsolidation(
          id: consolidationId,
          chatSessionId: sessionId,
          tier: 1,
          title: 'Consolidation error',
          summary: '',
          sourceEntryIds: entryIds,
          messageRangeStart: group.first.messageRange?.start ?? 0,
          messageRangeEnd: group.last.messageRange?.end ?? 0,
          status: 'error',
          errorMessage: e.toString(),
          sourceModel: settings.consolidationModel,
          createdAt: now,
          updatedAt: now,
        ));
      }
    }

    // Tier 2: if 3+ Tier 1 accumulated, create arc summary
    if (created > 0 || existing.isNotEmpty) {
      final tier1 = await _repo.getBySessionId(sessionId, tier: 1);
      final okTier1 = tier1.where((c) => c.status == 'ok').toList();
      if (okTier1.length >= 3) {
        final arcId = 'arc_${sessionId}_$now';
        try {
          final arcResult = await _callArcLlm(okTier1, settings: settings);
          if (arcResult != null) {
            await _repo.upsert(MemoryConsolidation(
              id: arcId,
              chatSessionId: sessionId,
              tier: 2,
              title: (arcResult['title'] as String?) ?? 'Arc summary',
              summary: (arcResult['summary'] as String?) ?? '',
              sourceEntryIds: okTier1.map((c) => c.id).toList(),
              messageRangeStart: okTier1.first.messageRangeStart,
              messageRangeEnd: okTier1.last.messageRangeEnd,
              status: 'ok',
              sourceModel: settings.consolidationModel,
              createdAt: now,
              updatedAt: now,
            ));
            created++;
          }
        } catch (e) {
          await _repo.upsert(MemoryConsolidation(
            id: arcId,
            chatSessionId: sessionId,
            tier: 2,
            title: 'Arc consolidation error',
            summary: '',
            status: 'error',
            errorMessage: e.toString(),
            sourceModel: settings.consolidationModel,
            createdAt: now,
            updatedAt: now,
          ));
        }
      }
    }

    return created;
  }

  Future<Map<String, dynamic>?> _callConsolidationLlm(
    List<MemoryEntry> entries, {
    required PipelineSettings settings,
  }) async {
    final content = entries
        .map((e) => '--- ${e.title} ---\n${e.content}')
        .join('\n\n');

    final prompt = '''Summarize these memory entries into a scene summary. Return ONLY a JSON object:
{"title": "brief scene title", "summary": "2-3 sentence summary of what happened", "emotionalTags": ["tag1", "tag2"]}

Memory entries:
$content''';

    return _callLlm(prompt, settings);
  }

  Future<Map<String, dynamic>?> _callArcLlm(
    List<MemoryConsolidation> tier1Summaries, {
    required PipelineSettings settings,
  }) async {
    final content = tier1Summaries
        .map((c) => '--- $c.title ---\n${c.summary}')
        .join('\n\n');

    final prompt = '''Summarize these scene summaries into an arc summary. Return ONLY a JSON object:
{"title": "arc title", "summary": "3-5 sentence arc summary covering the major developments"}

Scene summaries:
$content''';

    return _callLlm(prompt, settings);
  }

  Future<Map<String, dynamic>?> _callLlm(
    String prompt,
    PipelineSettings settings,
  ) async {
    final isCustom = settings.consolidationSource == 'custom';
    String endpoint;
    String apiKey;
    String model;
    String protocol;

    if (isCustom) {
      endpoint = settings.consolidationEndpoint;
      apiKey = settings.consolidationApiKey;
      model = settings.consolidationModel;
      protocol = LlmProtocol.openai;
    } else {
      throw Exception('Consolidation with source "current" requires caller to resolve config');
    }

    if (endpoint.isEmpty || model.isEmpty) {
      throw Exception('Consolidation API not configured');
    }

    final completer = Completer<String>();
    final transport = pickChatTransport(protocol);

    unawaited(transport.stream(
      request: ChatTransportRequest(
        endpoint: endpoint,
        apiKey: apiKey,
        model: model,
        messages: [
          {'role': 'user', 'content': prompt},
        ],
        maxTokens: 1000,
        temperature: 0.3,
        topP: 1.0,
        stream: false,
      ),
      cancelToken: CancelToken(),
      onComplete: (text, _, {rawResponseJson}) {
        if (!completer.isCompleted) completer.complete(text);
      },
      onError: (error) {
        if (!completer.isCompleted) completer.completeError(error);
      },
    ));

    final raw = await completer.future
        .timeout(Duration(milliseconds: settings.consolidationTimeoutMs));
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) return decoded;
    return null;
  }

  List<List<MemoryEntry>> _groupEntries(
    List<MemoryEntry> entries, {
    required int groupSize,
  }) {
    final groups = <List<MemoryEntry>>[];
    for (var i = 0; i < entries.length; i += groupSize) {
      final end = (i + groupSize).clamp(0, entries.length);
      groups.add(entries.sublist(i, end));
    }
    return groups;
  }

  List<String> _stringList(Object? raw) {
    if (raw is! List) return const [];
    return raw.whereType<String>().toList();
  }
}
