import 'package:flutter_test/flutter_test.dart';
import 'package:glaze_flutter/core/llm/memory_sidecar_prewarm_cache.dart';
import 'package:glaze_flutter/core/llm/memory_sidecar_reranker_service.dart';
import 'package:glaze_flutter/core/llm/memory_selector.dart';

MemorySidecarPrewarmKey _key({
  String sessionId = 'session1',
  String branchId = 'branchA',
  String anchorMessageId = 'msg1',
  int anchorSwipeId = 0,
  String settingsRevision = 'settings1',
  String memoryRevision = 'memory1',
  String historyRevision = 'history1',
}) {
  return MemorySidecarPrewarmKey(
    sessionId: sessionId,
    branchId: branchId,
    anchorMessageId: anchorMessageId,
    anchorSwipeId: anchorSwipeId,
    settingsRevision: settingsRevision,
    memoryRevision: memoryRevision,
    historyRevision: historyRevision,
  );
}

MemorySidecarPrewarmEntry _entry(MemorySidecarPrewarmKey key) {
  return MemorySidecarPrewarmEntry(
    key: key,
    result: const MemorySidecarResult(
      status: 'ok',
      selection: MemorySelection(),
    ),
    createdAtMillis: 10,
  );
}

void main() {
  test('takes a matching prewarm result once', () {
    final cache = MemorySidecarPrewarmCache();
    final key = _key();
    cache.put(_entry(key));

    expect(cache.takeIfFresh(key), isNotNull);
    expect(cache.takeIfFresh(key), isNull);
  });

  test(
    'invalidates on settings memory or history revision change',
    () {
      // Revision changes share the same cache key (session:anchor:swipe),
      // so a mismatched revision evicts the stale entry.
      final revisionVariants = [
        _key(historyRevision: 'history2'),
        _key(settingsRevision: 'settings2'),
        _key(memoryRevision: 'memory2'),
        _key(branchId: 'branchB'),
      ];

      for (final changedKey in revisionVariants) {
        final cache = MemorySidecarPrewarmCache();
        cache.put(_entry(_key()));
        expect(cache.takeIfFresh(changedKey), isNull);
        expect(cache.takeIfFresh(_key()), isNull);
      }
    },
  );

  test(
    'different anchor (message/swipe) does not evict original (per-swipe keying)',
    () {
      // Swipe/message changes map to different cache keys, so the original
      // entry survives (per-swipe coexistence).
      final anchorVariants = [
        _key(anchorSwipeId: 1),
        _key(anchorMessageId: 'msg2'),
      ];

      for (final changedKey in anchorVariants) {
        final cache = MemorySidecarPrewarmCache();
        cache.put(_entry(_key()));
        expect(cache.takeIfFresh(changedKey), isNull);
        expect(cache.takeIfFresh(_key()), isNotNull);
      }
    },
  );

  test('session invalidation does not touch other sessions', () {
    final cache = MemorySidecarPrewarmCache();
    final first = _key(sessionId: 'session1');
    final second = _key(sessionId: 'session2');
    cache.put(_entry(first));
    cache.put(_entry(second));

    cache.invalidateSession('session1');

    expect(cache.takeIfFresh(first), isNull);
    expect(cache.takeIfFresh(second), isNotNull);
  });

  test('per-swipe keying: different swipes coexist', () {
    final cache = MemorySidecarPrewarmCache();
    final swipe0 = _key(anchorSwipeId: 0);
    final swipe1 = _key(anchorSwipeId: 1);
    cache.put(_entry(swipe0));
    cache.put(_entry(swipe1));

    expect(cache.takeIfFresh(swipe0), isNotNull);
    expect(cache.takeIfFresh(swipe1), isNotNull);
  });

  test('anchor invalidation removes only the targeted anchor', () {
    final cache = MemorySidecarPrewarmCache();
    final a = _key(anchorMessageId: 'msg1', anchorSwipeId: 0);
    final b = _key(anchorMessageId: 'msg2', anchorSwipeId: 0);
    cache.put(_entry(a));
    cache.put(_entry(b));

    cache.invalidateAnchor('session1', 'msg1', 0);

    expect(cache.takeIfFresh(a), isNull);
    expect(cache.takeIfFresh(b), isNotNull);
  });
}
