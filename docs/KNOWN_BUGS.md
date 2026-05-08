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

## Image Generation

- **~~img-gen crashes with `String` → `bool?` cast error.~~** Fixed — `js_backup_importer.dart` now stores booleans as `setBool` instead of `setString`; `_migrateFromJsKeys` and `_fromJson` use safe `_castBool`/`_safeBool` helpers that handle string values.

## Memory Books

- **~~Memory books not imported from backup.~~** Fixed — `js_chat_importer.dart` now handles JSON-string encoded `memoryBooks`, imports `pendingDrafts`, and supports List format entries.
- **~~Memory books lag/crash on settings open/close.~~** Fixed — replaced `DropdownButton<int>` with 32,001 items with `TextFormField`; stored `TextEditingController`s as instance fields instead of recreating per build.
- **~~Memory books scan only 3 drafts for ~150 messages.~~** Fixed — `_scanChat` now includes the last partial segment and uses looser duplicate detection.
- **~~Memory books generation returns 401.~~** Fixed — `MemoryDraftGenerator` now uses `activeApiConfigProvider` instead of picking a random non-embedding config.

- **~~No custom prompt manager.~~** Fixed — `CustomPromptManagerSheet` with add/edit/delete UI; `MemoryPromptPresets.resolve()` and `label()` now accept custom presets; settings sheet shows built-in + custom sections with "Manage prompts" button.
- **~~No quick model selector.~~** Fixed — model text field now has a fetch button that calls `/models` endpoint and shows a picker.

## Backup Import

- **~~iOS backup import crashes with FileType.custom error.~~** Fixed — `backup_screen.dart` was using `FileType.any` with `allowedExtensions`, which iOS rejects. Changed to `FileType.custom`.
- **~~Duplicate template API config created on recover.~~** Fixed — moved `topLevel['apiPresets']` extraction before the `presets.isEmpty` fallback, so the "Default" template is only created when no presets exist from any source.
- **~~IMG-GEN API key not restored from backup.~~** Fixed — (1) remove `gz_imggen_settings` during import so migration re-runs; (2) extended `_migrateFromJsKeys()` to read 12 more fields (routmy/naistera model, aspectRatio, quality, sendAvatar, gemini size, ru-routmy key).

- **~~iOS can't select .glz backup files.~~** Fixed — all file pickers now use `FileType.any` on iOS and `FileType.custom` on other platforms.
- **~~PNG character import uses file picker instead of gallery on iOS.~~** Fixed — iOS now uses `image_picker` to open the photo gallery; other platforms keep file picker.
- **~~JSONL chat import doesn't work on iOS.~~** Fixed — same FileType fix as .glz backups.

## Tokenizer / Prompt Counting

- **~~Stale token counts after hide/unhide.~~** Fixed — added `ref.listen(chatProvider)` in TokenizerSheet, MagicDrawerPanel, ContextInfoSheet, PromptPreviewScreen to auto-recalculate when session changes. Also fixed `historyText` to exclude hidden messages.
- **~~Preset tokens counted before macro expansion.~~** Fixed — root cause was `blockId` lost in `_assembleMessages`. All `PromptMessage` objects got `id: 'static'`, so `_sourceForBlock` defaulted everything to `'preset'`. Now each message carries its actual blockId (`char_card`, `persona`, `summary`, `lorebook`, `memory`, etc.) and token breakdown is accurate per source.
- **~~No per-source token breakdown.~~** Fixed — same root cause as above. Now `_sourceForBlock` correctly maps block IDs including `memory` and `char_depth_prompt`.
- **~~Tokenizer total ≠ prompt fill indicator.~~** Fixed — was a symptom of stale token counts (now auto-refreshed via `ref.listen`) and misattributed blockId (now correctly mapped per source).
- **~~Tokenizer only shows author's note, chat history, preset.~~** Fixed — now shows character, persona, summary, memory, lorebook (with X / Y reserve), vector lorebook.
- **~~No Author's Note button in magic drawer quick access.~~** Fixed — added "Author's Note" item with inline editor (content, role, insertion mode, depth, enabled toggle).

## Chat Import

- **~~Imported chat doesn't open automatically.~~** Fixed — `ChatActionsService.importChat()` now updates `character.currentSessionIndex` so the provider navigates to the imported session.
- **~~Chat history screen opens wrong session.~~** Fixed — `_SessionTile.onTap` now passes `?session=sessionIndex` query param so `ChatScreen` switches to the correct session.
- **~~JSONL import ignores ISO-8601 timestamps.~~** Fixed — `_parseSTDate` now splits on `T` separator (e.g. `2026-04-27T01:23:00.000`), not just spaces/colons. Previously all imported messages got `DateTime.now()` as timestamp.

## Chat Export

- **~~Chat export crashes on iOS (PathNotFoundException).~~** Fixed — was writing to `~/Desktop` which doesn't exist on iOS. Now writes to temp dir and opens share sheet (`Share.shareXFiles`) so user can save/share the file.

## Sort / Timestamps

- **~~Backup import: characters in reverse order.~~** Fixed — `js_character_importer` now sorts characters by original timestamp (oldest first), then assigns fresh sequential `updatedAt` values preserving relative order.
- **~~Backup import: updatedAt fallback used milliseconds.~~** Fixed — `DateTime.now().millisecondsSinceEpoch` replaced with `currentTimestampSeconds()`. Also detects ms timestamps (>1e12) and converts to seconds.
- **~~New character import appears at bottom of list.~~** Fixed — `character_importer.dart` uses `currentTimestampSeconds()` for `updatedAt` so newly imported characters sort to top under "Newest".
- **~~Sort direction arrow unclear.~~** Fixed — replaced `AnimatedRotation` arrow icon with text labels "Newest" / "Oldest".

## Regex

- **~~Preset-level regexes not connected to presets.~~** Fixed — two-tier system: active preset regexes + global regexes merged at prompt-build time. Regex list now shows sections. JS backup `regex_scripts` imported to global tier.
- **~~Scroll resets on regex toggle.~~** Fixed — replaced FutureBuilder+invalidate with `presetsListProvider` + `skipLoadingOnReload: true` + `PageStorageKey`.

## UI

- **Android: magic drawer takes forever to load (first and subsequent opens).** Unresolved — likely infinite/retry loop in token counting or provider rebuild storm when magic drawer opens.
- **Android: fresh APK only installs clean (uninstall first), update over existing install fails.** Unresolved — likely DB schema migration issue or signing key mismatch between debug builds.

- **~~Character menu scrolls with lag.~~** Fixed — removed expensive `BackdropFilter` from every card (2 per card × N cards); simplified token badge background; kept token estimation but cleaned up expression.

- **~~Character detail screen crash (infinite height).~~** Fixed — `DraggableScrollableSheet` cannot live inside `GlazeBottomSheet` or as a route builder. Now opens via `showModalBottomSheet(isScrollControlled: true)` directly. Route `/character/:charId` uses `CharacterDetailSheetLauncher` which shows the sheet and returns to `/characters` on dismiss.

- **~~Bottom sheets inconsistent styling.~~** Fixed — replaced all `showModalBottomSheet` calls with `GlazeBottomSheet.show` for consistent glass-morphism styling. Removed dead code (`_PresetSheet`, `_ListSheet`, `_AddSheetOption`).

- **~~App rotates to landscape.~~** Fixed — locked to portrait orientation via `SystemChrome.setPreferredOrientations` in `main.dart`.

## Macros / Prompt Building

- **~~Single-brace macro aliases missing.~~** Fixed — `{char}`, `{description}`, `{scenario}`, `{personality}`, `{user}`, `{persona}`, `{mesExamples}` now resolve the same as their double-brace equivalents.

- **~~char_card block uses hardcoded labels instead of character content.~~** Fixed — `char_card` block now uses `rawContent` template from preset or falls back to raw `description` field, instead of hardcoded "Character Name:/Description:" labels.

## Character Import / Catalog

- **~~DataCat imports personality into wrong field.~~** Fixed — DataCat `variant=janitor_core` returns V2 spec field names. Now correctly maps `raw['description']` → `description`, `raw['personality']` → `personality`, `raw['creator_notes']` → `creatorNotes`.

- **~~Janitor/Janny/Chub personality mapped to description.~~** Fixed — Jai `personality` field = основное описание персонажа → our `personality` field, not `description`. `description` is only populated from V2 spec cards. Fixed in all three providers.

- **~~"Creator Notes" confusing label.~~** Fixed — renamed to "Short Description" in character editor, detail screen, and catalog preview. Model field remains `creatorNotes` for V2 spec compatibility.
