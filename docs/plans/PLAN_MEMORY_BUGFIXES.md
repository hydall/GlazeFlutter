# PLAN: Memory System Bug Fixes + Marinara Feature Gaps

## Context

Comprehensive comparison of Marinara Engine's memory system vs our GlazeFlutter
MemoryBook revealed 5 concrete bugs and several missing features. MemoryBook as
a summary replacement is working and strictly better than Marinara's flat text
wall — but the surrounding pipeline has gaps. This plan addresses the bugs first,
then evaluates the Marinara feature gaps for inclusion/deferral.

Branch: `feat/memory-bugfixes` off `feat/studio-status-3-of-3` (or master after
the current PR merges).

---

## §1 — Wire consolidation into `runPostTurn` (BUG — high priority)

**Problem**: `MemoryPostTurnService.runPostTurn` (memory_post_turn_service.dart:37-94)
docstring claims step 4 = "If consolidation is enabled and threshold met: trigger
consolidation" but the method body only does graph + salience. Consolidation is
never triggered automatically.

**Fix**: Add consolidation call at the end of `runPostTurn`, after graph + salience,
gated by cadence + threshold:

```dart
// After line 90 (markRun graph):
final shouldConsolidate = await _cadenceService.shouldRun(
  sessionId, 'consolidation',
  memoryMode: book.settings.memoryMode,
  cadenceInterval: book.settings.cadenceInterval,
);
if (shouldConsolidate && settings.consolidationEnabled) {
  try {
    await _consolidationService.consolidateSession(sessionId, book.entries, settings: settings);
    await _cadenceService.markRun(sessionId, 'consolidation');
  } catch (e) {
    // Decision G: consolidation errors surface to user via repo status,
    // not via exception propagation. The service already saves error status.
  }
}
```

**Dependencies**: Requires §2 (consolidation `source='current'` fix) to work end-to-end.

**Files**:
- `lib/core/llm/memory_post_turn_service.dart` — add `MemoryConsolidationService` +
  `PipelineSettings` injection, call consolidation after graph+salience.
- `lib/core/state/memory_agent_providers.dart` — wire `MemoryConsolidationService` into
  the `memoryPostTurnServiceProvider` constructor.
- `test/memory_post_turn_test.dart` — verify consolidation is called when cadence + threshold met.

---

## §2 — Fix consolidation `source='current'` resolution (BUG — high priority)

**Problem**: `MemoryConsolidationService._callLlm` (memory_consolidation_service.dart:218-220)
throws `Exception('Consolidation with source "current" requires caller to resolve config')`
when `consolidationSource == 'current'`. No caller resolves it — so consolidation only
works with a custom endpoint, not with the chat's current API.

**Fix**: Resolve the current API config inside `_callLlm` (or pass it in from
`consolidateSession`). Mirror `SidecarLlmClient.resolveConfig` pattern:
- `source='custom'` → use `consolidationEndpoint/ApiKey/Model` (existing path).
- `source='current'` → read `activeApiConfigProvider` (or the session's run API) and use
  its endpoint/key/model. Apply `consolidationModel` override if non-empty.

**Files**:
- `lib/core/llm/memory_consolidation_service.dart` — inject `Ref` (or pass
  `ApiConfig` as a parameter to `consolidateSession`), resolve `source='current'`.
- `lib/features/chat/services/generation_pipeline.dart` — if consolidation is called
  from the pipeline, pass the current `apiConfig`.
- `test/memory_consolidation_test.dart` — test both `source='custom'` and `source='current'`.

---

## §3 — Add JSON-retry to agentic write-loop (BUG — high priority)

**Problem**: `AgenticWriteRequestParser.askLlmForWrites` (agentic_write_request_parser.dart:151-153)
silently catches JSON parse errors and returns `response: null`. Transient LLM formatting
errors cause silent memory loss. Marinara retries once with a strict JSON reminder
(`buildInvalidJsonRetryMessages`).

**Fix**: On `catch (_)`, retry the LLM call ONCE with an appended system reminder:
"Your previous response was not valid JSON. Return ONLY a JSON object, no markdown
fences, no prose." If the retry also fails, return `null` (current behavior).

```dart
} catch (_) {
  // Retry once with a strict JSON reminder (Marinara buildInvalidJsonRetryMessages).
  try {
    final retryOutcome = await _llm.callWithRetry(messages: [...messages, retryReminderMessage]);
    final retryText = retryOutcome.text;
    // re-parse retryText...
    response = AgenticWriteResponse(...);
  } catch (_) {
    response = null;
  }
}
```

**Files**:
- `lib/core/llm/agentic_write_request_parser.dart` — add retry logic on catch.
- `lib/core/llm/sidecar_llm_client.dart` — possibly add a `callWithRetry` helper
  (or reuse existing `SidecarRetryRunner` with 2 attempts).
- `test/agentic_write_request_parser_test.dart` — test retry on invalid JSON.

---

## §4 — Fix `reindexAll` copy-paste bug (BUG — low priority)

**Problem**: `MemoryBookController.reindexAll` (memory_book_controller.dart:300-302):
```dart
embeddingTarget: globalSettings.vectorSearchEnabled ? 'content' : 'content',
```
Both branches return `'content'` — the conditional is pointless.

**Fix**: The non-vector branch should probably index by `'keys'` (or simply
not conditionally branch at all if `reindexAll` always targets content). Check
`MemoryEmbeddingService.reindexAll` to see what `embeddingTarget` does — if it's
only used for vector search, and vector search is disabled, the reindex is a no-op
anyway. Either:
- Remove the conditional entirely (always `'content'`), OR
- Make the non-vector branch `'keys'` if key-based indexing has a purpose.

**Files**:
- `lib/features/memory/controllers/memory_book_controller.dart:300-302` — fix or remove.
- Verify against `lib/core/llm/embedding_service.dart` — what does `embeddingTarget` do?

---

## §5 — Fix classifier potential deadlock (BUG — medium priority)

**Problem**: `MemoryClassifierHttpClient.buildClassifierClient`
(memory_classifier_http_client.dart:54) uses `unawaited(transport.stream(...))` with
a `Completer`. If `onComplete` never fires (transport silently drops the request),
the completer never resolves and the caller hangs until the outer timeout. This is a
**potential deadlock** if the timeout wrapper is missing or too long.

**Fix**: Verify the caller wraps `recall`/classifier calls in a `Future.timeout` with
a short duration (e.g., 10s). If not, add a `timeout` on the completer:
```dart
completer.future.timeout(Duration(seconds: 10), onTimeout: () => '');
```
OR convert the `unawaited(transport.stream(...))` to a direct `await` with a timeout.

**Files**:
- `lib/core/llm/memory_classifier_http_client.dart` — add timeout on completer.
- Check the caller in `memory_injection_service.dart` (the `balanced` mode classifier
  path around line 323-346) — does it already have a timeout?

---

## §6 — Add MessageRecall dimension-mismatch detection (Marinara feature gap — medium)

**Problem**: Marinara logs a warning and skips chunks whose embedding dimensions don't
match the query. GlazeFlutter only checks `textHash` staleness — if the embedding model
changes (dimensions differ), old vectors produce garbage scores without warning.

**Fix**: In `MessageRecallService.recall` (or `ChatMessageEmbeddingService`), compare
the query embedding's dimension against each candidate's embedding dimension. If they
differ, skip the candidate and log a warning. This prevents silent corruption when the
user switches embedding models.

**Files**:
- `lib/core/llm/message_recall_service.dart` — add dimension check in the scoring loop.
- `lib/core/llm/embedding_service.dart` — expose embedding dimensions or validate on write.

**Priority**: Medium — only triggers when the user changes embedding models, but when
it does, the silent corruption is hard to diagnose.

---

## §7 — Evaluate Marinara feature gaps (DEFER — document only)

The following Marinara features are **intentionally absent** or **deferred** — document
the decision in `docs/ARCHITECTURE.md` memory section:

1. **Cross-chat recall** (Marinara: up to 50 chatIds) — our recall is single-session.
   Defer: requires multi-session embedding index; not needed for roleplay MVP.

2. **Local embedder fallback** (Marinara: ONNX MiniLM / llama.cpp sidecar) — we require
   a configured embedding endpoint. Defer: 23MB ONNX binary in Flutter mobile builds
   is expensive (documented in PLAN_MEMORY_CONTINUITY.md:46).

3. **Agent batching by provider+model** (Marinara: XML-delimited `<result>` blocks) —
   our single JSON call is simpler. Defer: no per-agent model selection yet.

4. **Per-agent cadence** (Marinara: per-agent `runInterval`) — we use global
   `runAgenticEveryN`. Defer: add when we have >8 agents with different cost profiles.

5. **Knowledge router** (Marinara: LLM-based catalog routing for lorebook entries) —
   we use keyword + vector search. Defer: our `fallbackThreshold`/`fallbackTopK`
   semantic fallback (commit `5e90398`) covers the keyless-entry gap.

6. **Multi-pass RAG for lorebook** (Marinara: chunked extraction + consolidation) —
   defer: lorebook entries are short; multi-pass is for oversized documents.

7. **Head/tail truncation for recalled memories** (Marinara: 70% head + 30% tail with
   marker) — we use a soft char cap. Defer: marginal improvement; current cap works.

8. **Per-day/per-week characterMemories bucketing** — CANCELLED
   (PLAN_MEMORY_CONTINUITY.md:132). Doesn't fit roleplay.

**Files**:
- `docs/ARCHITECTURE.md` — add "Memory system vs Marinara" section documenting
  the intentional divergences and the bug fixes applied.

---

## Verification

After each section:
- `flutter analyze` — clean.
- `flutter test test/<relevant_test>.dart` — passes.
- `flutter test` — full suite passes.

After all sections:
- Manual test: start a chat with Studio + memory enabled, generate 2+ turns,
  verify `tracker_rows` + `memory_book_rows` are populated, `studioOutputs` are
  non-empty on each assistant message, and consolidation triggers after
  `consolidationThreshold` entries accumulate.

---

## Commit Strategy

One commit per section (§1-§6 are independently testable). §7 is docs-only.
Suggested messages:
- `fix(memory): wire consolidation into runPostTurn`
- `fix(memory): resolve consolidation source=current from active API`
- `fix(memory): add JSON-retry to agentic write-loop`
- `fix(memory): reindexAll copy-paste bug`
- `fix(memory): classifier timeout guard`
- `feat(memory): dimension-mismatch detection in recall`
- `docs(memory): document Marinara divergences + bug fixes`
