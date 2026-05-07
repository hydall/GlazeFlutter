# Known Bugs

## Vector / Embedding

- **~~Memory book embeddings entirely missing.~~** Fixed — `MemoryEmbeddingService` + vector search in `MemoryInjectionService` + reindex/clear UI in MemoryBooksSheet.
- **~~No rate limit cooldown UI.~~** Fixed — lorebook editor shows countdown after 429.
- **~~No error classification for embeddings.~~** Fixed — `EmbeddingErrorLabel.classify()` with 8 types, shown as tooltip on error badge in entry list.
- **~~No freshness check during vector search.~~** Fixed — `LorebookVectorSearch` now verifies `textHash` against current entry content and skips stale vectors.
- **~~`embeddingTarget` setting is a no-op.~~** Fixed — `LorebookEmbeddingService` now respects per-lorebook `embeddingTarget` (content/keys).
- **~~No "Delete All Indexes" button.~~** Fixed — added to lorebook editor toolbar.
- **~~No "Retry Failed" button.~~** Fixed — added to lorebook editor toolbar.
- **~~`characterFilter` not applied during vector search.~~** Fixed — entries with character filters are now excluded.
- **~~`keywordVectorSplit` unused.~~** Already implemented in `lorebook_merger.dart`.

## Memory Books

- **No custom prompt manager.** JS has `MemoryPromptManagerSheet` to add/edit/delete custom prompt templates. Flutter only has built-in presets.
- **No quick model selector.** JS fetches models from the API and shows a picker. Flutter only has a text field for model name.

## Backup Import

- **~~iOS backup import crashes with FileType.custom error.~~** Fixed — `backup_screen.dart` was using `FileType.any` with `allowedExtensions`, which iOS rejects. Changed to `FileType.custom`.
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
