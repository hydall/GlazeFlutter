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
- **~~iOS JSONL import shows "No messages found" for SillyTavern files.~~** Fixed — iOS `FilePicker` doesn't expose accessible `file.path` in sandbox, so `File(path).readAsString()` returned empty string. Now uses `file.bytes` directly with `utf8.decode` fallback.

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

- **Android: magic drawer slow token recalculation.** Partially fixed — multiple optimizations applied:
  - Token breakdown cached in provider after each generation (drawer shows instantly if tokens already computed)
  - Eliminated 9-10 duplicate DB queries in `computeTokenStats` by reusing data from `computeStats` via `buildFromPreFetched`
  - Skip vector search (2-3 network calls) for drawer token counting; only used in tokenizer sheet
  - Reuse lorebook scan results from `computeStats` in `buildPrompt` via `preScannedEntries` field
  - Replaced `Flutter.compute()` with `Isolate.run()` for lighter isolate management
  - Added per-text token count cache (LRU, 2048 entries) in `tokenizer.dart`
  - Debounced `ref.listen` callback (300ms) to prevent rapid re-computation
  - Still recalculates from scratch on first open with no cached breakdown; no cross-session caching

- **~~Android: fresh APK only installs clean (uninstall first), update over existing install fails.~~** Fixed — CI builds now decode `DEBUG_KEYSTORE_BASE64` secret into a persistent `debug-key.keystore`, so all CI APKs are signed with the same key. DB `createTable`/`addColumn` collision on migration from early schemas still possible but rare.

- **No HTML rendering in chat.** Unresolved — need to research if HTML support was implemented. Messages containing HTML are displayed as raw text.

- **Persona not injected into chat after backup import (Android confirmed).** Bug — after restoring a backup, existing chats show persona as "user" (no avatar), even though the correct persona is selected. The persona's content is not being applied to the chat session. Likely cause: `personaId` in chat sessions or character settings is not being restored/linked correctly on import, or `activeSelectionProvider` doesn't pick up the persona for existing sessions.

- **Lorebook ghost entries after delete + recreate.** Suspected — when a lorebook imported with a character (PNG/JSON) is deleted and a new one with the same name/keys is created and linked, the old lorebook's data may still persist somewhere in the DB. In Glaze JS this manifests as stale entries appearing during generation. Need to investigate: (1) where imported lorebooks are stored in DB, (2) whether deletion fully removes all references (entries, vector embeddings, character↔lorebook links), (3) what happens when a new lorebook with overlapping keys is created after deletion. See also: cloud sync issue below.

- **API settings and presets may not sync to cloud.** Suspected — after configuring API settings and presets, pushing to cloud may not include them. Needs verification of cloud sync scope: which tables/fields are included in cloud push/pull.

- **Lorebooks may not appear in cloud after delete + recreate + push.** Suspected — specific case: lorebooks were imported with a PNG character, then deleted (they had truncated entries from a faulty merge script), then new lorebooks with same names/keys but corrected entries were created, formatted cloud, pushed to cloud — but lorebooks didn't appear on the cloud. Hypothesis: (1) imported lorebooks may be stored in a different table or with different ownership than manually created ones, (2) deletion may leave orphaned embedding rows that conflict with new entries, (3) cloud sync may only track changes since last sync and miss the delete+recreate pattern. Needs investigation of: lorebook storage model, cloud sync logic, and embedding cleanup on deletion.

- **~~iOS: black screen on character import after prior successful imports.~~** Fixed — root cause was `Navigator.pop(context, result)` targeting the branch navigator instead of root navigator when dismissing `GlazeBottomSheet` (which uses `useRootNavigator: true`). After several imports the navigation state would corrupt, sticking a modal on the root navigator and leaving `CharacterDetailSheetLauncher` as `SizedBox.shrink()` = black screen. Additional fixes: `CharacterDetailSheetLauncher` now shows loading spinner instead of `SizedBox.shrink`, has try-catch around modal, skips firing on sub-routes (`/edit`, `/gallery`), and returns to `/characters` on failure; added `context.mounted` checks after native iOS pickers return; added `onError` handler to `charactersProvider` stream; added `onException` fallback to GoRouter.

- **~~Character menu scrolls with lag.~~** Fixed — removed expensive `BackdropFilter` from every card (2 per card × N cards); simplified token badge background; kept token estimation but cleaned up expression.

- **~~Character detail screen crash (infinite height).~~** Fixed — `DraggableScrollableSheet` cannot live inside `GlazeBottomSheet` or as a route builder. Now opens via `showModalBottomSheet(isScrollControlled: true)` directly. Route `/character/:charId` uses `CharacterDetailSheetLauncher` which shows the sheet and returns to `/characters` on dismiss.

- **~~Bottom sheets inconsistent styling.~~** Fixed — replaced all `showModalBottomSheet` calls with `GlazeBottomSheet.show` for consistent glass-morphism styling. Removed dead code (`_PresetSheet`, `_ListSheet`, `_AddSheetOption`).

- **~~App rotates to landscape.~~** Fixed — locked to portrait orientation via `SystemChrome.setPreferredOrientations` in `main.dart`.

## Macros / Prompt Building

- **~~Single-brace macro aliases missing.~~** Fixed — `{char}`, `{description}`, `{scenario}`, `{personality}`, `{user}`, `{persona}`, `{mesExamples}` now resolve the same as their double-brace equivalents.

- **~~char_card block uses hardcoded labels instead of character content.~~** Fixed — `char_card` block now uses `rawContent` template from preset or falls back to raw `description` field, instead of hardcoded "Character Name:/Description:" labels.

## Macro Engine — Parity with Glaze JS

- **~~`macro_name` field not supported.~~** Fixed — `macroName` field added to Character model (DB v16), MacroContext, character importer/exporter, JS backup importer. `{{char}}` now resolves `macroName ?? charName` matching JS `char.macro_name || char.name`.

- **~~`{{reasoningPrefix}}`/`{{reasoningSuffix}}` no API fallback.~~** Fixed — macro engine now falls back to `<think` / `</think` (with closing `>`) matching JS `APISettings.js` defaults, instead of empty string.

- **`{{pick}}` uses match-text hash instead of counter.** JS increments `pickCount++` per pick, so two identical `{{pick::a::b}}` at different positions produce different results. Flutter hashes the macro text, so identical macros always produce the same result. JS also supports `__pick_version` session var for re-rolling all picks.

- **~~`_simpleHash` produces different results.~~** Fixed — changed from `& 0x7FFFFFFF` to `(hash | 0).toSigned(32)` → `.abs()` matching JS `|= 0` → `Math.abs`.

- **`{{date}}`/`{{time}}` not locale-aware.** JS uses `toLocaleDateString()`/`toLocaleTimeString()`. Flutter always produces ISO format (`2026-05-09`) and 24h time (`14:30:00`). Low priority — ISO format is unambiguous.

- **~~`{{roll}}` returns `"0"` on invalid dice expression.~~** Fixed — now returns the original dice string (e.g. `{{roll::invalid}}` → `"invalid"`), matching JS behavior.

## Upstream Merge History

| Commit | Description | PR |
|--------|-------------|----|
| `e1e37e7` | style text | Hydall direct |
| `1564fcc` | api selector fix | Hydall direct |
| `5d323d4` | lord help me (onboarding, UI rework) | Hydall direct |
| `ea0f9fd` | refactor: shared matching/utils, fix vector search & lorebook bugs | #25 |
| `55c6403` | refactor: extract glaze_matcher, fix character filter, fix probability roll | #25 |
| `b4558de` | UI | Hydall direct |
| `112c420` | Merge PR #24 (perf: magic drawer token stats) | #24 |
| `6e507c7` | Merge PR #23 (fix: iOS black screen on import) | #23 |
| `0890f9c` | Merge PR #21 (fix: CI debug signing) | #21 |
| `a35b252` | Merge PR #20 (fix: embedding cleanup on delete) | #20 |

## Character Import / Catalog

- **~~DataCat imports personality into wrong field.~~** Fixed — DataCat `variant=janitor_core` returns V2 spec field names. Now correctly maps `raw['description']` → `description`, `raw['personality']` → `personality`, `raw['creator_notes']` → `creatorNotes`.

- **~~Janitor/Janny/Chub personality mapped to description.~~** Fixed — Jai `personality` field = основное описание персонажа → our `personality` field, not `description`. `description` is only populated from V2 spec cards. Fixed in all three providers.

- **~~"Creator Notes" confusing label.~~** Fixed — renamed to "Short Description" in character editor, detail screen, and catalog preview. Model field remains `creatorNotes` for V2 spec compatibility.
