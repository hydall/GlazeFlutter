// ---------------------------------------------------------------------------
// Write tool result types (Stage 1 — agentic write-loop)
// ---------------------------------------------------------------------------

/// A single tracker write requested by the agent.
///
/// Extracted from `memory_agentic_tools.dart` (plan §7.3 cosmetic split).
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
///
/// `existingEntryId` distinguishes two write modes (patch #4):
/// - empty → CREATE a new MemoryEntry with the given title/content/keys.
/// - non-empty → APPEND `content` as newFacts to the existing entry with
///   that id. The pipeline looks up the existing entry, appends `\n\n`
///   + this request's content to its `content`, and updates it via the
///   repo. Title/keys from this request are merged into the existing
///   entry's keys (case-insensitive dedup). The existing entry is NOT
///   rewritten — only appended to (Marinara append-only newFacts
///   semantics). Rationale (patch #4): append-only newFacts to existing entries
///   prevents fact loss at regen — the LLM sees existing entries via
///   `<existing_memory_entries>` and appends rather than rewriting (Marinara
///   append-only analog).
class MemoryWriteRequest {
  final String title;
  final String content;
  final List<String> keys;
  final String existingEntryId;

  const MemoryWriteRequest({
    required this.title,
    required this.content,
    this.keys = const [],
    this.existingEntryId = '',
  });

  factory MemoryWriteRequest.fromJson(Map<String, dynamic> json) {
    final rawKeys = json['keys'];
    return MemoryWriteRequest(
      title: (json['title'] as String?) ?? '',
      content: (json['content'] as String?) ?? '',
      keys: rawKeys is List
          ? rawKeys.map((e) => e.toString()).toList()
          : <String>[],
      existingEntryId: (json['existingEntryId'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        'content': content,
        'keys': keys,
        if (existingEntryId.isNotEmpty) 'existingEntryId': existingEntryId,
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
