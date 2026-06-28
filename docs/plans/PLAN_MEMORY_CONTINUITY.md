# Plan: Memory Continuity — Recall + MemoryBook Coexistence

> **Status:** 🚧 IN PROGRESS
> **Branch:** `plan/continuity-post-cleaner` (no separate branch — series of small commits)
> **Reference:** Marinara-Engine (Pasta-Devs/Marinara-Engine) — architecture compared prior to design.
> **Goal:** Stop memory loss + duplication across regens and long chats. MemoryBook and raw-message
> Recall coexist (compression + lossless insurance), mirroring Marinara's Lorebook + Memory Recall split.

---

## 0. Why

MemoryBook is our equivalent of Marinara's Lorebook + Chat Summary combined — a chronologically
ordered set of agent-curated facts (`MemoryEntry`) keyed by `messageIds`. It replaces Summary's
"big text wall" with structured entries, which is strictly better for retrieval and dedup.

But MemoryBook is **lossy compression**. It drops:
- verbatim quotes (entry says "Lucyna killed Danvi", original says "*пра-а-авда?*")
- fact evolution (final state wins; intermediate versions lost on rewrite)
- agent-filtered "unimportant" details that turn out to matter 100 turns later

Marinara runs a **parallel** Memory Recall system (raw-message chunks → embeddings → cosine) as
**insurance against lossy compression**. We adopt the same coexistence pattern.

---

## 1. Patch Order — 4 commits

| # | Patch | File(s) | Semantics |
|---|-------|---------|-----------|
| **1** | Planner split | `lib/core/llm/memory_draft_planner.dart:37-43` | Agentic entries (`source:'agentic'`) do NOT block manual scan. Only manual entries (`source:'scan_chat'` / `kind:'curated'`) block. Pending drafts block (anti-dup-segment). |
| **2** | Append-only dedup at regen | (merged into #4 semantically — no code change of its own; #4's append-only semantics cover regen via "LLM sees existing → appends newFacts instead of rewriting") | Per Marinara philosophy: do not `deleteForMessage` at regen. Append-only + "LLM sees existing entries" together prevent duplicates idempotently. **No separate code change.** Commit message documents the decision. |
| **3** | Embed raw messages (Recall) | new `lib/core/llm/message_embedding_service.dart`, new `lib/core/llm/message_recall_service.dart`, `lib/core/db/tables.dart:491-510` (new `sourceType='chat_message'`), `lib/core/llm/prompt_payload_builder.dart` (inject `<recalled_messages>`) | Chunk=5 messages → existing `EmbeddingRepo` with `sourceType='chat_message'`, `sourceId=sessionId`, `entryId=messageId`. Cosine ≥ 0.25, top-K=8. Inject as `<recalled_messages>` block in `PromptPayload`. Fire-and-forget embed after each generation. |
| **4** | LLM sees existing entries + append-only | `lib/core/llm/agentic_write_request_parser.dart:29-70`, `lib/core/llm/memory_agentic_write_service.dart:67` | Pass `book.entries` (title + keys, no content to keep prompt lean) into prompt as `<existing_memory_entries>` block. `update` action = **append `newFacts` to existing `content`**, NOT rewrite. Anti-duplicate instruction: "Do not duplicate entries already listed below; append new facts only if the fact is genuinely new." |

**Plus in this PR:** `PipelineSettings.runAgenticEveryN` (default 8) — run agentic write-loop
every N assistant turns, not every turn. Cost/latency control, mirrors Marinara's `runInterval: 8`.

---

## 2. Alternatives Considered

### 2.1 Skip Patch #3 (no Recall, MemoryBook alone) — REJECTED for now

**Arguments for skipping (rejected):**
- 23MB ONNX MiniLM-L6-v2 binary in Flutter mobile builds is expensive
- Cosine search over a growing table adds latency per generation
- MemoryBook + chat history within the context window already covers ~80% of cases

**Arguments against skipping (winning):**
- Marinara itself keeps Recall parallel to Lorebook + Summary, investing 23MB + chunk pipeline
- Without Recall, agent-filtered "unimportant" details are unrecoverable when they later matter
- MemoryBook is lossy by design; Recall is the only lossless backstop

**Decision:** Keep #3 in this PR.

**Mobile escape hatch:** If mobile latency / binary size becomes prohibitive on real devices:
1. Make `runMemoryRecall` a per-chat toggle (default off on mobile, on on desktop) — same as
   Marinara's `enableMemoryRecall` per-chat flag.
2. Lazy-load the embedder binary only when first Recall request fires.
3. As a last resort, drop #3 entirely and rely on MemoryBook + context window. This is acceptable
   because #1 + #4 already fix the most common memory-loss cases (planner blockage, duplicates).

Code in `message_recall_service.dart` must reference this section so the escape hatch is
discoverable from source. Marker: `// ADR: see docs/plans/PLAN_MEMORY_CONTINUITY.md §2.1`.

### 2.2 `deleteForMessage` at regen (delete-then-rewrite) — REJECTED

**For:** Simple. One-line fix in `generation_pipeline.dart`.

**Against (Marinara's argument, adopted):**
- Append-only semantics in #4 already prevent duplicates idempotently: at regen, LLM sees the
  existing entries for the same `messageId`, recognizes them, and only appends `newFacts`.
- Deleting agent-written entries also discards legitimate append-only facts that other agents
  may have written for the same `messageId`.
- Marinara deliberately does NOT delete; it uses append-only + `buildHistoricalLorebookKeeperContext`
  (replay with historical slice at regen).

**Decision:** No `deleteForMessage` call at regen. Rely on #4's append-only + LLM-sees-existing.

**Follow-up not in this PR:** If regen still produces stale facts in practice, consider adding
`buildHistoricalContext` analog (replay agent with the historical message slice at the original
turn) in a separate patch. Tracked as a follow-up, not committed to this plan.

### 2.3 Drop Summary in favor of MemoryBook — already done

GlazeFlutter has no separate Chat Summary system. MemoryBook IS our summary: chronologically
ordered entries with `messageIds` linkage. This is strictly better than Marinara's flat summary
text wall. No change needed.

### 2.4 `locked` flag on entries (manual user protection) — DEFerrd

Marinara lets the user `lock` an entry so agents cannot modify it. Simple, powerful, but adds:
- a new field on `MemoryEntry`
- a UI affordance in the memory book editor
- a guard in `appendApprovedEntries` / agentic write parser

Out of scope for this PR. Tracked as a follow-up feature.

### 2.5 `hiddenFromAI` + `summaryTailMessages` — N/A

Marinara hides summarized messages from future AI context. GlazeFlutter does not have a separate
Summary system that would benefit from hiding. The chat history window already preserves the
recent tail. No change.

---

## 3. Per-Patch Tests

| # | Test file | Assertion |
|---|-----------|-----------|
| 1 | `test/characterization/memory_draft_planner_test.dart` (new case) | An entry with `source:'agentic'` does NOT mark its `messageIds` as covered; an entry with `source:'scan_chat'` DOES. |
| 2 | (no new test — covered by #4) | — |
| 3 | `test/message_recall_service_test.dart` (new) | After embedding 5 messages, querying a semantically close message returns the right chunk in top-K with similarity ≥ 0.25. |
| 4 | `test/agentic_write_request_parser_test.dart` (new cases) | (a) The prompt contains an `<existing_memory_entries>` block listing titles + keys. (b) An `update` action appends `newFacts` to existing `content` instead of replacing it. |

Plus: `flutter analyze` clean + all existing tests green before each commit.

---

## 4. Out of Scope (follow-up patches, not in this PR)

- `locked` flag on `MemoryEntry` (manual user protection from agent rewrite) — **DONE in follow-up commit `1d27d05`.**
- `buildHistoricalLorebookKeeperContext` analog (replay agent with historical slice at regen) — **DONE in follow-up commit `4e8ab08`.**
- `chatSummaryFingerprint` analog for prompt-cache invalidation (relevant if/when we add Anthropic/DeepSeek prompt caching) — **DONE in follow-up commit `567bdfd`.**
- `excludeFromVectorization` granular opt-out for spoiler entries — **DONE in follow-up commit `1d27d05` (MemoryEntry) and `5e90398` (LorebookEntry).**
- Vector embeddings on MemoryBook entries (semantic activation without keyword gate — Marinara's supplementary system 4) — **DONE in follow-up commit `5e90398` (semantic fallback for keyless lorebook entries).**
- `agentWriteApprovalRequired` per-chat flag (user review modal before agent writes) — **DONE in follow-up commit `1bbd3db` (backend gate; agent writes land in pendingDrafts for review in existing MemoryBook UI).**

### Cancelled

- **Per-day / per-week summary hierarchy** (Marinara conversation mode). CANCELLED — does not fit roleplay use case. Roleplay chats are paused between sessions (the in-fiction timeline does not advance with wall-clock time), so bucketing memories by real-world day/week is meaningless. MemoryBook's existing chronological append-only structure already handles long conversations correctly. Marinara uses day/week only for its "Conversation" mode (Discord-style DMs), not for roleplay.
