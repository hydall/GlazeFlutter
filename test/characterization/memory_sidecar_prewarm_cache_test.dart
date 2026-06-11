import 'package:flutter_test/flutter_test.dart';
import 'package:glaze_flutter/core/llm/memory_sidecar_prewarm_cache.dart';
import 'package:glaze_flutter/core/llm/memory_sidecar_reranker_service.dart';
import 'package:glaze_flutter/core/llm/memory_selector.dart';

MemorySidecarPrewarmKey _key({
  String sessionId = 'session1',
  String branchId = 'branchA',
  int swipeId = 0,
  String settingsRevision = 'settings1',
  String memoryRevision = 'memory1',
  String historyRevision = 'history1',
}) {
  return MemorySidecarPrewarmKey(
    sessionId: sessionId,
    branchId: branchId,
    swipeId: swipeId,
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
    'invalidates on swipe regenerate edit settings memory or branch change',
    () {
      final variants = [
        _key(swipeId: 1),
        _key(historyRevision: 'history2'),
        _key(settingsRevision: 'settings2'),
        _key(memoryRevision: 'memory2'),
        _key(branchId: 'branchB'),
      ];

      for (final changedKey in variants) {
        final cache = MemorySidecarPrewarmCache();
        cache.put(_entry(_key()));
        expect(cache.takeIfFresh(changedKey), isNull);
        expect(cache.takeIfFresh(_key()), isNull);
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
}
