import 'memory_sidecar_reranker_service.dart';

class MemorySidecarPrewarmKey {
  final String sessionId;
  final String branchId;
  final int swipeId;
  final String settingsRevision;
  final String memoryRevision;
  final String historyRevision;

  const MemorySidecarPrewarmKey({
    required this.sessionId,
    required this.branchId,
    required this.swipeId,
    required this.settingsRevision,
    required this.memoryRevision,
    required this.historyRevision,
  });

  bool matches(MemorySidecarPrewarmKey other) {
    return sessionId == other.sessionId &&
        branchId == other.branchId &&
        swipeId == other.swipeId &&
        settingsRevision == other.settingsRevision &&
        memoryRevision == other.memoryRevision &&
        historyRevision == other.historyRevision;
  }
}

class MemorySidecarPrewarmEntry {
  final MemorySidecarPrewarmKey key;
  final MemorySidecarResult result;
  final int createdAtMillis;

  const MemorySidecarPrewarmEntry({
    required this.key,
    required this.result,
    required this.createdAtMillis,
  });
}

class MemorySidecarPrewarmCache {
  final Map<String, MemorySidecarPrewarmEntry> _bySession = {};

  void put(MemorySidecarPrewarmEntry entry) {
    _bySession[entry.key.sessionId] = entry;
  }

  MemorySidecarPrewarmEntry? takeIfFresh(MemorySidecarPrewarmKey key) {
    final entry = _bySession[key.sessionId];
    if (entry == null) return null;
    if (!entry.key.matches(key)) {
      _bySession.remove(key.sessionId);
      return null;
    }
    return _bySession.remove(key.sessionId);
  }

  void invalidateSession(String sessionId) {
    _bySession.remove(sessionId);
  }

  void clear() => _bySession.clear();
}
