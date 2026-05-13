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
- **~~`initEmbeddingConfigFromDb` never called — vector search/reindex always says "check settings".~~** Fixed — added call in `loadActiveSelections()` so `embeddingConfigProvider` is populated from API config on startup.

### Vector Search Architecture (parity with Glaze JS)

**Algorithm: MaxSim** — `findTopKMulti()` in `vector_math.dart` matches JS exactly:
- Each entry is chunked → multiple vectors stored per entry
- Query is also chunked (focused + fallback)
- Score = `max(cosineSimilarity(q, c))` across all (query_chunk, candidate_chunk) pairs
- This is NOT average pooling — a single highly relevant paragraph in a long entry can trigger retrieval

**Flow (matches JS):**
1. Query construction: focused (user messages + current text, ~1024 tokens) + fallback (all recent, ~1536 tokens)
2. Query chunks embedded via API
3. MaxSim against all indexed candidates
4. Hybrid boost: keyword overlap with entry comment (+0.18), keys (+0.04/key, max +0.12), retrieval hints (+0.025/hint, max +0.10)
5. Merge focused + fallback (best score wins per entry)
6. Filter by `vectorThreshold`, take top K

**Known difference from JS:** `getEmbeddings()` (single-vector path) averages multi-chunk vectors into one. This is used only by `memory_embedding_service.dart`. Lorebook search uses `getEmbeddingsWithChunks()` which preserves all chunks — correct.

## Cloud Sync

- **Session index collision on delete + recreate.** Steps: (1) Push sessions to cloud. (2) Delete a session locally. (3) Create a new session — it reuses the deleted session's index number. (4) Push or pull. On pull, the old session should reappear (it still exists in cloud). On push, the new session should overwrite. Currently no tracking of which records were intentionally deleted, so cloud ghosts may accumulate. **Proposed fix:** Add a `pendingDeletions` list to the sync manifest. On push: (1) apply pending deletions to cloud, (2) remove entries from manifest, (3) push new/updated records. Same logic applies to lorebooks, characters, and other synced entities. Alternative: use UUID-based IDs instead of sequential indices so collisions are impossible — but this requires migration.

## Lorebook / Export

- **~~Lorebook may be missing from PNG export after delete + recreate.~~** Fixed — PNG and JSON exports now always include character-scoped lorebooks. `lorebookToCharacterBookJson()` converts Lorebook model to V2 `character_book` format. Export queries lorebooks by `activationScope == 'character' && activationTargetId == charId`. Multiple character-scoped lorebooks are merged into one book.

- **Lorebook activation dual-system not synced.** Two independent systems track which lorebooks are "character-scoped": (1) DB fields `activationScope`/`activationTargetId` on the Lorebook row, set on import. (2) `lorebookActivations` SharedPreferences map, updated via connections sheet UI. Neither updates the other. Import creates DB entries but not SharedPreferences entries; UI linking creates SharedPreferences entries but not DB entries. The runtime scanner (`lorebook_scanner.dart`) only checks `lorebookActivations` for disabled lorebooks; enabled lorebooks are always active regardless. **Impact:** Low for runtime, but export only checks DB fields, so lorebooks linked only via UI won't be exported.

## Chat / Sessions

- **~~No rename session.~~** Fixed — `renameSession()` in `ChatHistoryNotifier`, rename menu item + dialog in `chat_history_screen.dart` and `magic_drawer.dart`. Name stored in `sessionVars['sessionName']`, no DB migration needed. Magic drawer now displays `sessionName` instead of `Session #N`.

- **~~Enter to Send not wired.~~** Fixed — `ChatInputBar.focusNode.onKeyEvent` sends on Enter (without Shift) when `enterToSend` is enabled. Shift+Enter inserts newline. Virtual keyboard send also works via `TextInputAction.send`.

## Theme

- **~~Theme preset only applied accent color.~~** Fixed — `GlazeColors.fromPreset()` now maps all 30+ preset properties: bubble colors, text/quote/italic colors per role, uiColor, borderColor. Auto-contrast `_contrastFor()` picks dark/light text based on bubble luminance when no explicit text color in preset. `_distinctBubble()` lightens charBubble when it matches uiColor/background.

- **~~Bubble colors wrong.~~** Fixed — user bubble uses `colors.userBubble` (was `colors.background`), char bubble uses `colors.charBubble` (was `colors.accent`). Meta text (name, tokens, time) uses `userText/charText` at 0.6 alpha for contrast on colored bubbles.

- **~~No bgImage support.~~** Fixed — `bgImageProvider` decodes base64 data URI, saves to disk, renders as `Image.file` with `bgOpacity`.

- **~~No custom font support.~~** Fixed — `ui.loadFontFromList()` loads base64 fonts at runtime. `chatFontFamilyProvider`/`uiFontFamilyProvider` feed into `GptMarkdown` fontFamily and `AppTheme` fontFamily.

- **~~No font size/letter spacing.~~** Fixed — `chatFontSize`/`chatLetterSpacing` applied to `GptMarkdown` TextStyle. `uiFontSize`/`uiLetterSpacing` applied to global `textTheme.apply()`.

- **~~No element opacity/blur.~~** Fixed — `elementOpacity` → bubble bg alpha, `elementBlur` → `ClipRRect`+`BackdropFilter` wrap.

- **~~No border customization.~~** Fixed — `borderWidth`/`borderColor`/`borderOpacity` from preset applied to bubble `BoxDecoration.border`.

- **~~No noise overlay.~~** Fixed — `NoiseOverlay` CustomPaint with `noiseOpacity`/`noiseIntensity` (element) and `bgNoiseOpacity`/`bgNoiseIntensity` (background).

- **~~Italic/bold text not colored.~~** Fixed — `ColoredItalicMd`/`ColoredBoldMd` inline components pass `italicColor` from theme preset to `TextStyle.color`.

- **~~Buttons invisible on dark accent themes.~~** Fixed — ElevatedButton foreground auto-contrasts with accent (was hardcoded `Colors.black` — invisible on dark_gray `#3d3d3d`, dark_red `#720A15`, etc). `_ensureButtonContrast()` shifts accent lightness until 4.5:1 (WCAG AA) contrast with surface.

- **~~Theme only visible in chat bubbles when uiColor is null.~~** Fixed — `_deriveUiColor()` creates a dark muted version of accent for dark mode (low sat, 15% lightness) and a light tinted version for light mode when `uiColor` is null (e.g. frutiger_aero).

- **~~Theme colors not propagating to non-chat UI.~~** Fixed — migrated from custom `GlazeColors` ThemeExtension to `ColorScheme`. Base UI colors (accent→primary, textPrimary→onSurface, textSecondary→onSurfaceVariant, background→surface, surfaceHigh→surfaceContainerHighest, border→outline, glassBorder→outlineVariant) now in ColorScheme. Material widgets pick them up automatically. `GlazeColors` slimmed to chat-specific fields only (userBubble, charBubble, userText/charText, userQuote/charQuote, userItalic/charItalic, accent).

- **~~Nav bar active tab darker/invisible on dark themes.~~** Fixed — active tab color auto-corrects when accent luminance direction mismatches surface: dark accent on dark bg → lightened, light accent on light bg → darkened.

- **~~Theme screen import button / "Active" label invisible.~~** Fixed — OutlinedButton→ElevatedButton with `_contrastColor()` (4.5:1 guarantee). "Active" label and check icon use `_contrastColor()` instead of raw `primary`.

- **~~Backup import button invisible.~~** Fixed — OutlinedButton→ElevatedButton (inherits `_ensureButtonContrast` from theme).

## API Settings

- **~~401 on generation — wrong API config used.~~** Fixed — 6 locations fetched first DB config instead of user-selected `activeApiConfigProvider`. If first config had empty key, `Authorization: Bearer ` header was rejected by CDN/proxy with 401 without forwarding to origin. All locations now use `activeApiConfigProvider`. Also: empty API key validation in `SseClient`, URL `/v1` prefix handling consolidated in `SseClient.buildChatUrl()`.

- **~~Theme font loading crashes on invalid data URI.~~** Fixed — `_loadFontFromBase64` now strips `data:...;base64,` prefix before decoding, and validates decoded bytes against font magic numbers (TTF/OTF/WOFF/WOFF2/TTC). Corrupted font data (e.g. HTML page saved as font) is silently skipped instead of crashing.

- **~~Generation errors shown as unclosable AlertDialog.~~** Fixed — errors now appear as chat messages with copy button (matching Glaze JS), using `_ErrorWindow` in `message.dart`. Auto-dismissing toast for transient errors.

- **~~API settings not saved — 3 bugs.~~** Fixed — (1) `_flushSave()` before navigation and in `dispose()` instead of `cancel()`. (2) `_toCompanion()`/`_toModel()` now include `omitTemperature`, `omitTopP`, `omitReasoning`, `omitReasoningEffort`. (3) `activeApiPresetIdProvider` now loads from SharedPreferences on startup; `_persistActiveId()` saves on switch.

- **~~Duplicate embedding API profile on backup import.~~** Fixed — Path 1: profiles with `mode: embedding/image_gen/memory_books` are skipped; when `serviceProfileMap` is null, embedding profile is detected and merged into LLM config. Path 2: embedding presets are merged into the first chat config instead of creating a separate profile.

## Android Performance

- **~~CI builds debug APK.~~** Fixed — `build-branch.yml` now uses `flutter build apk --release`.

- **~~Unthrottled streaming updates.~~** Fixed — `chat_generation_service.dart` now uses `SchedulerBinding.instance.scheduleFrameCallback` to throttle state updates to once per frame (~16ms). Tokens accumulate in the `StreamAccumulator` between frames without triggering Riverpod notifications.

- **~~No RepaintBoundary.~~** Fixed — `RepaintBoundary` wraps the `MessageList` in `chat_screen.dart` and the streaming `Message` widget in `message_list.dart`, preventing full-screen repaints on every streaming token.

## Prompt Building

- **~~Character card content injected with labels instead of raw content.~~** Investigated — `char_card` block correctly uses `rawContent` or falls back to `char.description` without labels. No "Character Name:"/"Character Description:" labels found in the pipeline. The only label injection is in `user_persona` which adds "User Name:"/"User Description:" — this is intentional.

## Image Generation

- **~~img-gen crashes with `String` → `bool?` cast error.~~** Fixed — `js_backup_importer.dart` now stores booleans as `setBool` instead of `setString`; `_migrateFromJsKeys` and `_fromJson` use safe `_castBool`/`_safeBool` helpers that handle string values.

## Memory Books

- **~~Memory books not imported from backup.~~** Fixed — `js_chat_importer.dart` imports `memoryBooks` from each chat session's data, including entries, settings, and pending drafts. Fixed `createdAt`/`updatedAt` type mismatch (String→int) and `messageRange` format incompatibility (JS `{startMessageId,endMessageId}` → Flutter `{start:int,end:int}`, incompatible ranges skipped).

- **~~Memory badge on every message.~~** Fixed — badge was counting `memoryCoverage` map keys (`entryIds`, `needsRebuild`, `stale` = 3) instead of actual entry IDs. Now reads `memoryCoverage['entryIds'].length`. Also unified the coverage format between `prompt_payload_builder` and JS backup (`{entryIds: [...], needsRebuild, stale}`).
- **~~Memory books lag/crash on settings open/close.~~** Fixed — replaced `DropdownButton<int>` with 32,001 items with `TextFormField`; stored `TextEditingController`s as instance fields instead of recreating per build.
- **~~Memory books scan only 3 drafts for ~150 messages.~~** Fixed — two causes: (1) `!m.isHidden` filter excluded hidden messages from scan, removed; (2) per-session `MemoryBookSettings` replaced with global `memoryGlobalSettingsProvider`.
- **~~Memory books generation returns 401.~~** Fixed — `MemoryDraftGenerator` now uses `activeApiConfigProvider` instead of picking a random non-embedding config.

- **~~No custom prompt manager.~~** Fixed — `CustomPromptManagerSheet` with add/edit/delete UI; `MemoryPromptPresets.resolve()` and `label()` now accept custom presets; settings sheet shows built-in + custom sections with "Manage prompts" button.
- **~~No quick model selector.~~** Fixed — model text field now has a fetch button that calls `/models` endpoint and shows a picker.

- **~~Memory book settings stored per-session instead of globally.~~** Fixed — `MemoryBooksSheet`, `MemoryInjectionService`, and `MemoryDraftGenerator` now read settings from `memoryGlobalSettingsProvider` (SharedPreferences) instead of per-session `MemoryBookSettings`. `ensureForSession` seeds new books from global settings. Settings sheet saves to global provider.

- **~~Vector reindex always says "check settings".~~** Fixed — `initEmbeddingConfigFromDb` was defined but never called, so `embeddingConfigProvider` was always empty. Added call in `loadActiveSelections()`.

- **~~Lorebook ghost entries after delete + recreate.~~** Fixed — 5 gaps closed: (1) Embedding `entryId` now namespaced as `lorebookId_entryId` to prevent cross-lorebook collisions (entries with IDs like `"0"`, `"1"` from character books no longer overwrite each other). (2) `_deleteAllIndexes` now uses `deleteBySourceId(lorebookId)` instead of `deleteBySourceType('lorebook_entry')` which wiped ALL lorebook embeddings. (3) `deleteLorebook()` now cleans stale IDs from `lorebookActivations` SharedPreferences map. (4) Character deletion now cascade-deletes character-scoped lorebooks + embeddings + activations. (5) Cloud sync `_deleteLocalEntity()` now handles `'lorebooks'` case. DB migration v17 clears old lorebook_entry embeddings (re-index required).

- **~~API settings and presets may not sync to cloud.~~** Fixed — cloud sync `_deleteLocalEntity()` now handles lorebook deletions with embedding cleanup. `EmbeddingRepo` injected into `SyncEngine`/`SyncService`.

- **~~Lorebooks may not appear in cloud after delete + recreate + push.~~** Fixed — cloud sync now handles lorebook deletions. Combined with the activations cleanup and namespaced entryId fixes, delete+recreate flows work correctly.

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

- **~~`{{pick}}` uses match-text hash instead of counter.~~** Fixed — now uses `pickCount` counter incremented per pick within `replaceMacros()`, matching JS `pickCount++`. Also supports `__pick_version` session var for re-rolling.

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
