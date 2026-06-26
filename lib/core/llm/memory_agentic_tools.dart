import '../models/memory_book.dart';
import 'memory_agentic_policy.dart';
import 'memory_selector.dart';

/// Tool definitions for the agentic memory system.
///
/// Read-only tools (`searchMemory`) are always available when agentic mode is
/// on. Write tools (`writeMemory`, `updateTracker`) are only exposed when the
/// policy allows writes — see [MemoryAgenticPolicy.settings.writeToolsEnabled].
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

  /// Tool definition for `updateTracker` — writes a lightweight key-value
  /// tracker (e.g. 'mood: happy', 'inventory: chip in pocket').
  static Map<String, dynamic> updateTracker() {
    return {
      'type': 'function',
      'function': {
        'name': 'updateTracker',
        'description':
            'Write or update a tracker — a lightweight key-value state '
            'variable that persists across turns. Use for facts that should '
            'survive context truncation: relationship status, inventory, '
            'location, ongoing promises, emotional state.',
        'parameters': {
          'type': 'object',
          'properties': {
            'name': {
              'type': 'string',
              'description':
                  'Tracker name (e.g. "mood", "location", "relationship_status")',
            },
            'value': {
              'type': 'string',
              'description':
                  'Tracker value (e.g. "happy", "tavern", "allies")',
            },
            'scope': {
              'type': 'string',
              'description':
                  'Tracker scope: "chat" (session-scoped, default), "character", "global"',
              'default': 'chat',
            },
          },
          'required': ['name', 'value'],
        },
      },
    };
  }

  /// Tool definition for `writeMemory` — creates a pending memory draft.
  /// Drafts require human approval before becoming active memory entries.
  static Map<String, dynamic> writeMemory() {
    return {
      'type': 'function',
      'function': {
        'name': 'writeMemory',
        'description':
            'Create a pending memory draft from a significant event or fact. '
            'The draft will be reviewed by the user before becoming an active '
            'memory entry. Use for important events, promises, revelations, '
            'relationship changes — NOT for transient state (use updateTracker for that).',
        'parameters': {
          'type': 'object',
          'properties': {
            'title': {
              'type': 'string',
              'description':
                  'Short title for the memory (e.g. "Lucy reveals the chip")',
            },
            'content': {
              'type': 'string',
              'description':
                  'Full memory content — what happened, who was involved, why it matters',
            },
            'keys': {
              'type': 'array',
              'items': {'type': 'string'},
              'description':
                  'Search keys for retrieval (e.g. ["Lucy", "chip", "secret"])',
            },
          },
          'required': ['title', 'content'],
        },
      },
    };
  }

  /// All available write tool definitions.
  static List<Map<String, dynamic>> writeTools() =>
      [updateTracker(), writeMemory()];

  /// All available tool definitions for the given policy.
  /// Read-only tools are always included when agentic mode is enabled.
  /// Write tools are only included when the policy allows writes.
  static List<Map<String, dynamic>> forPolicy(MemoryAgenticPolicy policy) {
    if (!policy.settings.enabled) return const [];
    if (policy.settings.readOnly || !policy.settings.writeToolsEnabled) {
      return readOnlyTools();
    }
    return [...readOnlyTools(), ...writeTools()];
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

    final queryTerms = _queryTerms(query);
    final queryScores = <String, double>{};
    final queryMatches = <String, List<String>>{};
    if (queryTerms.isNotEmpty) {
      for (final entry in active) {
        final matches = _queryMatches(entry, queryTerms);
        if (matches.isEmpty) continue;
        queryScores[entry.id] =
            (vectorScores[entry.id] ?? 0) + matches.length.toDouble();
        queryMatches[entry.id] = matches;
      }
    }

    final effectiveVectorScores = queryScores.isEmpty
        ? vectorScores
        : {...vectorScores, ...queryScores};
    final effectiveKeywordMatches = queryMatches.isEmpty
        ? keywordMatchedTerms
        : {...keywordMatchedTerms, ...queryMatches};

    // Run deterministic selector to get scored candidates
    final selection = MemorySelector.select(
      MemorySelectionInput(
        entries: active,
        vectorScores: effectiveVectorScores,
        keywordMatchedTerms: effectiveKeywordMatches,
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

  static Set<String> _queryTerms(String query) {
    return query
        .toLowerCase()
        .split(RegExp(r'[^\p{L}\p{N}_]+', unicode: true))
        .where((term) => term.length >= 3)
        .toSet();
  }

  static List<String> _queryMatches(MemoryEntry entry, Set<String> terms) {
    final haystack = [
      entry.title,
      entry.content,
      entry.arc,
      ...entry.keys,
    ].join(' ').toLowerCase();
    return terms.where(haystack.contains).toList(growable: false);
  }
}

// ---------------------------------------------------------------------------
// Write tool result types (Stage 1 — agentic write-loop)
// ---------------------------------------------------------------------------

/// A single tracker write requested by the agent.
class TrackerWriteRequest {
  final String name;
  final String value;
  final String scope;

  const TrackerWriteRequest({
    required this.name,
    required this.value,
    this.scope = 'chat',
  });

  factory TrackerWriteRequest.fromJson(Map<String, dynamic> json) {
    return TrackerWriteRequest(
      name: (json['name'] as String?) ?? '',
      value: (json['value'] as String?) ?? '',
      scope: (json['scope'] as String?) ?? 'chat',
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'value': value,
        'scope': scope,
      };
}

/// A single memory draft write requested by the agent.
class MemoryWriteRequest {
  final String title;
  final String content;
  final List<String> keys;

  const MemoryWriteRequest({
    required this.title,
    required this.content,
    this.keys = const [],
  });

  factory MemoryWriteRequest.fromJson(Map<String, dynamic> json) {
    final rawKeys = json['keys'];
    return MemoryWriteRequest(
      title: (json['title'] as String?) ?? '',
      content: (json['content'] as String?) ?? '',
      keys: rawKeys is List
          ? rawKeys.map((e) => e.toString()).toList()
          : <String>[],
    );
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        'content': content,
        'keys': keys,
      };
}

/// Result of executing a batch of tracker writes.
class TrackerWriteResult {
  final int written;
  final int denied;
  final List<String> errors;
  final List<TrackerWriteRequest> requests;

  const TrackerWriteResult({
    this.written = 0,
    this.denied = 0,
    this.errors = const [],
    this.requests = const [],
  });

  bool get isEmpty => written == 0 && denied == 0;
}

/// Result of executing a batch of memory draft writes.
class MemoryWriteResult {
  final int written;
  final int denied;
  final List<String> errors;
  final List<MemoryWriteRequest> requests;

  const MemoryWriteResult({
    this.written = 0,
    this.denied = 0,
    this.errors = const [],
    this.requests = const [],
  });

  bool get isEmpty => written == 0 && denied == 0;
}
