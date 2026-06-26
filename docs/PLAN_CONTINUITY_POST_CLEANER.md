# PLAN: Continuity-Aware POST-Cleaner

Status: **Phase 2 shipped**.

Phase 1 shipped (commit `d47f9d3`): recent chat history + Studio controller
notes wired into the cleaner prompt with conservative continuity rules.

Phase 2 shipped: PromptPayload pass-through + Character/World Auditor +
cleaner with audit notes.

Goal: evolve the existing POST-cleaner from a style-only rewrite pass into a
two-stage continuity-aware editor:

1. **Character/World Auditor** — a diagnostic sidecar pass that checks the final
   response against the **full generation context** (character card, persona,
   lorebooks, memory, summary, arcs, entities) and returns a compact list of
   contradictions. It does NOT rewrite text.
2. **Style Cleaner + Continuity Editor** — the existing cleaner, enhanced with
   recent chat history and Studio controller notes, receives the auditor's
   issues as explicit fix instructions and produces a single cleaned output.

Non-goals:

- Do not turn the cleaner into a second final writer.
- Do not create additional agent swipes. The result is one `cleaned` swipe, as
  today.
- Do not re-query memory/lorebooks after generation. The auditor uses the exact
  `PromptPayload` snapshot from the generation that produced the response.

---

## 1. Current State

The cleaner lives in `lib/core/llm/post_cleaner_service.dart`.

### Phase 1 (shipped)

- `PostCleanerService.runCleaner` accepts `recentMessages` and `studioOutputs`.
- `buildCleanerPrompt` includes `RECENT CHAT HISTORY` (last 12 messages,
  trimmed to 3000 chars each) and `STUDIO CONTROLLER NOTES` before style rules,
  plus conservative `Continuity rules` that appear only when context is present.
- `GenerationPipeline._runPostCleaner` collects the bounded history window and
  passes `lastAssistant.studioOutputs` to `runCleaner`.
- 7 new tests cover history inclusion, ordering, trimming, empty-skip, studio
  output formatting, and combined context ordering.
- `flutter analyze` — 0 issues. `flutter test` — 36/36 passed.

### Sidecar split & Post-Building UI (shipped, commit `dda65b6`)

- `MemoryBookSettings` extended with `postCleanerSource/Model/Endpoint/ApiKey/
  TimeoutMs` (per-feature, `'inherit'`/empty/0 fallback to shared `sidecar*`).
- `MemoryBookSettings` extended with `postCleanerContinuityEnabled` (default
  `true`), `postCleanerCharacterCheckEnabled` (default `false`, opt-in),
  `postCleanerHistoryMessages` (default `12`), `postCleanerMaxCharsPerMessage`
  (default `3000`).
- `SidecarLlmClient.resolveConfigForCleaner` + `resolveCleanerTimeout` prefer
  cleaner-specific fields, fall back to shared sidecar fields.
- `PostBuildingMenuDialog` (`post_building_menu_dialog.dart`) hosts all
  post-cleaner settings, opened from MagicDrawer `post-building` item.
- Post-cleaner settings removed from `studio_menu_dialog.dart`.

### Phase 2 (shipped)

- **PromptPayload pass-through:** `ChatState` gained a transient
  `PromptPayload? promptPayload` field (not persisted, not UI state). The three
  `StreamGenerationService.run()` exit points that produce a real assistant
  message (studio agent_errors, studio success, non-studio `onComplete`) set
  it via `.copyWith(promptPayload: payload)`. Early-abort and error paths leave
  it null — the auditor is skipped there anyway.
- **Character/World Auditor:** `PostCleanerService.runCharacterAudit` performs
  a diagnostic sidecar call (temperature 0.0, max_tokens 1024) that returns
  `List<String>?` — the contradictions, `[]` when clean, `null` on failure
  (skip audit). `buildAuditPrompt` assembles character profile (name,
  description, personality, scenario, post-history instructions), persona,
  lorebooks/memory/summary/arc/entity content, recent history, and the
  assistant response, with JSON-only output instructions.
- **Audit JSON parsing:** `parseAuditJson` handles `{"ok": true}` → `[]`,
  `{"ok": false, "issues": [...]}` → filtered string list, malformed/prose/
  markdown-fenced → extracts first balanced `{...}` block, returns `null` on
  failure. Filters non-string and empty issues.
- **Cleaner with audit notes:** `runCleaner` accepts `List<String>? auditIssues`.
  `buildCleanerPrompt` adds a `CHARACTER CONSISTENCY NOTES (from auditor — fix
  these)` section between `STUDIO CONTROLLER NOTES` and `AUTHORITATIVE RULES`
  when issues are non-empty, with explicit "apply minimal fixes, prefer
  deletion or neutral rewording, do not add new content" instructions. When null
  or empty, the section is omitted (Phase 1 behavior preserved).
- **Lorebook content assembly:** `_assembleLorebooksContent(payload)` in
  `generation_pipeline.dart` combines `preScannedEntries` (keyword path) and
  `vectorEntries` (deep/vector path) into a plain-text snapshot. Simpler than
  the full prompt builder's `_classifyLorebooks` — the auditor needs facts, not
  positioning/formatting.
- **Wiring:** `GenerationPipeline._runPostCleaner` accepts `PromptPayload?`,
  conditionally calls `runCharacterAudit` when
  `postCleanerCharacterCheckEnabled && promptPayload != null`, passes the
  resulting issues to `runCleaner`. Both `_runPostCleaner` call sites (regen +
  normal) thread `result.promptPayload`.
- **Tests:** 24 new tests — `buildAuditPrompt` (character/persona/lore/memory/
  summary/arc/entity inclusion, empty-section omission, JSON instructions,
  ordering), `parseAuditJson` (ok, issues, malformed, missing fields, non-string
  filtering, markdown-fence extraction, prose extraction, empty/blank input),
  `buildCleanerPrompt` with auditIssues (section inclusion, null/empty omission,
  ordering, separation from continuity rules). `flutter analyze` — 0 issues.
  `flutter test` — 1334/1334 passed.

### What is still missing

- The cleaner does NOT see character card (description, personality, scenario),
  persona, lorebooks, memory, summary, arcs, or entities. It cannot detect
  contradictions against the character's personality or world facts.
- `PromptPayload` is available during generation but is not passed to
  `_runPostCleaner`. The cleaner has no access to the generation context.

---

## 2. Architecture: Two-Pass Audit + Clean

### 2.1 Flow

```
Generation completes
  → PromptPayload available (character, persona, lorebooks, memory, summary,
     arcs, entities — the exact context the final agent saw)

Pass 0: Character/World Auditor (diagnostic, no text rewrite)
  input:  assistantText + PromptPayload fields + recentMessages (short window)
  output: List<String> issues  (empty = no contradictions found)

Pass 1: Style Cleaner + Continuity Editor (existing cleaner, enhanced)
  input:  assistantText + recentMessages + studioOutputs + broadcastBlocks
          + auditIssues (from Pass 0)
  output: cleanedText

Result: one AgentSwipe(kind: 'cleaned') — same as today.
```

### 2.2 Why two passes, not one

A single pass that receives character card + lorebooks + memory + history +
studio notes + style rules would have an oversized prompt and conflicting
instructions: "check facts" vs "clean style" vs "don't add content". The model
can get confused and start rewriting the scene.

Splitting diagnosis and rewrite:
- Auditor only finds problems (cheap, small max_tokens, JSON output).
- Cleaner only applies fixes + style (already works, just gets explicit
  instructions for what to fix).
- If auditor finds no issues, cleaner runs exactly as Phase 1 — no overhead
  beyond one short audit call.

### 2.3 Why no third swipe

Pass 0 does not produce a swipe. It returns `List<String> issues` passed as a
prompt parameter to Pass 1. The `agentSwipes[]` array stays at 2 entries:
`final` + `cleaned`.

Optionally, `issues` can be stored in `AgentSwipe.studioOutputs` of the
cleaned swipe as a diagnostic trace, so the diff viewer can show what the
auditor found. This is optional and does not affect swipe count or UI.

---

## 3. Source Priority

```
1. Recent chat history       — current scene state (who/where/what just happened)
2. Character card            — personality, scenario, description (stable identity)
3. Persona                   — user identity (name, role, description)
4. Injected lorebooks        — world facts ({{lorebooks}} snapshot)
5. Injected memory           — long-term facts ({{memory}} snapshot)
6. Summary                   — condensed history ({{summary}})
7. Arcs                      — narrative arc summaries ({{arc}})
8. Entities                   — active entity list ({{entities}})
9. Studio controller notes   — intended behavior/agency/constraints
10. Broadcast style rules    — prose, language, formatting, anti-cliche
```

Conflict rule:
- Recent history wins for current scene state.
- Character card wins for stable identity/personality.
- Lorebooks/memory win for world facts and long-term facts.
- Studio notes win for behavior constraints (who should speak/stay silent).
- If ambiguous, preserve the original and only clean style.

---

## 4. Phase 2: PromptPayload Pass-Through

### 4.1 Key Decision: Carry PromptPayload to Post-Cleaner

Instead of re-querying memory/lorebooks after generation (which can produce
different results if data changed), the `PromptPayload` built during generation
is passed directly to `_runPostCleaner`.

This means:
- **No separate "wire memory" phase.** `PromptPayload` already contains
  `memoryContent`, `memorySelection.entries`, `arcContent`, `entitiesContent`,
  `summaryContent`, `vectorEntries`, `lorebooks`, `character`, `persona`.
- **No DB migration.** No new fields on `ChatMessage`.
- **No re-query cost.** The payload is already in memory.
- **Exact snapshot.** The auditor sees exactly what the final agent saw.

### 4.2 Data Flow Changes

**`ChatGenerationService.generate()`** currently builds `PromptPayload`
internally via `PromptPayloadBuilder.buildFromSession()`. It needs to expose
the payload in its result so `GenerationPipeline` can pass it downstream.

Changes:
- `GenerationResult` (or equivalent) carries `PromptPayload? promptPayload`.
- `GenerationPipeline.run()` receives the payload from `service.generate()`.
- `GenerationPipeline._runPostCleaner` accepts `PromptPayload` and extracts:
  - `payload.character` → description, personality, scenario,
    `post_history_instructions`
  - `payload.persona` → name, prompt/description
  - `payload.summaryContent` → `{{summary}}` text
  - `payload.memoryContent` / `payload.memoryMacroContent` → `{{memory}}` text
  - `payload.arcContent` → `{{arc}}` text
  - `payload.entitiesContent` → `{{entities}}` text
  - `payload.lorebooks` + `payload.vectorEntries` → assemble lorebooks content
    (reuse `prompt_builder`'s lorebook assembly or pass pre-built content)
  - `payload.memorySelection.entries` → individual memory entry texts (if
    `memoryContent` is not sufficient and per-entry detail is needed)

### 4.3 What if PromptPayload is null?

`PromptPayload` can be null if generation failed early or used a fallback path.
In that case, the auditor is skipped and the cleaner runs as Phase 1 (style +
history + studio notes only). No crash, no degraded behavior.

---

## 5. Phase 2: Character/World Auditor

### 5.1 Auditor Service

New method in `PostCleanerService`:

```dart
Future<List<String>> runCharacterAudit({
  required String assistantText,
  required Character character,
  Persona? persona,
  String? lorebooksContent,
  String? memoryContent,
  String? summaryContent,
  String? arcContent,
  String? entitiesContent,
  List<ChatMessage> recentMessages,
  MemoryBookSettings settings,
  CancelToken? cancelToken,
})
```

Returns:
- `[]` — no contradictions found.
- `['issue 1', 'issue 2', ...]` — list of specific contradictions.

### 5.2 Auditor Prompt

```text
You are a continuity auditor for a roleplay story. Your job is to find
contradictions between the assistant response and the provided context.

CHARACTER PROFILE:
Description: ...
Personality: ...
Scenario: ...

USER PERSONA:
Name: ...
Description: ...

INJECTED WORLD/LORE CONTEXT:
...

INJECTED MEMORY CONTEXT:
...

SUMMARY:
...

ARCS:
...

ENTITIES:
...

RECENT CHAT HISTORY:
...

ASSISTANT RESPONSE TO AUDIT:
...

Instructions:
- Check the response against ALL provided context.
- Report ONLY direct contradictions: wrong names, wrong relationships, wrong
  locations, personality conflicts, world-fact errors, persona identity errors.
- Do NOT report style issues, cliches, or prose quality.
- Do NOT suggest fixes or rewrites. Only describe the contradiction.
- If no contradictions found, return: {"ok": true}
- If contradictions found, return: {"ok": false, "issues": ["...", "..."]}

Return ONLY the JSON, no other text.
```

### 5.3 Auditor Output Parsing

Parse JSON response:
```json
{"ok": true}
{"ok": false, "issues": ["Lucy is described as speaking but should be silent per scenario.", "Menu is described as paper but lore says wall of names."]}
```

If parsing fails or the response is not valid JSON:
- Log a warning.
- Return `null` (skip audit, cleaner runs without audit notes).

### 5.4 Auditor Settings

- Cheap model (reuse sidecar model, or allow separate model override).
- Low temperature (0.0–0.1).
- Small `max_tokens` (512–1024, enough for JSON with a few issues).
- Short timeout (sidecar timeout is fine).

---

## 6. Phase 2: Cleaner with Audit Notes

### 6.1 Enhanced Prompt

When `auditIssues` is non-empty, `buildCleanerPrompt` adds:

```text
CHARACTER CONSISTENCY NOTES (from auditor — fix these):
- Lucy is described as speaking but should be silent per scenario.
- Menu is described as paper but lore says wall of names.

Apply minimal fixes for these issues while also cleaning style.
Do not add new content to resolve them. Prefer deletion or neutral rewording.
```

This section appears after `RECENT CHAT HISTORY` and `STUDIO CONTROLLER
NOTES`, before `AUTHORITATIVE STYLE RULES`.

### 6.2 No Audit Issues

When `auditIssues` is `null` or empty, the cleaner runs exactly as Phase 1.
No `CHARACTER CONSISTENCY NOTES` section is added.

---

## 7. Settings & UI

### 7.1 Sidecar Settings Split

Currently `MemoryBookSettings` has a single set of sidecar fields
(`sidecarSource`, `sidecarModel`, `sidecarEndpoint`, `sidecarApiKey`,
`sidecarTimeoutMs`) shared by the agentic write-loop, agentic mode, and the
POST-cleaner. This couples the cleaner to the write-loop configuration.

Split into per-feature settings:

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `sidecarSource` | String | `'current'` | Write-loop source (unchanged). |
| `sidecarModel` | String | `''` | Write-loop model (unchanged). |
| `sidecarEndpoint` | String | `''` | Write-loop endpoint (unchanged). |
| `sidecarApiKey` | String | `''` | Write-loop API key (unchanged). |
| `sidecarTimeoutMs` | int | `60000` | Write-loop timeout (unchanged). |
| `postCleanerSource` | String | `'inherit'` | Cleaner source. `'inherit'` = fall back to `sidecarSource`. |
| `postCleanerModel` | String | `''` | Cleaner model. Empty = fall back to `sidecarModel`. |
| `postCleanerEndpoint` | String | `''` | Cleaner endpoint. Empty = fall back to `sidecarEndpoint`. |
| `postCleanerApiKey` | String | `''` | Cleaner API key. Empty = fall back to `sidecarApiKey`. |
| `postCleanerTimeoutMs` | int | `0` | Cleaner timeout. `0` = fall back to `sidecarTimeoutMs`. |

Resolution logic in `SidecarLlmClient.resolveConfig` (or a cleaner-specific
variant): if `postCleanerModel` is non-empty, use it; otherwise use
`sidecarModel`. Same for endpoint, apiKey, source, timeout. This lets the user
run the cleaner on a cheaper/faster model while the write-loop stays on a
different one — or keep them shared by leaving the cleaner fields empty.

### 7.2 Post-Cleaner Behavior Settings

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `postCleanerEnabled` | bool | `false` | Master switch (existing). |
| `postCleanerTemperature` | double | `0.3` | Cleaner temperature (existing). |
| `postCleanerMaxTokens` | int | `0` | Max tokens, 0 = auto (existing). |
| `postCleanerContinuityEnabled` | bool | `true` | Enable recent-history continuity check (Phase 1 behavior). |
| `postCleanerCharacterCheckEnabled` | bool | `false` | Enable character/world audit pass (Phase 2). Opt-in. |
| `postCleanerHistoryMessages` | int | `12` | Number of recent messages to include. |
| `postCleanerMaxCharsPerMessage` | int | `3000` | Max chars per history message. |

### 7.3 UI: Post-Building Menu

The POST-cleaner works **without Studio** — it only needs
`MemoryBookSettings.postCleanerEnabled`. Studio provides optional
`broadcastBlocks` and `studioOutputs`, but neither is required. The cleaner
settings therefore do not belong in the Studio menu.

Move all post-cleaner settings out of `studio_menu_dialog.dart` into a new
**Post-Building** entry in the MagicDrawer:

**MagicDrawer item** (`magic_drawer.dart`):

```dart
MagicDrawerItemDef(
  id: 'post-building',
  label: 'Post-Building',
  icon: Icons.cleaning_services_outlined,
),
```

**Post-Building dialog** (`post_building_menu_dialog.dart`):

```
[switch] POST-cleaner (anti-cliché rewrite)
[switch] Continuity check (recent history)
[switch] Character & world audit (extra sidecar call)
[tile]   Cleaner model: <inherit from write-loop>
[tile]   Cleaner temperature: 0.30
[tile]   Cleaner max tokens: Auto
[tile]   Cleaner timeout: 60s
[tile]   History messages: 12
[tile]   Max chars per message: 3000
```

**Studio menu** (`studio_menu_dialog.dart`) keeps only:
- Write-loop (trackers + memory drafts) switch
- Sidecar model selector (for write-loop only)
- Agent timeout (for write-loop only)
- Preset routing mode (Studio-specific)

### 7.4 Post-Cleaner Works Without Studio

Confirmed: the cleaner's only Studio dependency is `broadcastBlocks`, which
gracefully defaults to `const []` when no Studio config exists. The cleaner
also reads `lastAssistant.studioOutputs`, which is empty when generation did
not use Studio. Neither blocks the cleaner from running.

---

## 8. Code Touchpoints

### Settings split & UI migration

- `lib/core/models/memory_book.dart`
  - Add `postCleanerSource`, `postCleanerModel`, `postCleanerEndpoint`,
    `postCleanerApiKey`, `postCleanerTimeoutMs` (sidecar split).
  - Add `postCleanerContinuityEnabled`, `postCleanerCharacterCheckEnabled`,
    `postCleanerHistoryMessages`, `postCleanerMaxCharsPerMessage`.
  - Run `dart run build_runner build` after model changes.

- `lib/core/llm/sidecar_llm_client.dart`
  - Add `resolveConfigForCleaner` (or extend `resolveConfig` with a
    `PostCleanerSettings` override) that prefers `postCleanerModel` /
    `postCleanerEndpoint` / `postCleanerApiKey` / `postCleanerSource` /
    `postCleanerTimeoutMs` and falls back to the shared `sidecar*` fields
    when the cleaner-specific fields are empty/zero.

- `lib/core/llm/post_cleaner_service.dart`
  - Use the cleaner-specific config resolution instead of the shared
    `resolveConfig`.

- `lib/features/chat/widgets/post_building_menu_dialog.dart` (new)
  - New dialog hosting all post-cleaner settings: enable switch, continuity
    switch, audit switch, model selector, temperature, max tokens, timeout,
    history messages, max chars per message.

- `lib/features/chat/widgets/magic_drawer.dart`
  - Add `post-building` item to `_allItems`.
  - Add `case 'post-building'` to `_handleTap`.
  - Add `_showPostBuildingMenu()` method.

- `lib/features/chat/widgets/studio_menu_dialog.dart`
  - Remove the POST-cleaner switch, cleaner temperature, cleaner max tokens,
    and any cleaner-specific UI from the "Agentic memory (advanced)" section.
  - Keep write-loop switch, sidecar model selector (for write-loop), agent
    timeout (for write-loop), and preset routing mode.

- `lib/features/chat/services/generation_pipeline.dart`
  - Use `postCleanerHistoryMessages` instead of hardcoded `12`.
  - Use `postCleanerMaxCharsPerMessage` instead of hardcoded `3000`.
  - Conditionally skip continuity when `postCleanerContinuityEnabled = false`.

### Phase 2: Auditor + PromptPayload pass-through

- `lib/features/chat/services/chat_generation_service.dart`
  - Expose `PromptPayload` in the generation result.

- `lib/features/chat/services/generation_pipeline.dart`
  - Receive `PromptPayload` from `service.generate()`.
  - Pass it to `_runPostCleaner`.
  - `_runPostCleaner` extracts context fields from payload.
  - Conditionally calls `runCharacterAudit` when `characterCheckEnabled`.

- `lib/core/llm/post_cleaner_service.dart`
  - Add `runCharacterAudit` method.
  - Add `buildAuditPrompt` (visible for testing).
  - Add JSON parsing for auditor response.
  - Extend `runCleaner` with `auditIssues` parameter.
  - Extend `buildCleanerPrompt` with `auditNotes` section.

- `lib/core/llm/prompt_builder.dart`
  - Expose lorebook content assembly for reuse by the auditor.

- `test/post_cleaner_test.dart`
  - Tests for `buildAuditPrompt` (context inclusion, JSON instruction).
  - Tests for audit JSON parsing (ok, issues, malformed).
  - Tests for `buildCleanerPrompt` with `auditNotes` section.
  - Tests for `runCleaner` skipping audit when disabled or payload null.

---

## 9. Testing Plan

### Unit tests

- `buildAuditPrompt` includes character description, personality, scenario.
- `buildAuditPrompt` includes persona name and description.
- `buildAuditPrompt` includes lorebooks/memory/summary/arc/entity content when
  present, omits cleanly when absent.
- `buildAuditPrompt` includes recent chat history.
- `buildAuditPrompt` instructs JSON-only output.
- Audit JSON parsing: `{"ok": true}` → empty list.
- Audit JSON parsing: `{"ok": false, "issues": [...]}` → list of strings.
- Audit JSON parsing: malformed JSON → null (skip).
- `buildCleanerPrompt` with audit notes adds `CHARACTER CONSISTENCY NOTES`
  section.
- `buildCleanerPrompt` without audit notes omits the section (Phase 1 behavior
  preserved).
- Order: history → studio notes → audit notes → style rules → text.

### Integration scenarios

- Auditor finds no issues → cleaner runs as Phase 1.
- Auditor finds issues → cleaner receives them and can fix.
- `PromptPayload` is null → audit skipped, cleaner runs as Phase 1.
- `characterCheckEnabled = false` → audit skipped, cleaner runs as Phase 1.

### Manual validation

- Character acts against personality → auditor catches it, cleaner fixes.
- World fact contradicts lorebook → auditor catches it, cleaner fixes.
- Persona identity is wrong → auditor catches it, cleaner fixes.
- Character behaves correctly → auditor returns `{"ok": true}`, cleaner only
  cleans style.
- No crash when lorebooks/memory are empty.

---

## 10. Rollout

1. Add settings fields + `build_runner` regeneration.
2. Add UI switches/tiles in `studio_menu_dialog.dart`.
3. Expose `PromptPayload` from `ChatGenerationService`.
4. Wire `PromptPayload` through `GenerationPipeline` to `_runPostCleaner`.
5. Implement `runCharacterAudit` + `buildAuditPrompt`.
6. Implement audit JSON parsing.
7. Extend `buildCleanerPrompt` with `auditNotes` section.
8. Wire audit call in `_runPostCleaner` (conditional on `characterCheckEnabled`).
9. Run `flutter analyze` + `flutter test`.
10. Manual test on the Lucy/Afterlife session.

---

## 11. Success Criteria

The change is successful if:

- The auditor catches character/personality/world contradictions the Phase 1
  cleaner could not catch.
- The cleaner applies minimal fixes for auditor issues without expanding the
  scene.
- When the auditor finds no issues, behavior is identical to Phase 1.
- Only one `cleaned` swipe is produced — no third swipe.
- `PromptPayload` carries the full generation context without re-querying.
- Empty lorebooks/memory/summary do not crash the auditor.
- The auditor JSON parsing is robust to malformed responses.
- `flutter analyze` passes with no new errors.
- All existing tests continue to pass.
- Phase 1 behavior is preserved when `characterCheckEnabled = false`.

---

## 12. What Disappeared from the Old Plan

The old plan had a separate **Phase 2: Injected Memory Context** that described
how to persist or re-query injected memory blocks for the cleaner. This is no
longer needed because `PromptPayload` already contains `memoryContent`,
`memorySelection.entries`, `arcContent`, `entitiesContent`, and
`summaryContent`. By passing the full payload to the auditor, memory
verification is included automatically — no separate wiring phase required.

The old **Phase 3: Optional Strict Fact-Check Mode** is now the core
architecture (audit + clean two-pass flow), not an optional add-on.
