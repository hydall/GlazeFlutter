# Studio Prompt Filtering — Design-True Behavior

## Design intent (no toggle, just correct)

When Studio is enabled, the pipeline is:
1. Preset → blocks.
2. Blocks → routed to agents (each agent gets its slice).
3. CoT/reasoning templates → DROPPED (multi-agent pipeline IS the externalized reasoning).
4. Pre-gen agents run → produce briefs.
5. Main Responder (final agent) receives: its own shard + briefs + character context + memory + history → produces final reply.
6. POST-cleaner receives: the final reply + broadcast rules → cleans.

The bug: Main Responder ALSO receives the entire original preset via `staticContext` (default branch in `StudioContextBucketizer`). This:
- Leaks CoT blocks (that Studio explicitly dropped at decomposition).
- Duplicates every block that is already in some agent's `promptShard`.
- Bloats tokens (~20K extra per Main Responder call).

## What goes where — block taxonomy

### Blocks that should be in EXACTLY ONE place

These are "private" to a specific agent. The LLM router assigns them to one bucket, and that's it.

| Block type | Goes to | NOT to |
|-----------|---------|--------|
| `narrative_engine` (core narrative principles) | Narrative/agency agent | Main Responder staticContext |
| `anti_loop_system` | Anti-Loop & Prose Guard agent | Main Responder staticContext |
| `anti_cliche_filter` | Anti-Loop & Prose Guard agent | Main Responder staticContext |
| `sensory_enhancement` | Narrative agent | Main Responder staticContext |
| `anti_echo` | Anti-Loop & Prose Guard agent | Main Responder staticContext |
| `story_mode` | Narrative agent | Main Responder staticContext |
| `writer_style_mode` (Stephen King) | Narrative agent | Main Responder staticContext |
| `focus` (paragraph structure) | Narrative agent | Main Responder staticContext |
| `lumia_ghost` (meta-weaver rules) | Meta-Weaver agent | Main Responder staticContext |
| `genre_romantic` / `genre_fluff` | Narrative agent | Main Responder staticContext |
| `npcs_active` | World/NPC agent | Main Responder staticContext |
| `user_control` (Danvi autonomy) | Agency agent | Main Responder staticContext |
| `internal_test` / `test_mode` (jailbreaks) | Main Responder (final) | nowhere else — these are generation-context, not tracker concerns |
| `professional_standards` / `explicit_content_protocol` | Main Responder (final) | nowhere else — content rules apply to the visible reply, not to briefs |
| `task` / `response_structure` | Main Responder (final) | nowhere else — these define the final reply shape |
| `cot_gemini` (`<think_template>`) | DROPPED | nowhere — Studio IS the reasoning |
| `thinking_css` / `think` blocks | DROPPED | nowhere — same as CoT |
| `prefill` blocks | DROPPED for Studio runs | nowhere — prefill conflicts with Studio's "output a brief" contract for pre-gen agents and is redundant for Main Responder (which gets briefs instead of a prefill) |

### Blocks that SHOULD be duplicated (broadcast)

These are cross-cutting rules that must govern BOTH the final visible reply AND the POST-cleaner rewrite. They go to:
- Their primary agent (for the brief).
- Main Responder (so the final reply obeys them).
- POST-cleaner (so the rewrite obeys them).

| Block type | Primary agent | Also to |
|-----------|---------------|---------|
| `language` rules (`🇷🇺 LANGUAGE: Russian`) | Main Responder (final) | POST-cleaner via `broadcastBlocks` |
| `length` rules (`📏 LENGTH: Medium`) | Narrative agent (briefs length) | Main Responder + POST-cleaner |
| `ban_rules` / `Ban Rus` banlist | Anti-Loop & Prose Guard agent | Main Responder + POST-cleaner |
| `anti_echo` (also broadcast — prose quality) | Anti-Loop & Prose Guard | Main Responder + POST-cleaner |

`isBroadcastBlock` already identifies these (language, length, anti-loop/echo/cliché/slop, banlists). `_assignBlocks` already duplicates them into `final` bucket. `collectBroadcastBlocks` persists their verbatim content for POST-cleaner. **This part works.**

### Blocks that are CONTEXT, not rules

These are not "instructions" — they are the fictional context the model needs:

| Block type | Goes to | How |
|-----------|---------|-----|
| `char_card` (character description) | All agents (they need to know who they're writing about) | `staticContext` — via `mandatoryFallback` |
| `char_personality` | All agents | `staticContext` |
| `user_persona` | All agents | `staticContext` |
| `scenario` | All agents | `staticContext` |
| `example_dialogue` | Main Responder primarily | `staticContext` |
| `authors_note` | Main Responder primarily | `staticContext` (depth-positioned) |
| `memory` (MemoryBook) | All agents | `dynamicContext` |
| `summary` | All agents | `dynamicContext` |
| `lorebooks` / `worldInfoBefore` / `worldInfoAfter` | All agents | `dynamicContext` |
| Chat history | All agents (trimmed per agent.contextSize) | `history` |

These SHOULD stay in staticContext / dynamicContext / history. They are not in any agent's `sourceBlockNames` (the LLM router doesn't route them — they're handled by the bucketizer's static-id / dynamic-id / history branches).

## The fix

### What to filter from `staticContext` when Studio is enabled

After the bucketizer's existing classification, `staticContext` contains:
- Correct: char_card, char_personality, user_persona, scenario, example_dialogue, authors_note (via static-id branch + mandatory fallback). KEEP.
- BUG: all other preset blocks (narrative_engine, anti_loop_system, lumia_ghost, CoT, jailbreaks, language rules, etc.) via the default branch. **FILTER OUT**.

### Filter logic

For each message in `staticContext`, drop it if ANY of:
1. Its corresponding `PresetBlock` is a reasoning/CoT block (`StudioBlockClassifier.isReasoningBlock`).
2. Its `blockName` appears in ANY agent's `sourceBlockNames` — meaning it's already in some agent's `promptShard`.

After filtering, `staticContext` should contain ONLY the static-id blocks (char_card, char_personality, user_persona, scenario, example_dialogue, authors_note) and the mandatory fallback. Everything else is either in an agent shard or was dropped as CoT.

### Why this is correct

- **CoT blocks**: dropped at decomposition (not in any agent's sourceBlockNames). Pass 1 catches them by `isReasoningBlock`. They vanish from staticContext. ✓
- **Rule blocks (anti_loop, language, etc.) that are broadcast**: they ARE in Main Responder's sourceBlockNames (duplicated by `_assignBlocks` broadcast logic). Pass 2 catches them. They vanish from staticContext — but they're already in Main Responder's shard. ✓
- **Private rule blocks (narrative_engine, focus, story_mode)**: they are in their primary agent's sourceBlockNames (Narrative agent). Pass 2 catches them. They vanish from staticContext — but they're already in Narrative agent's shard, and that agent's brief carries their guidance to Main Responder. ✓
- **Jailbreak blocks (`internal_test`, `professional_standards`, `explicit_content_protocol`, `task`, `response_structure`)**: these should go to Main Responder (final bucket). Let me verify the LLM router actually puts them there. If yes → they're in Main Responder's sourceBlockNames → Pass 2 keeps them out of staticContext (they're in the shard). If no → they'd be filtered from staticContext and lost. Need to verify routing.
- **char_card etc.**: not in any agent's sourceBlockNames (router doesn't route them). Not CoT. Stay in staticContext. ✓
- **memory/summary/lore**: handled by dynamic-id branch, never reach staticContext. ✓

### Risk: jailbreak blocks routing

The critical question: does the LLM router (or keyword fallback) actually route jailbreak blocks (`internal_test`, `test_mode`, `professional_standards`, `explicit_content_protocol`, `task`, `response_structure`) to the `final` bucket?

Looking at `StudioBlockClassifier.bucketForBlock` (keyword fallback): none of these keywords match any bucket's needle list. They'd fall through to the default → `'final'`. So keyword fallback puts them in `final` — correct.

But the LLM router might classify them differently. If the LLM router puts `internal_test` in `meta` (because it mentions "test") or `guard` (because it mentions "restrictions"), they'd end up in the wrong agent's shard and Main Responder wouldn't see them. Then Pass 2 would filter them from staticContext and they'd be lost entirely.

This is a routing-quality issue. For now, the keyword fallback's default-to-`final` is a safety net. But to be robust, the filter should NOT drop a block from staticContext if it's a "jailbreak-style" block that must reach Main Responder. 

Actually — simpler: if a block is in Main Responder's own `sourceBlockNames`, it's already in Main Responder's shard. We only filter blocks that are in OTHER agents' sourceBlockNames (or are CoT). This way:
- Jailbreaks routed to `final` → in Main Responder's shard → not in staticContext (no duplication, but they're in the shard).
- Jailbreaks misrouted to `meta` → in Meta-Weaver's shard → NOT filtered from staticContext for Main Responder → Main Responder still sees them via staticContext. Wait, but that's the bug — we want to filter them.

Hmm. Let me think again.

The cleanest design: `staticContext` for a given agent should contain ONLY blocks that are NOT in ANY agent's sourceBlockNames (i.e., blocks the router didn't route — context blocks like char_card) + the mandatory fallback. Everything else is in some shard.

If a jailbreak is misrouted to `meta` instead of `final`, that's a routing bug — fix the router, not paper over it by leaking the block through staticContext. The router's keyword fallback already defaults to `final`, so misrouting only happens if the LLM router explicitly chooses another bucket. That's a rare case and should be addressed by improving the router's prompt, not by keeping the leak.

### Decision: filter ALL routed blocks from staticContext

For both pre-gen agents AND Main Responder: `staticContext` = preset blocks NOT in any agent's sourceBlockNames AND NOT CoT. This gives:
- char_card, char_personality, user_persona, scenario, example_dialogue, authors_note (context).
- Mandatory fallback (if any of the above were missing from the preset).
- Nothing else.

Pre-gen agents see: their own shard + char/persona context + memory/summary/lore + history. They don't see other agents' blocks, don't see CoT, don't see jailbreaks (those go to Main Responder's shard, not to pre-gen agents' staticContext).

Main Responder sees: its own shard (which includes broadcast blocks + jailbreaks + final-only blocks) + briefs + char/persona context + memory/summary/lore + history. Doesn't see CoT, doesn't see other agents' private blocks (they arrive via briefs).

This is the design.

## Implementation

### 1. Extend `StudioContextBucketizer`

```dart
StudioContextBuckets bucketize(
  PromptResult promptResult, {
  required PromptPayload promptPayload,
  StudioConfig? studioConfig, // NEW — when non-null, filter staticContext
}) {
  // ... existing classification ...

  // NEW: filter staticContext when Studio is active
  if (studioConfig != null) {
    final routedBlockNames = _collectRoutedBlockNames(studioConfig);
    final reasoningBlockNames = _collectReasoningBlockNames(promptPayload.preset);
    final dropNames = routedBlockNames.union(reasoningBlockNames);
    staticContext = staticContext.where((m) {
      final name = m.blockName ?? '';
      final id = m.blockId ?? '';
      return !dropNames.contains(name) && !dropNames.contains(id);
    }).toList();
  }

  // ... rest unchanged ...
}

Set<String> _collectRoutedBlockNames(StudioConfig config) {
  final names = <String>{};
  for (final agent in config.agents) {
    names.addAll(agent.sourceBlockNames);
  }
  return names;
}

Set<String> _collectReasoningBlockNames(Preset? preset) {
  if (preset == null) return {};
  return preset.blocks
      .where(StudioBlockClassifier.isReasoningBlock)
      .map((b) => b.name)
      .toSet();
}
```

Match by `blockName` AND `blockId` (the bucketizer message has both, routed names are display names, reasoning detection uses the PresetBlock which has both).

### 2. Pass `StudioConfig` from `MemoryStudioService`

Every call to `bucketizer.bucketize(promptResult, promptPayload: payload)` should pass the `StudioConfig` that's being used for the current run. The service has it.

### 3. Tests

- Unit: `StudioContextBucketizerTest` — given promptResult with messages from CoT block + narrative_engine block + char_card, and a StudioConfig with agents whose sourceBlockNames include `narrative_engine`, assert staticContext contains only char_card (via fallback), CoT and narrative_engine are filtered.
- Unit: broadcast block in Main Responder's sourceBlockNames → filtered from staticContext (it's in the shard).
- Unit: jailbreak block routed to `final` → in Main Responder's sourceBlockNames → filtered from staticContext (in shard). Jailbreak misrouted to `meta` → in Meta-Weaver's sourceBlockNames → filtered from staticContext for ALL agents (including Main Responder). This is the "routing bug" case — document it but don't paper over it.

### 4. Files

- `lib/core/llm/studio_context_bucketizer.dart` — add `StudioConfig?` param, implement filter.
- `lib/core/llm/memory_studio_service.dart` — pass `StudioConfig` to bucketizer.
- `test/studio_context_bucketizer_test.dart` (new) — unit tests.

### 5. Out of scope

- LLM router quality (jailbreak misrouting to meta). Separate concern.
- Main Responder shard bloat from broadcast duplication. Separate concern — by design, broadcast blocks SHOULD be in Main Responder's shard.
- `prompt_builder.dart` CoT filtering for non-Studio runs. NOT needed — non-Studio runs want CoT.

## Lumia architecture in Studio

Lumia (meta-weaver / OOC interface) has two behaviors:
1. **OOC responses** — when the user explicitly addresses Lumia in OOC brackets / meta request.
2. **Periodic commentary** — "Every N assistant responses, if it would not disrupt the scene, append a short Lumia OOC note after the narrative." N is defined in the `<lumia_ghost>` block (e.g. "Every 4 assistant responses"). Not hardcoded — the user can change it to 10 or any interval.

### Design

1. **Meta-Weaver agent** — runs EVERY turn (`refreshPolicy: 'turn'`, not `'static'`). Its `contextSize` must be large enough to count the period (≥ N+2 messages, so 12-15 for a period of 10). Its shard contains the `<lumia_ghost>` block (rules of engagement + period + format). On each turn it:
   - Counts assistant messages in the history it sees.
   - Decides: is this the Nth turn? Is there an OOC address? Should Lumia stay silent?
   - Produces a brief: "lumia_ooc: due | topic: X" OR "lumia_periodic_note: due | last note Y turns ago | keep it 1-3 sentences, useful, not scene-stealing" OR "lumia: silent".
2. **Main Responder** — receives the Meta-Weaver brief + a compact Lumia output contract in its shard (format + voice, NOT the full `<lumia_ghost>`). **Decides itself** based on the brief whether to emit `<lumiaooc>` and **writes the actual OOC reply itself**.
3. **PostCleaner** — preserves `<lumiaooc>` blocks.

### Why Meta-Weaver counts (not the code)

The period interval lives in the `<lumia_ghost>` block text ("Every 4 assistant responses" / "Every 10"). It's a user-editable parameter, not a hardcoded constant. Only the LLM reading the block can extract it. Counting in code would require parsing the block text for the interval — brittle. Letting Meta-Weaver read the block + count the history it sees is the natural design: one LLM call, deterministic-ish output (counting is mechanical, the decision is simple).

### Changes for Lumia

**Part A — Meta-Weaver runs every turn**:
- `studio_controller_ontology.dart`: change Meta-Weaver's `refreshPolicy` from `'static'` to `'turn'`.
- `studio_controller_ontology.dart`: bump Meta-Weaver's `contextSize` default (currently inherits the global default of 5) to 15 — enough to count periods up to 10.
- `studio_shard_synthesizer.dart`: when synthesizing Meta-Weaver's shard and `lumia_ghost` is assigned, emphasize the counting duty: "Count assistant messages in the provided history. Apply the period rule from the block. Output `lumia_periodic_note: due` / `lumia_ooc: due` / `lumia: silent` in your brief."

**Part B — Main Responder compact Lumia contract**:
- `studio_shard_synthesizer.dart`: when `lumia_ghost` is in Meta-Weaver's assignment, emit a compact Lumia output contract into Main Responder's shard: format (`<lumiaooc>\n<font color="#9370DB">...</font>\n</lumiaooc>`), voice (warm, maternal, useful, 1-3 sentences, not scene-stealing), emit-when-brief-says-due. NOT the full `<lumia_ghost>` block.

**Part C — PostCleaner preserves `<lumiaooc>`**:
- `post_cleaner_service.dart`: add `<lumiaooc>` to protected-markup. If original had `<lumiaooc>` and cleaned doesn't, reject rewrite.
- Cleaner prompt: "Preserve any `<lumiaooc>` blocks verbatim — meta-OOC commentary, not narrative prose. Do not rewrite, move, or delete them."

### Existing Studio config migration

Existing Studio configs (like Lucy's) have Meta-Weaver with `refreshPolicy: 'static'` and `contextSize: 5` baked into the serialized `StudioAgent`. After changing the spec defaults, old configs still have the old values. Two options:
1. **Migration**: when loading a StudioConfig, if Meta-Weaver agent has `refreshPolicy: 'static'`, upgrade it to `'turn'` and bump `contextSize` to 15. This is a one-time normalization in `StudioConfigRepo` or `MemoryStudioService`.
2. **Rebuild**: the user clicks "Rebuild Studio" and gets the new defaults. Simpler but requires user action.

I'll do option 1 — silent migration on load, so existing configs benefit immediately.

### Updated implementation plan

1. `studio_context_bucketizer.dart` — filter staticContext (CoT + routed blocks).
2. `memory_studio_service.dart` — pass StudioConfig to bucketizer.
3. `studio_controller_ontology.dart` — Meta-Weaver: `refreshPolicy: 'turn'`, `contextSize: 15` (new field on spec, currently contextSize is not on the spec — it's a default on StudioAgent; need to add it).
4. `studio_shard_synthesizer.dart` — Meta-Weaver: counting duty emphasis. Main Responder: compact Lumia contract when lumia_ghost is in Meta-Weaver's assignment.
5. `post_cleaner_service.dart` — preserve `<lumiaooc>` blocks.
6. StudioConfig migration on load — upgrade old Meta-Weaver agents to new refreshPolicy + contextSize.
7. Tests for all of the above.
