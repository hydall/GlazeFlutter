import 'memory_provenance.dart';
import 'memory_sidecar_reranker_service.dart';

/// Key for sidecar prewarm cache entries. Uses full provenance (branch +
/// swipe + revisions) so that stale results from a different branch, swipe,
/// or settings revision are automatically evicted.
///
/// This aligns with [MemoryProvenanceKey] but is kept as a separate type
/// because the prewarm cache stores one entry per anchor (message + swipe),
/// not per session.
class MemorySidecarPrewarmKey {
  final String sessionId;
  final String branchId;
  final String anchorMessageId;
  final int anchorSwipeId;
  final String settingsRevision;
  final String memoryRevision;
  final String historyRevision;

  const MemorySidecarPrewarmKey({
    required this.sessionId,
    required this.branchId,
    required this.anchorMessageId,
    required this.anchorSwipeId,
    required this.settingsRevision,
    required this.memoryRevision,
    required this.historyRevision,
  });

  /// Construct from a [MemoryProvenanceKey] (preferred).
  factory MemorySidecarPrewarmKey.fromProvenance(MemoryProvenanceKey key) {
    return MemorySidecarPrewarmKey(
      sessionId: key.sessionId,
      branchId: key.branchId,
      anchorMessageId: key.anchorMessageId,
      anchorSwipeId: key.anchorSwipeId,
      settingsRevision: key.settingsRevision,
      memoryRevision: key.memoryRevision,
      historyRevision: key.historyRevision,
    );
  }

  bool matches(MemorySidecarPrewarmKey other) {
    return sessionId == other.sessionId &&
        branchId == other.branchId &&
        anchorMessageId == other.anchorMessageId &&
        anchorSwipeId == other.anchorSwipeId &&
        settingsRevision == other.settingsRevision &&
        memoryRevision == other.memoryRevision &&
        historyRevision == other.historyRevision;
  }

  String get _cacheKey => '$sessionId:$anchorMessageId:$anchorSwipeId';
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

/// In-memory prewarm cache for sidecar reranker results.
///
/// Keyed by `sessionId:anchorMessageId:anchorSwipeId` so that multiple swipe
/// variants can coexist without overwriting each other. Stale entries (where
/// the key doesn't match) are evicted on [takeIfFresh].
class MemorySidecarPrewarmCache {
  final Map<String, MemorySidecarPrewarmEntry> _entries = {};

  void put(MemorySidecarPrewarmEntry entry) {
    _entries[entry.key._cacheKey] = entry;
  }

  /// Returns and removes the entry if it matches the key. Returns null
  /// (and evicts any stale entry) if the key doesn't match.
  MemorySidecarPrewarmEntry? takeIfFresh(MemorySidecarPrewarmKey key) {
    final entry = _entries[key._cacheKey];
    if (entry == null) return null;
    if (!entry.key.matches(key)) {
      _entries.remove(key._cacheKey);
      return null;
    }
    return _entries.remove(key._cacheKey);
  }

  /// Invalidate all entries for a session (used on swipe/regenerate/branch).
  void invalidateSession(String sessionId) {
    _entries.removeWhere((key, _) => key.startsWith('$sessionId:'));
  }

  /// Invalidate a specific anchor (message + swipe).
  void invalidateAnchor(String sessionId, String anchorMessageId, int anchorSwipeId) {
    _entries.remove('$sessionId:$anchorMessageId:$anchorSwipeId');
  }

  void clear() => _entries.clear();
}
