# Known Bugs

## Memory Books — major feature gap vs Glaze JS

Flutter's MemoryBooksSheet is a minimal stub. Glaze JS has a full draft-based workflow with 7 sheets and 8 composables. Missing features:

- **Draft system entirely missing.** JS has `pendingDrafts[]` with statuses `pending_generation` → `needs_regeneration` → approved. Flutter has no draft concept at all.
- **Scan Chat (auto-split into drafts).** JS splits uncovered messages into segments of N, creates draft placeholders per segment. Flutter has no scan/split UI.
- **Batch generation.** JS generates multiple drafts in parallel (configurable batch size). Flutter has no generation UI — only manual entry creation.
- **Single draft generation / regeneration.** Each draft can be generated individually or regenerated if `needs_regeneration`. Flutter has nothing.
- **Approve / delete draft.** JS lets you review draft content before approving into an active entry. Flutter only has raw add/edit/delete.
- **Model selection for memory generation.** JS has quick model selector (fetches models from API), plus "Use LLM API" toggle with separate endpoint/model/key fields. Flutter has these fields in settings but no model selector and no provider integration.
- **Generation prompt presets.** JS has `MemoryPromptManagerSheet` with custom prompt templates (detailed_beats, etc.) + preview. Flutter has no prompt management.
- **Search type selector.** JS has vector / keys / combined selector with cycle. Flutter only has settings toggle.
- **Maintenance / reindex.** JS has dedicated maintenance sheet + reindex-all. Flutter has neither.
- **Coverage / stale tracking.** JS tracks `staleCoverageCount`, `needs_rebuild` status, uncovered segments. Flutter has no coverage tracking.
- **Draft progress.** JS shows generating state with elapsed time, cancel button. Flutter has no progress UI.

## Backup Import

- **Duplicate template API config created on recover.** Importing a backup creates an extra API config entry (embedding template) that shouldn't exist.
- **IMG-GEN API key not restored from backup.** Image generation API keys (RoutMy, Naistera, etc.) are not properly recovered from JS backups.

## Tokenizer / Prompt Counting

- **Stale token counts after hide/unhide.** Tokenizer doesn't recalculate when messages are hidden/unhidden — requires re-entering the session to refresh.
- **Preset tokens counted before macro expansion.** Preset contribution is always counted pre-expansion, inflating the token count.
- **No per-source token breakdown.** Tokenizer shows a single total but doesn't break down into summary / persona / character / lorebook / history etc. like the prompt fill indicator does.
- **Tokenizer total ≠ prompt fill indicator.** Tokenizer shows ~87k while the request preview shows ~69k for the same session — discrepancy likely caused by macro expansion and regex application differences.

## Regex

- **Preset-level regexes not connected to presets.** Regex scripts from presets should be tied to their parent preset — toggled and applied together (two tiers: global regexes + preset-level regexes). Currently after a backup import, regexes from all presets are mixed into one flat list.
- **Scroll resets on regex toggle.** Enabling/disabling a regex always scrolls to the top of the regex list page.

## UI

- **Character menu scrolls with lag.** The character list/menu has noticeable scroll latency/jank.
