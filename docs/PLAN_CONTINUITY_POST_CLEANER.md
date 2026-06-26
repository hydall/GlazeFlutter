# PLAN: Continuity-Aware POST-Cleaner

Status: **DRAFT / IMPLEMENTATION PLAN**.

Goal: evolve the existing POST-cleaner from a style-only rewrite pass into a conservative continuity-aware editor. It should still primarily remove cliches, repetition, filler, and AI-isms, but it should also catch local scene mistakes from recent chat history: who said what, who is present, what characters are wearing or holding, current positions, and what just happened.

Non-goal: do not turn the cleaner into a second final writer. It must not invent new story beats, add exposition, or rewrite the scene from scratch.

---

## 1. Current State

The cleaner lives in `lib/core/llm/post_cleaner_service.dart`.

Current inputs:

- `assistantText` — final assistant response to clean.
- `broadcastBlocks` — Studio build-time cross-cutting rules, mostly output language and prose-quality guards.
- `MemoryBookSettings` — sidecar model, temperature, max tokens, timeout, and enable flag.

Current behavior:

- Builds a prompt with style cleanup instructions.
- Calls the sidecar LLM once via `SidecarLlmClient`.
- Rejects empty output and extreme length ratio changes.
- Saves the cleaned output as a nested `AgentSwipe(kind: 'cleaned')` while preserving the final-agent text as `kind: 'final'`.

Current limitation:

- The cleaner does not see the chat history. It cannot reliably detect local continuity mistakes such as a character answering a question they did not hear, a speaker being swapped, clothing reverting, an item changing owner, or an NPC forgetting the current scene position.

---

## 2. Product Behavior

The cleaner should perform two tasks in one sidecar pass:

1. Style cleanup.
2. Conservative local continuity check against the recent chat history.

Continuity checks should cover only facts directly supported by the supplied context:

- who said or asked something;
- who is present in the current scene;
- where characters are positioned;
- what characters are wearing or holding;
- object ownership and visible props;
- recent actions and unanswered or already answered questions;
- whether characters currently know each other;
- whether a character should stay silent or speak based on the immediate scene.

The cleaner may fix only clear contradictions. If the context is ambiguous, it must preserve the original response and only clean style.

---

## 3. Source Priority

When multiple sources are available, the prompt should define this priority order:

1. **Recent chat history** — authoritative for current scene state.
2. **Injected memory context** — authoritative for stable background facts, but only after it is wired in a later phase.
3. **Studio controller notes** — authoritative for intended behavior, agency, and constraints.
4. **Broadcast style rules** — authoritative for prose, language, formatting, and anti-cliche rules.

Conflict rule:

- If recent history conflicts with memory, prefer recent history for current scene state.
- If memory conflicts with Studio notes, prefer memory for stable facts and Studio notes for behavior constraints.
- If sources are still ambiguous, keep the final-agent response and only clean style.

---

## 4. Phase 1: Recent Chat History

Implement first. This gives the largest improvement for the observed failure class without adding new persistence.

### 4.1 Data Flow

Update `GenerationPipeline._runPostCleaner` in `lib/features/chat/services/generation_pipeline.dart`:

- Find the index of the last assistant message being cleaned.
- Build a bounded list of messages before that assistant response.
- Pass that list to `PostCleanerService.runCleaner`.
- Also pass the last assistant message's `studioOutputs` so the cleaner can reuse the controller notes that shaped the final response.

Recommended defaults:

- Last `12` messages before the assistant response.
- Trim each message to a maximum of `3000` characters.
- Keep role, optional persona name, message id suffix, and content.

Do not include the assistant response being cleaned inside `RECENT CHAT HISTORY`; it is supplied separately as `ASSISTANT RESPONSE TO CLEAN`.

### 4.2 Prompt Shape

Extend `PostCleanerService.buildCleanerPrompt` into a context-aware builder:

```text
You are a conservative prose editor for a roleplay story.

Your primary job is to clean style: remove cliches, repetitive phrasing,
filler, and common AI-isms.

Before editing style, silently check the assistant response against RECENT
CHAT HISTORY and STUDIO CONTROLLER NOTES.

RECENT CHAT HISTORY:
[assistant #41]
...

[user #42]
...

STUDIO CONTROLLER NOTES:
[Continuity Controller]
...

AUTHORITATIVE STYLE RULES:
...

Rules:
- Keep the same meaning, events, character voices, POV, tense, output language, and formatting.
- Fix only clear local continuity contradictions directly contradicted by the provided context.
- You may correct who said what, who is present, current position, clothing, held objects, object ownership, and recent actions.
- If the context is ambiguous, keep the original wording.
- Do not invent missing details.
- Do not add new events, explanations, dialogue, memories, or motivations.
- Prefer minimal edits: remove, shorten, or neutralize the incorrect phrase.
- Return only the cleaned text.

ASSISTANT RESPONSE TO CLEAN:
...
```

### 4.3 Context Formatting Rules

History formatting should be compact and literal:

```text
[user #m123]
*сажусь за барную стойку.* "А меню у вас существует?"
```

Avoid summarizing in Phase 1. Summaries can introduce new errors and make post-cleaner debugging harder. Raw recent messages are more reliable.

### 4.4 Safety Guards

Keep the existing length-ratio guard. Add lightweight output guards if needed:

- reject outputs that start with explanation labels such as `Here is`, `Explanation:`, `Cleaned:`, or `Diff:`;
- reject empty or refusal-like outputs;
- keep existing no-change behavior when the cleaner returns identical text.

Do not add aggressive semantic diffing in Phase 1. It is easy to false-positive on legitimate prose cleanup.

---

## 5. Phase 2: Injected Memory Context

Add after Phase 1 is working. The cleaner should check against memory that was actually injected into the original generation prompt, not perform a fresh memory search.

### 5.1 Principle

The cleaner must use memory only as a contradiction checker.

Allowed:

- correct a wrong name;
- correct relationship labels;
- correct ownership of an item;
- correct a directly contradicted past event;
- remove a sentence that contradicts memory and cannot be safely corrected.

Not allowed:

- add new memory exposition;
- make a character mention memory facts unprompted;
- override current scene state from recent chat history;
- use memory as inspiration for new dialogue or actions.

### 5.2 Preferred Data Flow

Persist or carry the memory blocks selected for the original generation.

Preferred shape:

```json
{
  "injectedMemoryBlocks": [
    {
      "source": "memory_book",
      "id": "...",
      "title": "...",
      "content": "...",
      "scope": "chat|character|global",
      "priority": 0
    }
  ]
}
```

Potential storage locations:

- `ChatMessage.memoryCoverage` if the existing shape can hold full injected text safely;
- a new metadata field on `ChatMessage` if full injected blocks should be first-class;
- `swipesMeta` for per-green-swipe generation metadata if memory differs by branch/swipe.

Avoid re-querying memory by ID after generation unless there is no alternative. Memory may have changed between generation and post-cleaner, which would make the cleaner validate against context the final writer did not see.

### 5.3 Prompt Section

Add a section between recent history and Studio notes:

```text
INJECTED MEMORY CONTEXT:
These memory entries were included in the original generation context.
Use them only to detect direct contradictions.
Do not introduce memory facts that the assistant response did not already touch.
If recent chat history conflicts with memory, recent chat history wins for current scene state.
```

---

## 6. Phase 3: Optional Strict Fact-Check Mode

Only consider this if the single-pass cleaner still misses too many contradictions.

Strict mode would be a two-pass sidecar flow:

1. Fact-check pass returns a compact JSON list of continuity problems.
2. Cleaner pass applies style cleanup plus minimal fixes for those problems.

Benefits:

- easier debugging;
- possible UI display of detected issues;
- stronger separation between detection and rewrite.

Costs:

- more latency;
- more tokens;
- more failure modes;
- another operation type in logs.

Default recommendation: do not implement strict mode until the one-pass context-aware cleaner is evaluated.

---

## 7. Code Touchpoints

Expected Phase 1 files:

- `lib/features/chat/services/generation_pipeline.dart`
  - collect bounded recent history before the cleaned assistant message;
  - pass recent history and Studio outputs to `PostCleanerService.runCleaner`.

- `lib/core/llm/post_cleaner_service.dart`
  - introduce a small context object or additional parameters;
  - format recent messages;
  - format Studio controller notes;
  - update `buildCleanerPrompt`.

- `test/...`
  - add prompt-builder tests for history inclusion, trimming, and conservative rules;
  - add tests that empty history preserves current prompt behavior where practical.

Possible Phase 2 files:

- `lib/core/llm/prompt_payload_builder.dart`
- `lib/core/llm/prompt_builder.dart`
- `lib/core/models/chat_message.dart`
- `lib/core/db/repositories/chat_repo.dart`
- `lib/core/llm/post_cleaner_service.dart`

Exact Phase 2 touchpoints depend on where injected memory metadata is captured.

---

## 8. Testing Plan

Phase 1 tests:

- `buildCleanerPrompt` includes recent chat history before the assistant response.
- History is trimmed and bounded.
- Prompt includes explicit conservative continuity rules.
- Prompt preserves broadcast rules and keeps them authoritative for style/language.
- Studio controller notes are included when provided and omitted cleanly when absent.

Manual validation scenarios:

- NPC does not confuse who asked the last question.
- NPC does not speak for a silent character when history indicates that another character should answer.
- Clothing and held objects do not revert within a short scene.
- Character positions at a table/bar/door remain consistent.
- Cleaner still performs style cleanup without expanding the scene.

Phase 2 tests:

- Injected memory context is included only when available.
- Prompt prioritizes recent history over memory for current scene state.
- Memory rules prohibit adding exposition from memory.

---

## 9. Rollout

Phase 1 should be enabled behind the existing POST-cleaner enable flag. No new UI is required for MVP.

Recommended implementation sequence:

1. Add context parameters and prompt tests.
2. Wire recent history and Studio outputs from `GenerationPipeline`.
3. Run `flutter analyze` and focused tests.
4. Test manually on a chat where the final response has a clear local continuity slip.
5. Only after Phase 1 is stable, design Phase 2 injected-memory capture.

Do not expose strict fact-check mode or memory verification UI until there is evidence that the one-pass cleaner is insufficient.

---

## 10. Success Criteria

The change is successful if:

- post-cleaner still primarily improves prose style;
- it catches obvious local continuity contradictions from recent history;
- it does not add new story content;
- it does not significantly increase latency beyond one extra sidecar call already used by the cleaner;
- original final-agent output remains recoverable through nested agent swipes;
- future memory-book verification can be added by supplying injected memory blocks without redesigning the cleaner.
