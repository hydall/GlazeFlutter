import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Per-chat in-memory ring of the LAST sent prompt fingerprints.
///
/// We only ever need to compare the current request against the immediately
/// previous one to find the optimal Anthropic cache breakpoint. The set is
/// overwritten on every generation, so memory stays bounded and stale chats
/// are self-evicting on app restart (we don't persist to disk).
///
/// This is deliberately volatile: if the app restarts, the cache fingerprint
/// ring is lost, and the next request will simply behave like a cold start
/// (Anthropic's automatic caching still applies).
class PromptCacheFingerprintStore {
  final Map<String, List<String>> _byCharId = <String, List<String>>{};

  /// Returns the last sent fingerprint for [charId], or null if none.
  List<String>? read(String charId) => _byCharId[charId];

  /// Overwrites the stored fingerprint for [charId].
  void write(String charId, List<String> fingerprints) {
    _byCharId[charId] = List<String>.unmodifiable(fingerprints);
  }

  /// Clears the stored fingerprint for [charId]. Used when the user starts
  /// a brand new session or regenerates from scratch.
  void clear(String charId) => _byCharId.remove(charId);
}

final promptCacheFingerprintStoreProvider =
    Provider<PromptCacheFingerprintStore>((ref) {
  return PromptCacheFingerprintStore();
});
