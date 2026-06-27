import 'memory_agentic_policy.dart';

/// Tool definitions for the agentic memory system.
///
/// Read-only tools (`searchMemory`) are always available when agentic mode is
/// on. Write tools (`writeMemory`, `updateTracker`) are only exposed when the
/// policy allows writes — see [MemoryAgenticPolicy.settings.writeToolsEnabled].
///
/// Extracted from `memory_agentic_tools.dart` (plan §7.3 cosmetic split).
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
