import '../models/memory_book.dart';
import 'memory_agentic_policy.dart';
import 'memory_selector.dart';

/// Tool definition for `searchMemory` — the only read-only agentic tool in Phase 10.
///
/// The tool lets an LLM request bounded memory retrieval from Memory Book.
/// The app enforces caps, source-window exclusion, and permissions.
class MemoryAgenticToolDefinition {
  /// OpenAI-format tool definition for `searchMemory`.
  static Map<String, dynamic> searchMemory() {
    return {
      'type': 'function',
      'function': {
        'name': 'searchMemory',
        'description':
            'Search the Memory Book for relevant past memories. '
            'Returns candidate memory titles and scores. '
            'Use this when you need to recall specific past events, '
            'promises, relationships, or details.',
        'parameters': {
          'type': 'object',
          'properties': {
            'query': {
              'type': 'string',
              'description': 'Search query describing what you want to remember',
            },
            'maxResults': {
              'type': 'integer',
              'description': 'Maximum number of results (default 5, max 10)',
              'default': 5,
            },
          },
          'required': ['query'],
        },
      },
    };
  }

  /// All available read-only tool definitions.
  static List<Map<String, dynamic>> readOnlyTools() => [searchMemory()];

  /// All available tool definitions including write tools (when enabled).
  /// Phase 10 only exposes read-only tools.
  static List<Map<String, dynamic>> forPolicy(MemoryAgenticPolicy policy) {
    if (!policy.settings.enabled) return const [];
    if (policy.settings.readOnly) return readOnlyTools();
    // Write tools would be added here in a future phase
    return readOnlyTools();
  }
}

/// Result of a `searchMemory` tool call.
class MemorySearchResult {
  final List<MemorySearchHit> hits;
  final String? error;

  const MemorySearchResult({this.hits = const [], this.error});

  bool get isEmpty => hits.isEmpty && (error == null || error!.isEmpty);

  Map<String, dynamic> toJson() => {
        'hits': hits.map((h) => h.toJson()).toList(),
        if (error != null) 'error': error,
      };
}

class MemorySearchHit {
  final String entryId;
  final String title;
  final double score;
  final List<String> matchedKeys;
  final int tokenCost;

  const MemorySearchHit({
    required this.entryId,
    required this.title,
    required this.score,
    this.matchedKeys = const [],
    this.tokenCost = 0,
  });

  Map<String, dynamic> toJson() => {
        'entryId': entryId,
        'title': title,
        'score': score.toStringAsFixed(2),
        if (matchedKeys.isNotEmpty) 'matchedKeys': matchedKeys,
        if (tokenCost > 0) 'tokenCost': tokenCost,
      };
}

/// Handler for `searchMemory` tool calls. Bounded retrieval from Memory Book.
///
/// Enforces:
/// - [MemoryAgenticPolicy] permissions (read-only default)
/// - Max results cap (10)
/// - Source-window exclusion
/// - Returns only metadata (id, title, score, keys), NOT full content
class MemoryAgenticToolHandler {
  final MemoryAgenticPolicy policy;

  const MemoryAgenticToolHandler(this.policy);

  /// Execute a `searchMemory` tool call.
  MemorySearchResult searchMemory({
    required List<MemoryEntry> entries,
    required String query,
    required Set<String> visibleMessageIds,
    int maxResults = 5,
    Map<String, double> vectorScores = const {},
    Map<String, List<String>> keywordMatchedTerms = const {},
  }) {
    final decision = policy.canUse(MemoryAgenticTool.inspectContext);
    if (!decision.allowed) {
      return MemorySearchResult(error: decision.reason);
    }

    final capped = maxResults.clamp(1, 10);
    final active = entries
        .where((e) =>
            e.status == 'active' && e.content.trim().isNotEmpty)
        .toList();
    if (active.isEmpty) return const MemorySearchResult();

    // Run deterministic selector to get scored candidates
    final selection = MemorySelector.select(
      MemorySelectionInput(
        entries: active,
        vectorScores: vectorScores,
        keywordMatchedTerms: keywordMatchedTerms,
        visibleMessageIds: visibleMessageIds,
        maxInjectedEntries: capped,
        sourceWindowExclusion: true,
        diversityAware: true,
        recencyBoost: true,
        importanceBoost: true,
      ),
    );

    final hits = selection.allScores
        .where((s) => !s.excludedBySourceWindow && s.score > 0)
        .take(capped)
        .map((s) => MemorySearchHit(
              entryId: s.entry.id,
              title: s.entry.title,
              score: s.score,
              matchedKeys: s.matchedKeys,
              tokenCost: MemorySelector.tokenCost(s.entry),
            ))
        .toList();

    return MemorySearchResult(hits: hits);
  }
}
