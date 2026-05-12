# JS Backup Import — Missing Features

Features present in Glaze JS backups but not yet implemented in Flutter.

## Completed

- [x] **Lorebook per-book settings** — `gz_lorebooks[].settings`
  - `settingsJson` column in `lorebooks` table (migration v12), `LorebookSettings` model, per-book settings UI, scanner/vector/coverage engine support

- [x] **Backup import audit fixes** (earlier commit)
  - gz_lorebooks handles both array and Map formats
  - genTime uses ?.toString() instead of as String?
  - Message text checks 'text' before 'content'
  - Chat sessions import updatedAt
  - Lorebook entries include delayUntilRecursion, useGroupScoring
  - Lorebook probability uses double
  - Standalone embedding/memory/imggen/connections keys imported
  - Fallback API config includes temp/topp/stream/reasoning
  - loadLorebookSettings() fixed (was broken)

- [x] **Authors Notes** — `gz_chat_{id}.authorsNotes`
  - `authorsNoteJson` column in `chat_sessions` (migration v13)
  - `AuthorsNote` freezed model (content, role, insertionMode, depth, enabled)
  - `ChatRepo._toModel`/`_toCompanion` round-trip authorsNoteJson
  - `PromptPayload.authorsNote` passed from session
  - `resolveBlockContent` handles `authors_note` case with role override
  - Per-session depth/insertionMode override from AuthorsNote data
  - Backup import: `_encodeAuthorsNote()` normalizes JS string/object formats

- [x] **Chat currentId** — `gz_chat_{id}.currentId`
  - `currentSessionIndex` column in `characters` (migration v13)
  - `ChatNotifier.build` resolves session by currentSessionIndex
  - `_saveCurrentSessionIndex()` persists on session switch/create/branch
  - Backup import updates character after chat data import

- [x] **Character extensions** — `characters[].extensions` + `fav`
  - `extensionsJson` and `fav` columns in `characters` (migration v13)
  - `Character.extensions` and `Character.fav` fields
  - `CharacterImporter._extractExtensions()` strips gallery from extensions
  - `CharacterExporter` includes fav and extensions in V2 data
  - Backup import: `_extractExtensionsJson()` handles both top-level and data.extensions

- [x] **Message metadata** — in chat messages
  - `greetingIndex`, `contextRefs`, `swipeDirection`, `isEditing` fields in ChatMessage
  - Backup import reads these from JS message objects

- [x] **Chat drafts** — `gz_chat_{id}.draft`
  - `draft` column in `chat_sessions` (migration v13)
  - `ChatSession.draft` field
  - Backup import reads draft from chatData

- [x] **Scroll position** — `gz_chat_{id}.lastScrollAnchor`
  - `lastScrollAnchor` column in `chat_sessions` (migration v14, RealColumn)
  - `ChatSession.lastScrollAnchor` field
  - Backup import reads lastScrollAnchor from chatData

- [x] **character_version** — `characters[].character_version`
  - `characterVersion` column in `characters` (migration v14)
  - `Character.characterVersion` field
  - CharacterImporter and CharacterExporter round-trip it
  - Backup import reads character_version

- [x] **Lorebook description** — `gz_lorebooks[].description`
  - `description` column in `lorebooks` (migration v14)
  - `Lorebook.description` field
  - LorebookRepo round-trips it
  - Backup import reads description

- [x] **Global variables** — `gz_global_vars`, `gz_vars_{chatId}_{sessionIdx}`
  - Backup import writes gz_global_vars to SharedPreferences (key: 'globalVars')
  - Per-session vars (gz_vars_{charId}_{sessionIdx}) written to sessionVarsJson
  - Macro engine already supports {{var::}}, {{globalvar::}}, {{setvar::}}, {{setglobalvar::}}

- [x] **Memory settings (global)** — `gz_memory_settings`
  - `MemoryGlobalSettings` model with all JS fields
  - `memoryGlobalSettingsProvider` (StateNotifier) with load/save from SharedPreferences
  - Loaded on app startup via `loadActiveSelections()`
  - Backup import already writes to SharedPreferences key 'memorySettings'

- [x] **Scroll position (fixed)** — `gz_chat_{id}.lastScrollAnchor`
  - Fixed: lastScrollAnchor is `{index: int, offset: double}` object, not a number
  - `lastScrollAnchorJson` TextColumn in `chat_sessions` (stores JSON object)
  - `ChatSession.lastScrollAnchor` is `Map<String, dynamic>` now
  - Backup import encodes the anchor object as JSON

- [x] **Message extended metadata** — in chat messages
  - Added: `isTyping`, `guidanceText`, `guidanceType`, `triggeredLorebooks`, `triggeredMemories`, `swipesMeta`, `memoryCoverage`, `time`
  - All imported with defensive type checks

- [x] **Chat memoryBooks (fixed)** — per-session memory book import
  - Fixed sessionId: uses `{charId}_{sessionIdx}` instead of just the session index
  - Added fields: `rawContent`, `messageRange`, `updatedAt`, `generatedAt`
  - Fixed all unsafe casts with defensive type checks

- [x] **Character depth_prompt** — `extensions.depth_prompt`
  - `depthPrompt`, `depthPromptDepth`, `depthPromptRole` fields on Character model
  - Extracted from extensions JSON during import
  - Included in extensions on export

- [x] **Character world** — `extensions.world`
  - `world` field on Character model (links to lorebook by name)
  - Extracted from extensions JSON during import
  - Included in extensions on export

- [x] **Skip gz_chat_undefined** — invalid charId
  - Backup import skips chat data with charId "undefined" or empty

## Still Missing (discovered from backup analysis)

- [ ] **Character thumbnail / mini_thumbnail** — `characters[].thumbnail`
  - Optimized thumbnails for character list
  - Need: DB migration (thumbnailPath column), image storage, lazy generation
  - Deferred: Flutter Image widget resizes efficiently from avatarPath

- [x] **Character extensions talkativeness** — `extensions.talkativeness`
  - Random reply probability (0-1)
  - Implemented: `sendMessage` checks `character.extensions['talkativeness']`, skips generation with probability `1 - talkativeness`
  - UI: slider in character editor, persisted via extensions map

- [x] **Depth prompt injection** — `extensions.depth_prompt`
  - PromptPayload includes `characterDepthPrompt/Depth/Role`, injected as depth block in `buildPrompt()`
  - Separate from authors_note — character depth_prompt always injected if non-empty
  - UI: text field + role/depth dropdowns in character editor

- [x] **World lorebook linking** — `extensions.world`
  - `scanLorebooks()` and `LorebookVectorSearch.search()` auto-activate lorebook where `lb.name == char.world`
  - Works even if lorebook is disabled
  - UI: dropdown picker in character editor

- [x] **Message memoryCoverage persistence** — `msg.memoryCoverage`
  - `PromptPayloadBuilder` extracts matched memory entry IDs into `memoryCoverage`
  - `ChatGenerationService` writes `memoryCoverage` on generated assistant message
  - UI: "N mem" indicator in message metadata row

- [x] **Message swipesMeta persistence** — `msg.swipesMeta`
  - Each swipe stores `{genTime, reasoning, tokens, guidanceText?, guidanceType?}`
  - `previousSwipesMeta` carried forward on regeneration
  - `setSwipe()` restores reasoning/genTime/tokens from swipesMeta

- [x] **Backup import: deleted entries** — `gz_deleted_*`
  - `_importJsDeletedEntries()` reads `gz_deleted_{type}` from localStorage
  - Writes to `gz_sync_deleted_entries` SharedPreferences key (used by SyncDeletionTracker)

- [x] **Backup import: preset order** — `gz_preset_order`
  - `_importJsApiConfigs()` reads `gz_preset_order` and stores in SharedPreferences key `presetOrder`
  - `PresetListNotifier._applyOrder()` reads key to sort presets by imported order

- [x] **Backup import: embedding settings** — `gz_embedding_*`
  - API fields (endpoint, key, model, enabled, use_same) already imported into ApiConfig
  - Vector search fields (threshold, top_k, scan_depth) now merged into LorebookGlobalSettings via `_importJsLorebookSettings()`

- [x] **Character editor data loss fix** — `_save()` was constructing new Character without preserving extensions, fav, depthPrompt, world, characterVersion
  - Now preserves all original fields that aren't edited in the UI
  - Talkativeness slider writes to extensions map

## Low Priority (nice to have)

- [ ] **Group chats** — multi-character conversations
  - Need: GroupChat model, group chat creation UI, turn-order logic, per-character prompt assembly
  - Complex feature, deferred

- [x] **Chat stats** — persistent tracking + dashboard
  - Stats shown in magic drawer: messages, visible/hidden, user/assistant, prompt estimate
  - Time tracking per character: SessionLifecycleTracker records elapsed time, shown as "Time Spent" in stats sheet

- [x] **Time tracking** — timer service per chat
  - SessionLifecycleTracker records wall-clock time spent in each chat (persisted to SharedPreferences)
  - Displayed in Chat Stats sheet (magic drawer) as "Time Spent"

- [x] **Image generation config** — `gz_imggen_*`
  - ImageGenSettingsNotifier migrates from individual `gz_imggen_*` keys to consolidated `gz_imggen_settings` JSON blob
  - Migration runs automatically on first load if blob doesn't exist but JS keys do

- [x] **Sync** — `gz_sync_*`
  - Cloud sync fully implemented: Google Drive + Dropbox adapters
  - SyncEngine, SyncService, SyncManifest, SyncQueue, SyncConflict, SyncDeletionTracker
  - UI: sync_sheet.dart with provider selection, auto-sync toggle, conflict resolution

- [x] **Theme** — `gz_theme_*`
  - Flutter theme: mode (light/dark/system) + accent color
  - Backup import: `_importJsTheme()` reads `gz_theme_state` from JS backup, maps accent/dark to `theme_accent`/`theme_mode` SharedPreferences keys
  - Full custom theme support: all 30+ preset properties mapped (bg, blur, opacity, fonts, bubble colors, text colors, borders, noise)
  - ColorScheme migration: base UI colors in ColorScheme for automatic Material widget theming
  - Auto-contrast for buttons (4.5:1 WCAG AA), nav bar active tab, theme screen UI
  - `_deriveUiColor()` when uiColor is null (e.g. frutiger_aero)

- [x] **Character fav UI** — star on card, filter, toggle
  - Star icon on CharacterCard when fav=true
  - Favorite toggle in card long-press menu
  - Star filter button in character list header
  - SortType.fav filter option

- [x] **Chat search** — find text within chat messages
  - "Find in Chat" menu item in chat screen
  - Search bar with match counter (X/Y) and previous/next navigation
  - Filters messages by content, highlights match count

- [x] **Move/reorder messages** — move up/down
  - `moveMessage(fromIndex, toIndex)` in ChatNotifier
  - "Move Up" / "Move Down" actions in message context menu

- [x] **Continue message** — append to last assistant message
  - `continueMessage()` in ChatNotifier: generates continuation and appends to last assistant message
  - "Continue" action in message context menu (last assistant message only)

- [x] **Swipe dot indicators** — visual swipe position
  - Dot indicators (≤10 swipes) or text counter (>10) replace old "X/Y" text
  - Active swipe dot is full color, others are dimmed

- [x] **Lorebook free-form test** — test key matching
  - "Test Keys" button in lorebook editor
  - Dialog with text input showing matched entries in real-time
  - Matches keys and secondary keys with proper case sensitivity
