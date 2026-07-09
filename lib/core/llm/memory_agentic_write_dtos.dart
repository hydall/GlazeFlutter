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
