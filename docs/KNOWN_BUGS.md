# Known Bugs

## Memory Books

- **No UI for manual memory creation.** The "Add Memory" action may be hidden when there's no draft, but manual creation should always be available.

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
