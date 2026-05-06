# Glaze Flutter Migration — Full Plan

## Current Status (updated 2026-05-06)

**Go/No-Go: PASSED.** Chat streams on all platforms. MVP core is production-quality.

### Completed phases

| Phase | Status | Notes |
|-------|--------|-------|
| Phase 0: Scaffold | Done | main, app, GoRouter, theme, shell |
| Phase 1: Data Layer | Done | Drift (not Isar), 6 tables, 6 repos, Freezed models, providers, event_hub |
| Phase 2: Chat + Import | Done | PNG/JSON/ZIP import, prompt builder in isolate, SSE streaming, abort, edit, branch |
| Phase 2.5: JS Migration | Done | .glz backup import (characters, chats, personas, presets, API configs, active selections), migration UI in menu |
| Phase 3: Presets & Personas | Done | SillyTavern import, block/regex editor, persona CRUD, active selection |
| Phase 4: Lorebooks | Done | Model, keyword scanner, prompt integration, UI — see below |
| Phase 4b: Vector Search | Done | Embedding service, vector math, DB storage, indexing pipeline, runtime search, UI — see below |
| Phase 5: Regex Runtime | Done | Applied in chat_provider during generation (placement/ephemerality/depth) |
| Phase 5b: Vector Search UI | Done | Index Entry button, vec/idx/err badges, reindex banner |
| Phase 5c: Summary + Macros | Done | SummaryService, ChatSummaries DB table (v6), {{summary}}/{{lorebooks}} macros, Generate Summary menu |
| Phase 5d: Swipe UI | Done | ←→ swipe arrows on assistant messages with swipe counter |
| Phase 5e: Session Switcher | Done | Session picker in chat header, session creation/deletion |
| UI Refactoring (round 2) | Done | God object decomposition: 6 monoliths → 19 single-responsibility files, -1308 net lines (see below) |
| Phase 6: Memory Books | Done | Memory book model, MemoryBooksSheet UI, injection service, {{memory}} macro |
| Phase 7: Guided Generation | Done | {{guidance}} macro, guided generation prompt in preset, guidance input in chat |
| Phase 8: Chat Import/Export | Done | ST JSONL import/export, export/import menu in chat |
| Phase 9: Character Book Extraction | Done | Extract character_book from PNG card, auto-create lorebook |
| Phase 10: Magic Drawer Polish | Done | Raw Prompt + Context chips wired, Context info sheet |
| Phase 11: Persona Avatar Picker | Done | Image picker for persona avatar |
| Phase 12: Character Export | Done | PNG with tEXt chunk + JSON V2 spec export |
| Phase 13: Theme + Polish | Done | Theme engine (dark/light/system + custom accent), search, crash recovery, onboarding |
| Phase 14: Character Catalog | Done | 4 providers (JanitorAI/Hampter, DataCat, JannyAI, Chub.ai), search, filters, infinite scroll, preview sheet, import, Import by URL — see below |
| Phase 14b: Import by URL | Done | DataCat extract-and-poll API, phase tracking, dialog UI |

### UI Refactoring (2025-05-05 → 2025-05-06)

Two rounds of decomposition following the "No God Objects — Parallel Decomposition" rule from AGENTS.md. Every extracted class has a single responsibility; top-level screens are thin orchestrators with zero business logic.

**Round 1** — widget extraction into `widgets/` subdirectories:

| Before | After | Extracted widgets |
|--------|-------|-------------------|
| `chat_screen.dart` (1047 lines) | `chat_screen.dart` (~300 lines) + `widgets/` | `message_bubble.dart`, `input_bar.dart`, `edit_message_dialog.dart`, `raw_prompt_viewer.dart` |
| `preset_list_screen.dart` (882 lines) | `preset_list_screen.dart` (~350 lines) + `preset_editor_screen.dart` + `widgets/` | `block_tile.dart`, `regex_tile.dart` |
| `character_list_screen.dart` (858 lines) | `character_list_screen.dart` (~250 lines) + `widgets/` | `character_card.dart`, `character_grid.dart`, `empty_state.dart` |
| `api_settings_screen.dart` (593 lines) | `api_settings_screen.dart` (~130 lines) + `api_editor_screen.dart` + `widgets/` | `mode_selector.dart`, `param_slider.dart` |

**Round 2** — god object decomposition (business logic + state + UI separated):

| Before | After | Extracted files |
|--------|-------|----------------|
| `character_list_screen.dart` (895) | `character_list_screen.dart` (139) | Reused existing `widgets/` (character_card, character_grid, empty_state) |
| `chat_provider.dart` (594) | `chat_provider.dart` (241) | `chat_state.dart`, `chat_generation_service.dart`, `initial_message_builder.dart` |
| `menu_screen.dart` (521) | `menu_screen.dart` (55) | `about_overlay.dart`, `menu_group.dart` (shared) |
| `preset_list_screen.dart` (499) | `preset_list_screen.dart` (79) | `silly_tavern_preset_parser.dart`, `preset_list_provider.dart`, `preset_tile.dart` |
| `prompt_builder.dart` (521) | `prompt_builder.dart` (227) | `fallback_prompt_builder.dart`, `prompt_block_resolver.dart`, `lorebook_merger.dart` |
| `message_bubble.dart` (465) | `message_bubble.dart` (220) | `message_actions.dart` (context menu + edit dialog) |

Net result: **-1308 lines** across 19 files (8 modified + 11 new).

New directory structure for feature folders:
```
features/
  chat/
    chat_screen.dart
    chat_provider.dart
    chat_state.dart
    chat_generation_service.dart
    initial_message_builder.dart
    widgets/
      message_bubble.dart
      message_actions.dart
      input_bar.dart
      edit_message_dialog.dart
      raw_prompt_viewer.dart
  character_list/
    character_list_screen.dart
    widgets/
      character_card.dart
      character_grid.dart
      empty_state.dart
  menu/
    menu_screen.dart
    about_overlay.dart
  presets/
    preset_list_screen.dart
    preset_list_provider.dart
    preset_editor_screen.dart
    widgets/
      preset_tile.dart
      block_tile.dart
      regex_tile.dart
  settings/
    api_settings_screen.dart
    api_editor_screen.dart
    widgets/
      mode_selector.dart
      param_slider.dart
core/
  llm/
    prompt_builder.dart
    prompt_block_resolver.dart
    fallback_prompt_builder.dart
    lorebook_merger.dart
    ...
  import/
    silly_tavern_preset_parser.dart
shared/
  widgets/
    menu_group.dart
    ...
```

Enums `SortType`/`SortDir` extracted from `_SortType`/`_SortDir` (private) to public in `character_grid.dart` — reused by the screen. `ChatState`, `NotifyObj`/`ResolvedContent`, `MenuGroup`/`MenuItem`, `ActionButton`, `PresetTile` extracted from private to public single-responsibility files.

### Phase 4: Lorebooks (2025-05-06)

Full keyword-based lorebook system ported from Glaze JS.

**Data layer:**
- `LorebookEntry` (Freezed) — all JS fields: keys, secondaryKeys, selectiveLogic, position, order, scanDepth, caseSensitive, matchWholeWords, probability, preventRecursion, sticky/cooldown/delay, group, characterFilter, ignoreBudget, vectorSearch/useKeywordSearch
- `Lorebook` (Freezed) — id, name, enabled, activationScope (global/character/chat), entries
- `LorebookGlobalSettings` / `LorebookActivations` — Freezed state models
- Drift `Lorebooks` table (schema v4), `LorebookRepo` with JSON entries column
- `LorebookProvider` (Riverpod) with CRUD, settings/activations state

**Keyword scanner (`lorebook_scanner.dart`):**
- Direct port of JS `scanLorebooksPure` / `lorebookSearchService.scanLorebooks`
- Recursive scan (up to 5 iterations)
- Glaze boundary matching (`[\s.,!?;:"'\u201C\u201D\u2018\u2019\u00AB\u00BB(){}[\]—–*]`)
- Sticky/cooldown temporal logic
- Selective logic: ANY (0), ALL (1), NOT ANY (2), NOT ALL (3), no secondary (4/5)
- Probability gate, character filter, vector-only entry skip

**Prompt integration:**
- `PromptPayload` extended with `lorebooks`, `lorebookSettings`, `lorebookActivations`
- `loreBefore` injected before preset blocks, `loreAfter` after chat_history
- `{{lorebooks}}` macro resolved for `lorebooksMacro` position entries
- `chat_provider` passes all lorebook state to prompt builder

**UI:**
- `LorebookListScreen` — list with scope badges, enable toggle, delete
- `LorebookEditorScreen` — name/scope editor + entry list
- `EntryEditorDialog` — full entry editor (keys, content, position, selective logic, temporal, group, flags)
- Route `/tools/lorebooks`, tools_screen tile navigates

**Not yet ported:**
- `{{lorebooks}}` macro content in PromptMessage metadata (no `isLorebook` / `blockName` tracking yet)
- ST lorebook import format converter
- Character book extraction from PNG cards

### Phase 4b: Lorebook Vector Search (2025-05-06)

Full vector/semantic search system ported from Glaze JS.

**Vector math (`vector_math.dart`):**
- `cosineSimilarity(a, b)` — standard dot/(||a||*||b||)
- `findTopKMulti(queryChunks, candidates, k, threshold)` — MaxSim strategy: max similarity across all query-candidate chunk pairs
- `findTopK(queryVector, candidates, k, threshold)` — single-query wrapper
- `VectorChunk`, `VectorCandidate`, `TopKResult` data classes
- `vectorToBytes`/`bytesToVector` — Float64 BLOB serialization for single vectors
- `vectorListToBytes`/`bytesToVectorList` — multi-vector BLOB serialization (count + dim + floats)

**Embedding service (`embedding_service.dart`):**
- OpenAI-compatible `/embeddings` endpoint (auto-appends if not in URL)
- Bearer token auth (optional)
- Text chunking by `maxChunkTokens` (split at newline → `. ` → space → hard cut)
- Batch processing with 200ms inter-call delay
- 429 rate limit detection → `RateLimitException(retryAfter)`
- Multi-chunk embedding with averaging for `getEmbeddings()` and per-chunk results for `getEmbeddingsWithChunks()`
- `EmbeddingChunk`, `EmbeddingConfig` data classes

**Embedding DB storage:**
- Drift `Embeddings` table (schema v5): `entryId` (PK), `sourceType`, `sourceId`, `vectorsBlob` (multi-vector BLOB), `textHash` (SHA-256), `retrievalHintsJson`, `errorJson`, `updatedAt`
- `EmbeddingRepo` with CRUD + `putEmbeddingVector`/`putEmbeddingError` helpers + `decodeVectors`/`decodeHints`/`decodeError`

**Indexing pipeline (`lorebook_embedding_service.dart`):**
- `indexLorebookEntries(lorebookId, entries, config, onProgress, retryFailedOnly)`
- SHA-256 fingerprint cache: skip entries where `textHash` matches stored hash
- On 429 rate limit: immediately mark all remaining entries as rate-limited errors and stop
- `extractRetrievalHints(entry)`: up to 32 hints from comment, keys, first 8 content lines, `label: value` patterns
- `IndexResult` with indexed/skipped/failed/rateLimited counts

**Runtime vector search (`lorebook_vector_search.dart`):**
- `search(history, currentText, lorebooks, settings, config)` → `List<VectorSearchResult>`
- Filters active lorebooks, vector-enabled entries (excluding constants)
- Loads embeddings from DB, skips stale/missing ones
- Dual query strategy: **focused** (user messages only, bounded by `maxChunkTokens*2`) + **fallback** (all messages, bounded by `maxChunkTokens*3`), merges by higher score
- Query sanitization: strips HTML, OOC, base64 images
- Hybrid boost: name/key substring match (+0.18), key token overlap (+0.04/key, max +0.12), descriptor token overlap (+0.025/hint, max +0.10)
- Applies `vectorThreshold` (default 0.45) and `vectorTopK` (default 10)
- `embeddingConfigProvider` (StateProvider), `lorebookVectorSearchProvider`, `lorebookEmbeddingServiceProvider`

**Prompt integration:**
- `PromptPayload` extended with `vectorEntries: List<LorebookEntry>`
- `_mergeKeywordVector()` in prompt_builder: splits `maxInjectedEntries` budget by `keywordVectorSplit` %, deduplicates by entry ID, unused keyword slots roll over to vector
- `chat_provider._runVectorSearch()`: runs before `buildPromptInIsolate`, skipped if `searchType == 'keys'` or config endpoint empty

**LorebookGlobalSettings additions:**
- `vectorThreshold` (default 0.45)
- `vectorTopK` (default 10)

**UI:**
- `EntryEditorDialog`: added "Vector Search" and "Keyword Search" chips; vector-only mode when vector=on + keyword=off
- `LorebookEditorScreen`: index button in AppBar with progress status; calls `LorebookEmbeddingService.indexLorebookEntries`
- `EmbeddingSettingsScreen`: search mode selector (keyword/vector/both), embedding API config (endpoint, key, model, maxChunkTokens), test connection button, vector params (threshold, topK, scan depth)
- Route `/tools/embeddings`, search icon in LorebookListScreen navigates to embedding settings

### Phase 5b: Vector Search UI (2025-05-06)

Enhanced vector search user experience.

**Entry-level indexing:**
- `EntryEditorDialog`: "Index Entry" button for single-entry indexing (passes `lorebookId` to dialog)
- Embedding status display: indexed (green), none (gray), error (orange)
- Status loaded from `EmbeddingRepo` on dialog open

**List-level indicators:**
- `vec`/`idx`/`err` badges on entry tiles in `LorebookEditorScreen`
- `_Badge` widget with color-coded labels (cyan=vec, green=idx, orange=err)
- Embedding statuses loaded asynchronously from DB on screen open

**Reindex banner:**
- Orange banner appears when vector entries lack embeddings
- Shows count of missing entries, "Index All" button
- Auto-refreshes after batch indexing completes

### Phase 5c: Summary + Macros (2025-05-06)

Chat summary generation and macro integration.

**Summary service (`summary_service.dart`):**
- `generateSummary(sessionId, history, apiConfig, customPrompt)` — sends history to LLM, stores result
- `getSummary(sessionId)` — retrieves cached summary from DB
- `needsRegeneration(currentCount, savedCount)` — 30% threshold check
- Default prompt: "Summarize the following roleplay conversation concisely..."
- Supports `{{history}}` in custom prompt templates
- Uses Dio for API calls (consistent with rest of codebase)

**Database:**
- `ChatSummaries` Drift table (schema v6): `sessionId` (PK), `content`, `messageCount`, `prompt`, `updatedAt`
- `SummaryRepo` with `get`, `put`, `deleteBySessionId`
- `summaryRepoProvider`, `summaryServiceProvider` in `db_provider.dart`

**Macro integration:**
- `MacroContext` extended with `summaryContent` and `lorebooksContent` fields
- `{{summary}}` macro in `MacroEngine` — replaced with `ctx.summaryContent ?? ''`
- `{{lorebooks}}` macro in `MacroEngine` — replaced with `ctx.lorebooksContent ?? ''`
- `summaryContent` wired through `PromptPayload` → `buildPrompt` → `MacroContext`
- Existing `summary` block in `prompt_block_resolver.dart` continues to work via `summaryContent`

**Chat integration:**
- `chat_generation_service.dart`: loads summary from DB, passes to `PromptPayload`
- `tokenizer_sheet.dart`: loads summary for accurate token breakdown
- `chat_dialogs.dart` (raw prompt viewer): includes summary in payload
- "Generate Summary" menu item in chat screen popup menu

### Phase 5d: Swipe UI (2025-05-06)

Swipe navigation on assistant messages.

- Left/right arrow buttons on assistant message bubbles
- Swipe counter (e.g. "2/3") showing current swipe position
- Swipe metadata stored per message in `swipesMeta` list
- `previousSwipes` and `previousSwipeId` passed through generation service

### Phase 5e: Session Switcher (2025-05-06)

Chat session management.

- Session picker in chat header (tap session name to switch)
- New session creation via "+" button
- Session deletion with confirmation
- Session index display and message count

### Phase 14: Character Catalog (2026-05-06)

Full character discovery and import system ported from Glaze JS.

**Data layer:**
- `CatalogItem` — id, name, avatarUrl, description, tags, tokens, chatCount, creator, creatorId, nsfw, source, fullPath, slug
- `CatalogFilters` — sort, nsfw, nsfl, tagIds, tagNames, minTokens, maxTokens
- `CatalogTag` — id, name, type (category/nsfw/other)
- `CatalogProvider` enum — janitor, janny, datacat, chub
- `CharacterData` — name, description, personality, scenario, firstMes, mesExample, creatorNotes, systemPrompt, postHistoryInstructions, alternateGreetings, tags, creator, creatorId, characterBook
- `DownloadedCharacter` — charData + avatarUrl
- `CatalogSearchResult` — characters, total, hasMore

**Provider services (4 providers):**
- `janitor_provider.dart` — Hampter API search/tags/fetch, with DataCat UUID fallback chain
- `datacat_provider.dart` — session auth, browse/search, Saucepan extraction, tags
- `janny_provider.dart` — MeiliSearch API, token management, Astro scraping
- `chub_provider.dart` — REST search, tag aggregation, character download
- `catalog_http.dart` — shared Dio-based HTTP client with GET/POST/list helpers

**State management:**
- `CatalogNotifier` (Riverpod StateNotifier) — provider switching, pagination, search, filter persistence (SharedPreferences), import pipeline
- Per-provider sort defaults persisted to SharedPreferences
- Filter state (NSFW/NSFL/token range/tag selections) persisted

**UI:**
- `CatalogCard` — avatar via CachedNetworkImage, token badge, NSFW badge, tag chips
- `CatalogGrid` — infinite scroll, provider/sort/filter controls, results count, loading/empty states
- Provider selector — bottom sheet with JanitorAI/DataCat/JannyAI/Chub.ai options
- Sort selector — per-provider sort options (trending, popular, latest, etc.)
- Filter sheet — NSFW/NSFL toggles, min/max token range, reset/apply
- Preview sheet — draggable sheet with full character info (avatar, name, creator, tags, creator notes, description, scenario, first message) + Import button
- Import pipeline — download avatar → save via ImageStorage → create character + lorebook entries in DB
- Wired into character_list_screen Discover tab (replaces "coming soon" placeholder)

**Import by URL (Phase 14b):**
- `ImportUrlDialog` — paste JanitorAI/Saucepan/Chub URL
- `datacatExtractAndPoll` — submit URL to DataCat, poll for completion with phase tracking
- Phase callback updates UI during extraction
- On success: import character via same pipeline as catalog import
- Import URL FAB shown on Discover tab

**Directory structure:**
```
features/catalog/
  catalog_models.dart
  catalog_provider.dart
  services/
    catalog_http.dart
    janitor_provider.dart
    datacat_provider.dart
    janny_provider.dart
    chub_provider.dart
  widgets/
    catalog_card.dart
    catalog_grid.dart
    import_url_dialog.dart
    widgets.dart
```

### Phase 6: Image Generation (2026-05-06)

Full image generation system with 4 providers, auto-gen, and settings UI.

**Data layer:**
- `ImageGenSettings` — Freezed model with per-provider settings, reference images, image context
- `ReferenceImage` — name, imageData (base64), matchMode (match/always)
- `ImageGenApiType` enum — openai, gemini, naistera, routmy
- `RoutMyConstants`, `NaisteraConstants`, `OpenAIConstants`, `GeminiConstants` — static options
- Settings persisted via SharedPreferences key `gz_imggen_settings`

**Provider services (4 providers):**
- `openai_image_provider.dart` — DALL-E API (b64_json response format)
- `gemini_image_provider.dart` — Imagen API (predictions response)
- `naistera_image_provider.dart` — Naistera API (hardcoded endpoint, reference images)
- `routmy_image_provider.dart` — RoutMy API + RU Bridge (two-step: LLM description → image gen)
- `image_gen_http.dart` — shared Dio-based HTTP client with POST/base64 extraction helpers

**Orchestrator:**
- `image_gen_service.dart` — `processMessageImages()` scans for `[IMG:GEN:...]` tags, generates images, replaces with `[IMG:RESULT:path]` or `[IMG:ERROR:...]`
- `generateImage()` dispatches to provider based on settings
- Reference images built from character/persona avatars, additional refs, and image context
- Generated images saved to `generated/` subdirectory via `ImageStorageService`
- `_buildReferences()` handles match mode (keyword/always) per provider

**State management:**
- `ImageGenSettingsNotifier` (Riverpod AsyncNotifier) — load/save from SharedPreferences, JSON serialization
- `getService()` factory for ImageGenService (reuses ImageStorageService from db_provider)

**UI:**
- `ImageGenSheet` — draggable settings panel: enabled toggle, provider selector (4 providers), per-provider fields, image context settings, tip about `[IMG:GEN:...]` tag format
- `ImageContentRenderer` — parses message content for `[IMG:GEN:...]`, `[IMG:RESULT:path]`, `[IMG:ERROR:...]` markers, renders MarkdownBody for text spans and Image.file/loading/error widgets for image spans
- `MessageBubble` updated — uses `ImageContentRenderer` when image markers detected, else MarkdownBody
- `ChatInputBar` updated — image button now wired (`onImageGen` callback → opens ImageGenSheet)
- `MagicDrawerPanel` updated — added "ImgGen On/Off" item that opens ImageGenSheet

**Integration:**
- `ChatGenerationService.processImageTags()` — post-generation hook that processes `[IMG:GEN:...]` tags after LLM response is saved
- `ChatNotifier.sendMessage()` and `regenerateLastAssistant()` call `processImageTags()` after generation completes
- `ImageStorageService.baseDir` changed from private to public for image gen save path
- `image_gen_provider.dart` imports added to `db_provider.dart` dependency chain

**Directory structure:**
```
features/image_gen/
  image_gen_models.dart
  image_gen_provider.dart
  services/
    image_gen_http.dart
    openai_image_provider.dart
    gemini_image_provider.dart
    naistera_image_provider.dart
    routmy_image_provider.dart
    image_gen_service.dart
  widgets/
    image_gen_sheet.dart
    image_content_renderer.dart
    widgets.dart
```

### Remaining phases (in priority order)

| Phase | Priority | What's Missing |
|-------|----------|----------------|
| Cloud Sync | Medium | Dropbox + GDrive adapters, manifest, engine, conflict resolution UI (no encryption for now) |
| Backup Export/Import | Medium | .glz backup export, ST backup ZIP import, backup/restore UI in menu |
| Character Gallery | Medium | Per-character image gallery, add/delete, full-screen viewer, sync support |
| Persona Connections | Medium | Per-character and per-chat persona bindings (currently global only) |
| Memory Coverage/Preview | Medium | Coverage analysis (which memories activate), prompt template editor, prompt preview, text preview |
| Glossary / Help | Low | Categorized help articles, inline HelpTip components |
| Stats Dashboard | Low | Per-chat/char/global stats (tokens, messages, time) |
| Notifications | Low | In-app notification center + native push for background gen |
| Character Color Picker | Low | Color picker with presets, custom hex, auto — used for theme accent |
| Drag-and-Drop Import | Low | Desktop: drag PNG/JSON/ZIP onto app |
| ST Backup Import | Low | Import SillyTavern backup ZIP format |
| Enhanced Onboarding | Low | Replay from menu, more steps |

### Known stubs in current codebase

- `chat_screen.dart` → `input_bar.dart` — 2 input bar buttons (fullscreen, auto) are decorative
- `menu_screen.dart` — Cloud Sync, Backups "coming soon"
- `tokenizer.dart` — heuristic (chars/3.35), no real BPE

### Architecture note

Plan originally specified **Isar**; actual implementation uses **Drift** (SQLite). This is intentional — Drift has better Windows support and doesn't require native binaries per platform. All model/DB references in this doc should be read as "Drift" instead of "Isar".

Also: the project structure now uses **widget subdirectories** per feature folder. Each `features/{feature}/widgets/` contains extracted, focused widgets (cards, tiles, dialogs, etc.) that were previously inline in the screen file. This follows the "No God Objects" rule from AGENTS.md — no file should exceed ~150 lines or take on more than one role.

---

# PART 1: MVP (Day 1–18)

## Goal

A working chat app on iOS + Android + Windows that:
1. Imports a character card (PNG/JSON)
2. Opens a chat session
3. Builds a prompt in an isolate
4. Streams a response from an OpenAI-compatible API
5. Saves the conversation to local DB
6. No WKWebView, no Web Worker, no IndexedDB

---

## Phase 0: Project Scaffold (Day 1–2)

### Step 0.1: Create Flutter project

```bash
flutter create --org com.glaze --project-name glaze_flutter glaze_flutter
cd glaze_flutter
flutter pub add flutter_riverpod riverpod_annotation isar isar_flutter_libs dio go_router freezed_annotation json_annotation path_provider shared_preferences flutter_markdown url_launcher archive crypto encrypt image
flutter pub add --dev build_runner freezed json_serializable riverpod_generator isar_generator flutter_test integration_test
```

### Step 0.2: Project structure

```
lib/
├── main.dart
├── app.dart                      # MaterialApp + GoRouter
├── core/
│   ├── db/
│   │   ├── app_db.dart           # Isar instance singleton
│   │   ├── collections.dart      # Isar @collection classes
│   │   └── repositories/
│   │       ├── character_repo.dart
│   │       ├── chat_repo.dart
│   │       ├── preset_repo.dart
│   │       ├── api_config_repo.dart
│   │       └── persona_repo.dart
│   ├── models/                   # Freezed data classes
│   │   ├── character.dart
│   │   ├── chat_message.dart
│   │   ├── chat_session.dart
│   │   ├── preset.dart
│   │   ├── api_config.dart
│   │   └── persona.dart
│   ├── state/                    # Riverpod providers
│   │   ├── character_provider.dart
│   │   ├── chat_provider.dart
│   │   ├── preset_provider.dart
│   │   ├── api_config_provider.dart
│   │   └── persona_provider.dart
│   ├── llm/
│   │   ├── macro_engine.dart
│   │   ├── prompt_builder.dart
│   │   ├── prompt_isolate.dart
│   │   ├── sse_client.dart
│   │   ├── stream_accumulator.dart
│   │   ├── response_normalizer.dart
│   │   └── tokenizer.dart
│   ├── services/
│   │   ├── image_storage.dart
│   │   ├── character_importer.dart
│   │   └── file_saver.dart
│   └── events/
│       └── event_hub.dart
├── features/
│   ├── character_list/
│   │   ├── character_list_screen.dart
│   │   └── character_card_widget.dart
│   ├── chat/
│   │   ├── chat_screen.dart
│   │   ├── message_list.dart
│   │   ├── message_bubble.dart
│   │   ├── input_bar.dart
│   │   └── streaming_indicator.dart
│   ├── settings/
│   │   └── api_settings_screen.dart
│   └── onboarding/
│       └── welcome_screen.dart
├── shared/
│   ├── widgets/
│   │   ├── glaze_scaffold.dart
│   │   ├── glaze_text_field.dart
│   │   └── loading_overlay.dart
│   └── theme/
│       ├── app_theme.dart
│       └── app_colors.dart
└── generated/                    # build_runner output
```

### Step 0.3: pubspec.yaml overrides

```yaml
dependency_overrides:
  isar: ^4.0.0
  isar_flutter_libs: ^4.0.0
```

### Step 0.4: main.dart

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import 'app.dart';
import 'core/db/collections.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dir = await getApplicationDocumentsDirectory();
  final isar = await Isar.open(
    [CharacterCollectionSchema, ChatSessionCollectionSchema,
     PresetCollectionSchema, ApiConfigCollectionSchema, PersonaCollectionSchema],
    directory: dir.path,
  );
  runApp(ProviderScope(overrides: [isarProvider.overrideWithValue(isar)], child: const GlazeApp()));
}
```

### Step 0.5: GoRouter setup

```dart
// app.dart
final routerProvider = Provider<GoRouter>((ref) => GoRouter(
  routes: [
    GoRoute(path: '/', builder: (_, __) => const CharacterListScreen()),
    GoRoute(path: '/chat/:charId', builder: (_, state) => ChatScreen(charId: state.pathParameters['charId']!)),
    GoRoute(path: '/settings/api', builder: (_, __) => const ApiSettingsScreen()),
  ],
));
```

### Step 0.6: Basic dark theme

```dart
// shared/theme/app_theme.dart
class AppTheme {
  static ThemeData dark() => ThemeData(
    brightness: Brightness.dark,
    colorSchemeSeed: const Color(0xFF66CCFF),
    useMaterial3: true,
  );
}
```

### Deliverables Phase 0
- [x] App runs on iOS simulator, Android emulator, Windows desktop
- [x] Isar DB opens without errors
- [x] GoRouter navigates between 3 empty screens
- [x] Dark theme applied

---

## Phase 1: Data Layer (Day 3–7)

### Step 1.1: Freezed models

Port each JS model to Dart. The JS source of truth:

| JS File | JS Export | Dart Target |
|---------|-----------|-------------|
| `utils/characterIO.js:296` `normalizeCharacterData` | Character shape | `models/character.dart` |
| `utils/db.js:68` `normalizeChatData` | Message shape | `models/chat_message.dart` |
| `core/states/presetState.js` | Preset shape | `models/preset.dart` |
| `core/config/APISettings.js` | ApiConfig shape | `models/api_config.dart` |
| `core/states/personaState.js` | Persona shape | `models/persona.dart` |

#### character.dart
```dart
@freezed
class Character with _$Character {
  const factory Character({
    required String id,
    required String name,
    String? avatarPath,
    String? description,
    String? personality,
    String? scenario,
    String? firstMes,
    String? mesExample,
    String? systemPrompt,
    String? postHistoryInstructions,
    String? creator,
    String? creatorNotes,
    @Default([]) List<String> tags,
    @Default([]) List<String> alternateGreetings,
    String? color,
    @Default(0) int updatedAt,
  }) = _Character;
  factory Character.fromJson(Map<String, dynamic> json) => _$CharacterFromJson(json);
}
```

Mapping from JS `normalizeCharacterData` (characterIO.js:296):
- `data.name` → `name`
- `data.avatar` → `avatarPath` (decode data URL → save file → store path)
- `data.description` → `description`
- `data.personality` → `personality`
- `data.scenario` → `scenario`
- `data.first_mes` → `firstMes`
- `data.mes_example` → `mesExample`
- `data.system_prompt` → `systemPrompt`
- `data.post_history_instructions` → `postHistoryInstructions`
- `data.alternate_greetings` → `alternateGreetings`
- `data.tags` → `tags`
- `data.creator` / `data.creator_notes` → `creator` / `creatorNotes`
- `data.character_book` → extracted during import, not stored on character

#### chat_message.dart
```dart
@freezed
class ChatMessage with _$ChatMessage {
  const factory ChatMessage({
    required String id,
    required String role, // 'user' | 'assistant' | 'system'
    required String content,
    int? timestamp,
    String? personaId,
    String? personaName,
    String? imagePath,
    @Default([]) List<String> swipes,
    @Default(0) int swipeId,
    String? reasoning,
  }) = _ChatMessage;
  factory ChatMessage.fromJson(Map<String, dynamic> json) => _$ChatMessageFromJson(json);
}

@freezed
class ChatSession with _$ChatSession {
  const factory ChatSession({
    required String id,
    required String characterId,
    required int sessionIndex,
    @Default([]) List<ChatMessage> messages,
    @Default(0) int updatedAt,
  }) = _ChatSession;
  factory ChatSession.fromJson(Map<String, dynamic> json) => _$ChatSessionFromJson(json);
}
```

Mapping from JS `normalizeChatData` (db.js:68):
- Message `role`: JS `'user'`/`'char'` → Dart `'user'`/`'assistant'`
- Message `mes`/`text` → `content`
- Message `persona.id`/`persona.name` → `personaId`/`personaName`
- Message `swipes` → `swipes`
- Message `swipeId` → `swipeId`
- Message `reasoning` → `reasoning`
- JS stores `image` as data URL → Dart stores as `imagePath` (file)

#### preset.dart
```dart
@freezed
class PresetBlock with _$PresetBlock {
  const factory PresetBlock({
    required String id,
    required String name,
    required String role,
    required String content,
    @Default(true) bool enabled,
    @Default(false) bool isStatic,
    @Default('relative') String insertionMode,
    int? depth,
    String? prefix,
    @Default(false) bool isStashed,
  }) = _PresetBlock;
  factory PresetBlock.fromJson(Map<String, dynamic> json) => _$PresetBlockFromJson(json);
}

@freezed
class PresetRegex with _$PresetRegex {
  const factory PresetRegex({
    required String id,
    required String name,
    required String regex,
    @Default('') String replacement,
    @Default('') String trimOut,
    @Default([1, 2]) List<int> placement,
    @Default([1, 2]) List<int> ephemerality,
    @Default(false) bool disabled,
    @Default('0') String macroRules,
    int? minDepth,
    int? maxDepth,
  }) = _PresetRegex;
  factory PresetRegex.fromJson(Map<String, dynamic> json) => _$PresetRegexFromJson(json);
}

@freezed
class Preset with _$Preset {
  const factory Preset({
    required String id,
    required String name,
    String? author,
    @Default([]) List<PresetBlock> blocks,
    @Default([]) List<PresetRegex> regexes,
    @Default(false) bool reasoningEnabled,
    String? reasoningStart,
    String? reasoningEnd,
    String? guidedGenerationPrompt,
    String? guidedImpersonationPrompt,
    String? summaryPrompt,
    @Default(false) bool mergePrompts,
    @Default('system') String mergeRole,
    @Default(0) int createdAt,
  }) = _Preset;
  factory Preset.fromJson(Map<String, dynamic> json) => _$PresetFromJson(json);
}
```

Mapping from JS `presetImportService.js` + `presetState.js`:
- Block `insertion_mode` → `insertionMode`
- Block `isStatic` → `isStatic`
- Regex `placement` can be `int` or `List<int>` in JS → normalize to `List<int>` on import
- Regex `ephemerality` same → `List<int>`
- `macroRules` stored as string `'0'`/`'1'`/`'2'` → keep as string

Mandatory blocks from `presetImportService.js:51-60`:
```
worldInfoBefore, user_persona, char_card, char_personality,
scenario, example_dialogue, worldInfoAfter, chat_history
```
Plus auto-added: `summary`, `authors_note`, `guided_generation`

#### api_config.dart
```dart
@freezed
class ApiConfig with _$ApiConfig {
  const factory ApiConfig({
    required String id,
    @Default('') String name,
    @Default('openai_compatible') String providerId,
    @Default('') String endpoint,
    @Default('') String apiKey,
    @Default('') String model,
    @Default(8000) int maxTokens,
    @Default(32000) int contextSize,
    @Default(0.7) double temperature,
    @Default(0.9) double topP,
    @Default(true) bool stream,
    @Default('medium') String reasoningEffort,
    @Default(false) bool requestReasoning,
    String? reasoningTagStart,
    String? reasoningTagEnd,
  }) = _ApiConfig;
  factory ApiConfig.fromJson(Map<String, dynamic> json) => _$ApiConfigFromJson(json);
}
```

Mapping from JS `APISettings.js`:
- `key` → `apiKey`
- `temp` → `temperature`
- `reasoningTags.start/end` → `reasoningTagStart`/`reasoningTagEnd`

#### persona.dart
```dart
@freezed
class Persona with _$Persona {
  const factory Persona({
    required String id,
    required String name,
    String? prompt,
    String? avatarPath,
  }) = _Persona;
  factory Persona.fromJson(Map<String, dynamic> json) => _$PersonaFromJson(json);
}
```

### Step 1.2: Isar collections

```dart
// core/db/collections.dart
part 'collections.g.dart';

@collection
class CharacterCollection {
  Id id = Isar.autoIncrement;
  late String charId;
  late String name;
  String? avatarPath;
  String? description;
  String? personality;
  String? scenario;
  String? firstMes;
  String? mesExample;
  String? systemPrompt;
  String? postHistoryInstructions;
  String? creator;
  String? creatorNotes;
  String? color;
  int updatedAt = 0;
  String? tagsJson;              // JSON-encoded List<String>
  String? alternateGreetingsJson;
}
```

Index `charId` for fast lookup. Same pattern for all collections.

`ChatSessionCollection` stores `messagesJson` (serialized `List<ChatMessage>`).
`PresetCollection` stores `dataJson` (serialized full `Preset`).
`ApiConfigCollection` stores flat fields (endpoint, model, etc.).
`PersonaCollection` stores flat fields.

### Step 1.3: Repository classes

Each repo follows this pattern:

```dart
class CharacterRepo {
  final Isar _db;
  CharacterRepo(this._db);

  Future<List<Character>> getAll() async {
    final collections = _db.characterCollections.where().findAll();
    return collections.map(_toModel).toList();
  }

  Future<Character?> getById(String id) async {
    final c = _db.characterCollections.where().charIdEqualTo(id).findFirst();
    return c != null ? _toModel(c) : null;
  }

  Future<void> put(Character char) async {
    await _db.writeAsync(() {
      _db.characterCollections.put(_toCollection(char));
    });
  }

  Future<void> delete(String id) async {
    await _db.writeAsync(() {
      _db.characterCollections.where().charIdEqualTo(id).deleteAll();
    });
  }

  Character _toModel(CharacterCollection c) => Character(
    id: c.charId, name: c.name, avatarPath: c.avatarPath,
    description: c.description, /* ... */
    tags: c.tagsJson != null ? List<String>.from(jsonDecode(c.tagsJson!)) : [],
  );

  CharacterCollection _toCollection(Character m) => CharacterCollection()
    ..charId = m.id
    ..name = m.name
    ..avatarPath = m.avatarPath
    ..description = m.description
    ..tagsJson = jsonEncode(m.tags)
    /* ... */;
}
```

Repositories to implement:
- `CharacterRepo` — maps `CharacterCollection` ↔ `Character`
- `ChatRepo` — maps `ChatSessionCollection` ↔ `ChatSession`. Key: sessionId = `{charId}_{sessionIndex}`
- `PresetRepo` — maps `PresetCollection` ↔ `Preset`
- `ApiConfigRepo` — maps `ApiConfigCollection` ↔ `ApiConfig`
- `PersonaRepo` — maps `PersonaCollection` ↔ `Persona`

### Step 1.4: Image storage service

```dart
// core/services/image_storage.dart
class ImageStorage {
  final String _baseDir;

  Future<String> saveDataUrl(String dataUrl, String subfolder, String filename) async {
    // 1. Parse data URL: extract mime + base64 body
    // 2. Decode base64 → bytes
    // 3. Determine extension from mime
    // 4. Write to {baseDir}/{subfolder}/{filename}.{ext}
    // 5. Return the relative path
  }

  Future<String> saveBytes(Uint8List bytes, String subfolder, String filename, String ext) async { ... }

  Future<Uint8List?> readBytes(String relativePath) async { ... }

  Future<void> delete(String relativePath) async { ... }

  String? absolutePath(String? relativePath) => relativePath != null ? '$_baseDir/$relativePath' : null;
}
```

Subfolder structure:
```
{appDocumentsDir}/
  avatars/{charId}.png
  gallery/{charId}/{imgId}.jpg
  chat_images/{sessionId}/{msgId}.png
```

### Step 1.5: Riverpod providers

```dart
// core/state/db_provider.dart
final isarProvider = Provider<Isar>((ref) => throw UnimplementedError('Isar not initialized'));
final characterRepoProvider = Provider<CharacterRepo>((ref) => CharacterRepo(ref.watch(isarProvider)));
final chatRepoProvider = Provider<ChatRepo>((ref) => ChatRepo(ref.watch(isarProvider)));
// ... same for all repos

// core/state/character_provider.dart
final charactersProvider = AsyncNotifierProvider<CharactersNotifier, List<Character>>(CharactersNotifier.new);

class CharactersNotifier extends AsyncNotifier<List<Character>> {
  @override
  Future<List<Character>> build() => ref.read(characterRepoProvider).getAll();

  Future<void> add(Character character) async {
    await ref.read(characterRepoProvider).put(character);
    state = AsyncData(await ref.read(characterRepoProvider).getAll());
  }

  Future<void> remove(String id) async {
    await ref.read(characterRepoProvider).delete(id);
    state = AsyncData(await ref.read(characterRepoProvider).getAll());
  }
}
```

Same pattern for: `ChatNotifier`, `PresetNotifier`, `ApiConfigNotifier`, `PersonaNotifier`.

### Step 1.6: Event hub

```dart
// core/events/event_hub.dart
class EventHub {
  static final _controllers = <String, StreamController<_Event>>{};

  static void publish(String event, [dynamic data]) {
    _controllers[event]?.add(_Event(event, data));
  }

  static StreamSubscription subscribe(String event, void Function(dynamic data) onEvent) {
    _controllers.putIfAbsent(event, () => StreamController<_Event>.broadcast());
    return _controllers[event]!.stream.listen((e) => onEvent(e.data));
  }

  static void dispose(String event) {
    _controllers[event]?.close();
    _controllers.remove(event);
  }
}

class _Event {
  final String name;
  final dynamic data;
  _Event(this.name, this.data);
}
```

### Step 1.7: Run build_runner

```bash
dart run build_runner build --delete-conflicting-outputs
```

Generates: `*.g.dart`, `*.freezed.dart` files.

### Deliverables Phase 1
- [x] All 6 Freezed models compile with `fromJson`
- [x] All 5 Isar collections with indexes
- [x] All 5 repository classes with CRUD
- [x] ImageStorage saves/reads files correctly
- [x] Riverpod providers wire repos to UI
- [x] EventHub publish/subscribe works
- [ ] Unit tests for each repo (in-memory Isar)

---

## Phase 2: Character Import + Chat (Day 8–16)

### Step 2.1: PNG tEXt chunk parser

Port from JS `characterIO.js:91-170`.

```dart
// core/services/character_importer.dart
class CharacterImporter {
  final ImageStorage _imageStorage;

  Future<Character> importFromFile(String filePath) async {
    final bytes = await File(filePath).readAsBytes();
    final ext = filePath.toLowerCase();

    if (ext.endsWith('.png')) return _importPng(bytes);
    if (ext.endsWith('.json')) return _importJson(bytes);
    if (ext.endsWith('.charx') || ext.endsWith('.zip')) return _importCharX(bytes);
    throw ArgumentError('Unsupported file format');
  }

  Future<Character> _importPng(Uint8List bytes) async {
    // 1. Validate PNG signature: [137, 80, 78, 71, 13, 10, 26, 10]
    // 2. Walk chunks starting at offset 8:
    //    - Read 4 bytes length (big-endian uint32)
    //    - Read 4 bytes type (ASCII)
    //    - If type == 'tEXt':
    //      a. Find null byte separating keyword from text
    //      b. If keyword == 'chara' or 'ccv3': base64-decode the text → JSON
    //    - Skip: length + 4 (CRC)
    // 3. If no charaData found, throw
    // 4. Save PNG bytes to ImageStorage as avatar
    // 5. Call _normalizeCharacterData on the JSON
    // 6. Return Character with avatarPath set
  }
}
```

Key differences from JS:
- `file.arrayBuffer()` → `File.readAsBytes()`
- `DataView.getUint32(offset)` → `ByteData.view(buffer).getUint32(offset, Endian.big)` (PNG is big-endian)
- `atob(base64)` → `base64Decode(base64)`
- `new TextDecoder().decode()` → `utf8.decode()`
- `JSON.parse()` → `jsonDecode()`

### Step 2.2: JSON import

Port from JS `characterIO.js:45-89`.

```dart
Future<Character> _importJson(Uint8List bytes) async {
  final json = jsonDecode(utf8.decode(bytes));
  return _normalizeCharacterData(json);
}
```

### Step 2.3: CharX/ZIP import

Port from JS `characterIO.js:172-283`.

```dart
Future<Character> _importCharX(Uint8List bytes) async {
  final archive = ZipDecoder().decodeBytes(bytes);
  // 1. Look for 'card.json' entry → parse as V3 card
  // 2. If no card.json, look for first .png entry → delegate to _importPng
  // 3. Extract icon asset from zip → save to ImageStorage
  // 4. Extract gallery assets → save to ImageStorage
  // 5. Return normalized Character
}
```

Package: `archive` (replaces JSZip).

### Step 2.4: Character normalizer

Port from JS `characterIO.js:296-333`.

```dart
Character _normalizeCharacterData(Map<String, dynamic> json) {
  Map<String, dynamic> data;
  if (json['spec'] == 'chara_card_v2' || json['spec'] == 'chara_card_v3') {
    data = Map<String, dynamic>.from(json['data'] as Map);
  } else if (json.containsKey('name')) {
    data = json;
  } else {
    throw FormatException('Unknown character data format');
  }

  return Character(
    id: generateId(),
    name: data['name'] ?? 'Unknown',
    description: data['description'],
    personality: data['personality'],
    scenario: data['scenario'],
    firstMes: data['first_mes'],
    mesExample: data['mes_example'],
    systemPrompt: data['system_prompt'],
    postHistoryInstructions: data['post_history_instructions'],
    creator: data['creator'],
    creatorNotes: data['creator_notes'],
    tags: List<String>.from(data['tags'] ?? []),
    alternateGreetings: List<String>.from(data['alternate_greetings'] ?? []),
  );
}
```

### Step 2.5: Macro engine

Port from JS `macroEngine.js` (212 lines). Nearly 1:1.

```dart
// core/llm/macro_engine.dart
class MacroEngine {
  final Map<String, String> _sessionVars = {};
  final Map<String, String> _globalVars = {};

  String replaceMacros(String text, {
    required String charName,
    String? charDescription,
    String? charScenario,
    String? charPersonality,
    String? charMesExample,
    String? userName,
    String? userPersona,
    Map<String, String>? sessionVars,
  }) {
    if (text.isEmpty) return '';

    var result = text;

    // Comments: {{ // }} ... {{ /// }}
    result = result.replaceAll(RegExp(r'\{\{\s*\/\/\s*\}\}[\s\S]*?\{\{\s*\/\/\/\s*\}\}'), '');
    result = result.replaceAll(RegExp(r'\{\{\/\/[^}]*\}\}'), '');

    // Simple replacements
    result = result.replaceAll(RegExp(r'{{char}}', caseSensitive: false), charName);
    result = result.replaceAll(RegExp(r'{{description}}', caseSensitive: false), charDescription ?? '');
    result = result.replaceAll(RegExp(r'{{scenario}}', caseSensitive: false), charScenario ?? '');
    result = result.replaceAll(RegExp(r'{{personality}}', caseSensitive: false), charPersonality ?? '');
    result = result.replaceAll(RegExp(r'{{mesExamples}}', caseSensitive: false), charMesExample ?? '');
    result = result.replaceAll(RegExp(r'{{user}}', caseSensitive: false), userName ?? 'User');
    result = result.replaceAll(RegExp(r'{{persona}}', caseSensitive: false), userPersona ?? '');

    // {{trim}}
    if (result.contains('{{trim}}')) {
      result = result.replaceAll(RegExp(r'{{trim}}', caseSensitive: false), '').trim();
    }

    // {{setvar::name::value}}
    result = result.replaceAllMapped(
      RegExp(r'{{setvar::([\s\S]*?)::([\s\S]*?}}', caseSensitive: false),
      (m) { _sessionVars[m[1]!] = m[2]!; return ''; },
    );

    // {{getvar::name}}
    result = result.replaceAllMapped(
      RegExp(r'{{getvar::([\s\S]*?)}}', caseSensitive: false),
      (m) => _sessionVars[m[1]] ?? '',
    );

    // {{random::a::b::c}}
    result = result.replaceAllMapped(
      RegExp(r'{{random::(.*?)}}', caseSensitive: false),
      (m) {
        final options = m[1]!.split('::');
        return options[DateTime.now().microsecond % options.length];
      },
    );

    // {{roll::1d20}}
    result = result.replaceAllMapped(
      RegExp(r'{{roll::(.*?)}}', caseSensitive: false),
      (m) => _rollDice(m[1]!),
    );

    // {{date}} / {{time}} / {{weekday}}
    final now = DateTime.now();
    result = result.replaceAll(RegExp(r'{{date}}', caseSensitive: false), now.toLocal().toString().split(' ')[0]);
    result = result.replaceAll(RegExp(r'{{time}}', caseSensitive: false), now.toLocal().toString().split(' ')[1]);

    // Unescape: \{ → {
    result = result.replaceAll('\\{', '{').replaceAll('\\}', '}');

    return result;
  }

  String _rollDice(String dice) {
    final match = RegExp(r'(\d+)d(\d+)', caseSensitive: false).firstMatch(dice);
    if (match == null) return dice;
    final count = int.parse(match[1]!);
    final sides = int.parse(match[2]!);
    var total = 0;
    for (var i = 0; i < count; i++) total += Random().nextInt(sides) + 1;
    return total.toString();
  }
}
```

### Step 2.6: Prompt builder (isolate)

Port from JS `workers/generationWorker.js` (999 lines). This is the core engine.

**Strategy**: Port `buildPromptMessagesWorker` as a top-level function so it can run in `compute()`.

```dart
// core/llm/prompt_builder.dart

class PromptPayload {
  final Character character;
  final Persona? persona;
  final Preset preset;
  final List<ChatMessage> history;
  final ApiConfig apiConfig;
  final Map<String, String> sessionVars;

  PromptPayload({...);
}

class PromptResult {
  final List<Map<String, String>> messages; // [{role, content}]
  final int estimatedTokens;
  final Map<String, int> tokenBreakdown;

  PromptResult({...});
}

PromptResult buildPrompt(PromptPayload payload) {
  final macro = MacroEngine();
  final messages = <Map<String, String>>[];
  var totalTokens = 0;

  // 1. Build each preset block → apply macros → add to messages
  for (final block in payload.preset.blocks) {
    if (!block.enabled) continue;

    var content = block.content;
    content = macro.replaceMacros(content,
      charName: payload.character.name,
      charDescription: payload.character.description,
      charScenario: payload.character.scenario,
      charPersonality: payload.character.personality,
      charMesExample: payload.character.mesExample,
      userName: payload.persona?.name,
      userPersona: payload.persona?.prompt,
      sessionVars: payload.sessionVars,
    );

    if (content.isNotEmpty) {
      messages.add({'role': block.role, 'content': content});
      totalTokens += _estimateTokens(content);
    }
  }

  // 2. Build chat history messages
  for (final msg in payload.history) {
    messages.add({'role': msg.role == 'char' ? 'assistant' : msg.role, 'content': msg.content});
    totalTokens += _estimateTokens(msg.content);
  }

  // 3. Trim from front if over context limit
  final contextLimit = payload.apiConfig.contextSize;
  while (totalTokens > contextLimit && messages.length > 1) {
    totalTokens -= _estimateTokens(messages.removeAt(0)['content']!);
  }

  return PromptResult(messages: messages, estimatedTokens: totalTokens, tokenBreakdown: {});
}

int _estimateTokens(String text) => (text.length / 3.35).ceil();
```

**Isolate wrapper:**

```dart
// core/llm/prompt_isolate.dart
Future<PromptResult> buildPromptInIsolate(PromptPayload payload) {
  return compute(buildPrompt, payload);
}
```

Note: `MacroEngine` and `PromptPayload` must be serializable (no closures, no Isar objects). Freezed models are fine.

### Step 2.7: SSE client + streaming

Port from JS `completionsClient.js` (105 lines) + `streamAccumulator.js` (110 lines).

```dart
// core/llm/sse_client.dart
Stream<String> streamChatCompletion({
  required String endpoint,
  required String apiKey,
  required String model,
  required List<Map<String, String>> messages,
  required int maxTokens,
  required double temperature,
  CancelToken? cancelToken,
}) async* {
  final dio = Dio();
  final response = await dio.post(
    endpoint,
    options: Options(
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      responseType: ResponseType.stream,
    ),
    data: {
      'model': model,
      'messages': messages,
      'max_tokens': maxTokens,
      'temperature': temperature,
      'stream': true,
    },
    cancelToken: cancelToken,
  );

  final stream = response.data.stream as ResponseBody;
  var buffer = '';

  await for (final chunk in stream.stream) {
    buffer += utf8.decode(chunk, allowMalformed: true);
    final lines = buffer.split('\n');
    buffer = lines.removeLast(); // keep incomplete line

    for (final line in lines) {
      if (!line.startsWith('data: ')) continue;
      final data = line.substring(6).trim();
      if (data == '[DONE]') return;
      try {
        final json = jsonDecode(data) as Map<String, dynamic>;
        final delta = json['choices']?[0]?['delta']?['content'] as String?;
        if (delta != null) yield delta;
      } catch (_) {}
    }
  }
}
```

```dart
// core/llm/stream_accumulator.dart
class StreamAccumulator {
  final String? tagStart;
  final String? tagEnd;
  final bool hasInlineTags;
  String _text = '';
  String _reasoning = '';

  void consumeDelta(String delta) {
    if (hasInlineTags && tagStart != null && tagEnd != null) {
      final result = _extractInlineReasoning(delta, tagStart!, tagEnd!);
      _text += result.text;
      _reasoning += result.reasoning;
    } else {
      _text += delta;
    }
  }

  ({String text, String reasoning}) _extractInlineReasoning(String raw, String start, String end) {
    // Port from JS streamAccumulator.js:10 extractInlineReasoning
    // Split on start/end tags, categorize segments
    var text = '';
    var reasoning = '';
    var inReasoning = false;
    final parts = raw.split(RegExp(RegExp.escape(start)));
    for (var i = 0; i < parts.length; i++) {
      if (i > 0) {
        final endSplit = parts[i].split(RegExp(RegExp.escape(end)));
        if (endSplit.length > 1) {
          reasoning += endSplit[0];
          text += endSplit.sublist(1).join(end);
          inReasoning = false;
        } else {
          reasoning += parts[i];
          inReasoning = true;
        }
      } else {
        text += parts[i];
      }
    }
    return (text: text, reasoning: reasoning);
  }

  String get text => _text;
  String get reasoning => _reasoning;
}
```

### Step 2.8: Response normalizer

Port from JS `responseNormalizer.js` (50 lines).

```dart
// core/llm/response_normalizer.dart
class ResponseNormalizer {
  static ({String content, String? reasoningContent}) extractOpenAiMessage(
    Map<String, dynamic> data, [
    String contextLabel = 'API response',
  ]) {
    final choice = data['choices']?[0];
    final message = choice?['message'];
    final content = message?['content'] as String? ?? '';
    final reasoningContent = message?['reasoning_content'] as String? ??
        message?['reasoning'] as String?;
    return (content: content, reasoningContent: reasoningContent);
  }

  static ({String text, String? reasoning, List<String> allReasoning}) normalizeReasoningOutput({
    required String content,
    required bool requestReasoning,
    String? rawReasoning,
    bool hasInlineTags = false,
    String? tagStart,
    String? tagEnd,
  }) {
    if (!requestReasoning) return (text: content, reasoning: null, allReasoning: []);
    // Merge inline + model-provided reasoning
    return (text: content, reasoning: rawReasoning, allReasoning: [if (rawReasoning != null) rawReasoning]);
  }
}
```

### Step 2.9: Chat notifier (state management)

```dart
// features/chat/chat_provider.dart
final chatProvider = AsyncNotifierProvider.family<ChatNotifier, ChatState, String>(ChatNotifier.new);

class ChatState {
  final ChatSession session;
  final bool isGenerating;
  final String streamingText;
  final String? streamingReasoning;

  ChatState({required this.session, this.isGenerating = false, this.streamingText = '', this.streamingReasoning});
  ChatState copyWith({ChatSession? session, bool? isGenerating, String? streamingText, String? streamingReasoning}) =>
    ChatState(session: session ?? this.session, isGenerating: isGenerating ?? this.isGenerating,
      streamingText: streamingText ?? this.streamingText, streamingReasoning: streamingReasoning ?? this.streamingReasoning);
}

class ChatNotifier extends FamilyAsyncNotifier<ChatState, String> {
  CancelToken? _cancelToken;

  @override
  Future<ChatState> build(String arg) async {
    final repo = ref.read(chatRepoProvider);
    final sessions = await repo.getByCharacterId(arg);
    final session = sessions.isNotEmpty ? sessions.first : await _createSession(arg);
    return ChatState(session: session);
  }

  Future<void> sendMessage(String text) async {
    final currentState = state.value!;
    final userMsg = ChatMessage(
      id: generateId(), role: 'user', content: text, timestamp: DateTime.now().millisecondsSinceEpoch,
    );
    final updatedMessages = [...currentState.session.messages, userMsg];
    state = AsyncData(currentState.copyWith(
      session: currentState.session.copyWith(messages: updatedMessages),
      isGenerating: true, streamingText: '',
    ));

    try {
      // 1. Build prompt in isolate
      final payload = await _buildPayload(currentState.session, updatedMessages);
      final promptResult = await buildPromptInIsolate(payload);

      // 2. Stream response
      final apiConfig = await ref.read(apiConfigProvider.future);
      final activeConfig = apiConfig.first; // simplified for MVP
      _cancelToken = CancelToken();
      final accumulator = StreamAccumulator(
        tagStart: activeConfig.reasoningTagStart,
        tagEnd: activeConfig.reasoningTagEnd,
        hasInlineTags: activeConfig.reasoningTagStart != null,
      );

      await for (final delta in streamChatCompletion(
        endpoint: activeConfig.endpoint,
        apiKey: activeConfig.apiKey,
        model: activeConfig.model,
        messages: promptResult.messages,
        maxTokens: activeConfig.maxTokens,
        temperature: activeConfig.temperature,
        cancelToken: _cancelToken,
      )) {
        accumulator.consumeDelta(delta);
        state = AsyncData(currentState.copyWith(streamingText: accumulator.text, streamingReasoning: accumulator.reasoning));
      }

      // 3. Save assistant message
      final assistantMsg = ChatMessage(
        id: generateId(), role: 'assistant', content: accumulator.text,
        reasoning: accumulator.reasoning.isNotEmpty ? accumulator.reasoning : null,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );
      final finalMessages = [...updatedMessages, assistantMsg];
      final finalSession = currentState.session.copyWith(messages: finalMessages);
      await ref.read(chatRepoProvider).put(finalSession);
      state = AsyncData(ChatState(session: finalSession));
    } catch (e) {
      state = AsyncData(currentState.copyWith(isGenerating: false));
    }
  }

  void abortGeneration() {
    _cancelToken?.cancel();
    state = AsyncData(state.value!.copyWith(isGenerating: false));
  }
}
```

### Step 2.10: Character list screen

```dart
// features/character_list/character_list_screen.dart
class CharacterListScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final characters = ref.watch(charactersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Glaze'),
        actions: [
          IconButton(icon: const Icon(Icons.settings), onPressed: () => context.go('/settings/api')),
          IconButton(icon: const Icon(Icons.add), onPressed: () => _importCharacter(context, ref)),
        ],
      ),
      body: characters.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (chars) => chars.isEmpty
          ? const Center(child: Text('No characters. Import one!'))
          : ListView.builder(
              itemCount: chars.length,
              itemBuilder: (_, i) => _CharacterTile(character: chars[i]),
            ),
      ),
    );
  }

  Future<void> _importCharacter(BuildContext context, WidgetRef ref) async {
    // Use file_picker or platform-specific file selection
    // Call CharacterImporter.importFromFile
    // Add to repo via ref.read(charactersProvider.notifier).add(char)
  }
}
```

### Step 2.11: Chat screen

```dart
// features/chat/chat_screen.dart
class ChatScreen extends ConsumerWidget {
  final String charId;
  const ChatScreen({required this.charId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chatState = ref.watch(chatProvider(charId));
    final controller = TextEditingController();

    return Scaffold(
      appBar: AppBar(
        title: Text(ref.read(characterProvider(charId))?.name ?? 'Chat'),
        actions: [
          if (chatState.isGenerating)
            IconButton(icon: const Icon(Icons.stop), onPressed: () => ref.read(chatProvider(charId).notifier).abortGeneration()),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: chatState.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (state) => _MessageList(
                messages: state.session.messages,
                streamingText: state.isGenerating ? state.streamingText : null,
              ),
            ),
          ),
          _InputBar(
            controller: controller,
            onSend: (text) {
              ref.read(chatProvider(charId).notifier).sendMessage(text);
              controller.clear();
            },
            isGenerating: chatState.value?.isGenerating ?? false,
          ),
        ],
      ),
    );
  }
}
```

### Step 2.12: Message list + bubbles

```dart
class _MessageList extends StatelessWidget {
  final List<ChatMessage> messages;
  final String? streamingText;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      reverse: true,
      slivers: [
        if (streamingText != null)
          SliverToBoxAdapter(child: _MessageBubble(content: streamingText!, isUser: false, isStreaming: true)),
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (_, i) {
              final msg = messages[messages.length - 1 - i]; // newest first
              return _MessageBubble(content: msg.content, isUser: msg.role == 'user', isStreaming: false);
            },
            childCount: messages.length,
          ),
        ),
      ],
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final String content;
  final bool isUser;
  final bool isStreaming;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isUser ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: MarkdownBody(data: content), // flutter_markdown
      ),
    );
  }
}
```

### Step 2.13: API settings screen

```dart
// features/settings/api_settings_screen.dart
class ApiSettingsScreen extends ConsumerStatefulWidget { ... }

class _ApiSettingsScreenState extends ConsumerState<ApiSettingsScreen> {
  late TextEditingController _endpointCtrl, _keyCtrl, _modelCtrl;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('API Settings')),
      body: ListView(
        children: [
          TextField(controller: _endpointCtrl, decoration: const InputDecoration(labelText: 'Endpoint')),
          TextField(controller: _keyCtrl, decoration: const InputDecoration(labelText: 'API Key'), obscureText: true),
          TextField(controller: _modelCtrl, decoration: const InputDecoration(labelText: 'Model')),
          // maxTokens, temperature, etc.
          ElevatedButton(onPressed: _save, child: const Text('Save')),
          ElevatedButton(onPressed: _testConnection, child: const Text('Test Connection')),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final config = ApiConfig(id: generateId(), endpoint: _endpointCtrl.text, apiKey: _keyCtrl.text, model: _modelCtrl.text);
    await ref.read(apiConfigProvider.notifier).add(config);
  }

  Future<void> _testConnection() async {
    // Send minimal request to verify endpoint/key/model work
  }
}
```

### Deliverables Phase 2 (Go/No-Go checkpoint)
- [x] Import character from PNG (tEXt chunk parsed, avatar saved)
- [x] Import character from JSON
- [x] Character list displays all imported characters
- [x] Tap character → opens chat screen
- [x] Type message → builds prompt in isolate → streams response
- [x] Streaming text updates in real-time in chat bubble
- [x] Abort generation works
- [x] API settings persist across app restarts
- [x] Runs on iOS without WKWebView issues
- [x] Runs on Android
- [x] Runs on Windows

---

## Phase 2.5: Data Migration from JS Glaze

### Context

Glaze JS has `exportFullBackupAsync()` in `backupService.js` that produces a `.glz` JSON file containing all user data. We already import character cards (PNG/JSON/ZIP) via `CharacterImporter`. What's missing is importing the **full backup** which includes chats, personas, presets, API configs, and lorebooks stored in IDB keyvalue store.

### Glaze JS backup format (.glz)

```json
{
  "_isGlazeBackup": true,
  "_glazeVersion": 1,
  "keyvalue": {
    "gz_chats_{charId}": { "sessions": { "0": [msg, ...], "1": [msg, ...] } },
    "gz_api_connection_presets": [ { id, name, endpoint, key, model, temp, ... }, ... ],
    "silly_cradle_presets": { "presets": [ { id, name, prompt_order, ... }, ... ] },
    "gz_lorebooks": { "lorebooks": [ { id, name, entries, ... }, ... ] },
    "gz_active_preset": "preset_id",
    "gz_active_persona": "persona_id",
    "gz_theme_state": { ... },
    "gz_chat_recovery_{id}": { ... },
    ...other keys
  },
  "characters": [ { id, name, avatar, description, ... }, ... ],
  "personas": [ { id, name, prompt, avatar, ... }, ... ],
  "localStorage": { "key": "value", ... }
}
```

### What we already handle

- **Characters** from PNG/JSON/ZIP via `CharacterImporter` — but NOT from IDB format (data URL avatars, different field layout)
- **Presets** from SillyTavern JSON via `PresetListScreen._parseSillyTavernPreset()` — but NOT from Glaze internal format (`silly_cradle_presets`)
- **Personas** from IDB format — NOT handled yet

### Step 2.14: Migration service

```dart
// core/services/migration_service.dart
class MigrationService {
  final CharacterRepo _charRepo;
  final ChatRepo _chatRepo;
  final PersonaRepo _personaRepo;
  final PresetRepo _presetRepo;
  final ApiConfigRepo _apiRepo;
  final ImageStorageService _imageStorage;

  Future<MigrationResult> importGlzBackup(String jsonPath) async {
    final bytes = await File(jsonPath).readAsBytes();
    final data = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;

    if (data['_isGlazeBackup'] != true) {
      throw FormatException('Not a valid Glaze backup file');
    }

    final kv = Map<String, dynamic>.from(data['keyvalue'] ?? {});
    final result = MigrationResult();

    // 1. Characters (from IDB 'characters' store)
    for (final charJson in data['characters'] as List? ?? []) {
      final char = await _mapCharacter(charJson);
      await _charRepo.put(char);
      result.characters++;
    }

    // 2. Personas
    for (final pJson in data['personas'] as List? ?? []) {
      final persona = _mapPersona(pJson);
      await _personaRepo.put(persona);
      result.personas++;
    }

    // 3. Chats (from keyvalue, gz_chats_* keys)
    for (final entry in kv.entries) {
      if (entry.key.startsWith('gz_chats_')) {
        final charId = entry.key.replaceFirst('gz_chats_', '');
        final chatData = entry.value as Map<String, dynamic>;
        final sessions = chatData['sessions'] as Map<String, dynamic>? ?? {};
        for (final sessionEntry in sessions.entries) {
          final sessionIndex = int.tryParse(sessionEntry.key) ?? 0;
          final session = await _mapChatSession(charId, sessionIndex, sessionEntry.value);
          await _chatRepo.put(session);
          result.sessions++;
        }
      }
    }

    // 4. API configs (from keyvalue, gz_api_connection_presets)
    final apiConfigs = kv['gz_api_connection_presets'];
    if (apiConfigs is List) {
      for (final cfgJson in apiConfigs) {
        final config = _mapApiConfig(cfgJson);
        await _apiRepo.put(config);
        result.apiConfigs++;
      }
    }

    // 5. Presets (from keyvalue, silly_cradle_presets)
    final presetsData = kv['silly_cradle_presets'];
    if (presetsData is Map && presetsData['presets'] is List) {
      for (final pJson in presetsData['presets']) {
        final preset = _mapGlazePreset(pJson);
        await _presetRepo.put(preset);
        result.presets++;
      }
    }

    // 6. Mark migration complete
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('gz_migration_done', true);

    return result;
  }
}
```

### Key mapping details

**Characters** (IDB → Flutter):
- `avatar` is a data URL → decode to bytes → `ImageStorageService.saveAvatar()`
- Field names already match (name, description, personality, scenario, first_mes, etc.)

**Chat messages** (IDB → Flutter):
- Message `role`: JS `'char'` → Dart `'assistant'`
- Message `mes`/`text` → `content`
- Message `persona.id`/`persona.name` → `personaId`/`personaName`
- Message `swipes` → `swipes`, `swipe_id` → `swipeId`
- Message `reasoning` → `reasoning`
- Message `is_hidden` → hidden flag on ChatMessage

**API configs** (IDB → Flutter):
- `key` → `apiKey`
- `temp` → `temperature`
- `reasoningTags.start`/`end` → `reasoningTagStart`/`reasoningTagEnd`

**Presets** (Glaze internal → Flutter):
- `prompt_order` → convert to ordered `PresetBlock` list
- `regex_scripts` → `List<PresetRegex>`
- Same block structure as SillyTavern but already in Glaze format

### Step 2.15: Migration UI

Add a "Import from Glaze" button in the Menu/Tools screen that:
1. Opens file picker filtered for `.glz` files
2. Shows progress dialog during import
3. Displays summary (X characters, Y chats, Z presets imported)
4. Marks migration as done in SharedPreferences

### Deliverables Phase 2.5
- [x] `MigrationService` with .glz backup import
- [x] Character import from IDB format (data URL avatar → file)
- [x] Chat session import from gz_chats_* keyvalue entries
- [x] API config import
- [x] Preset import from Glaze internal format
- [x] Persona import
- [x] Migration UI in Menu/Tools
- [x] One-time migration flag in SharedPreferences

---

# PART 2: Post-MVP (Day 19–57)

After Day 18, if the Go/No-Go passes, continue with feature parity.

---

## Phase 3: Presets & Personas (Day 19–23)

### Step 3.1: Preset import from SillyTavern format

Port from JS `presetImportService.js` (471 lines), specifically `convertSTPreset()`.

```dart
// core/services/preset_import_service.dart
class PresetImportService {
  Preset convertSTPreset(Map<String, dynamic> data, String fileName) {
    // 1. Parse prompt_order (ST stores layout under character_id 100001)
    // 2. Map ST identifiers to Glaze block IDs via ST_TO_BLOCK_MAP
    // 3. Create PresetBlock for each prompt in order
    // 4. Handle orphaned prompts (not in order list)
    // 5. Ensure mandatory blocks exist (worldInfoBefore, user_persona, etc.)
    // 6. Add auto-blocks: summary, authors_note, guided_generation
    // 7. Return complete Preset
  }
}
```

Key mappings from JS `presetImportService.js:62-76`:
```
ST identifier    → Glaze block ID
personaDescription → user_persona
charDescription    → char_card
charPersonality    → char_personality
scenario           → scenario
chatHistory        → chat_history
dialogueExamples   → example_dialogue
worldInfoBefore    → worldInfoBefore
worldInfoAfter     → worldInfoAfter
```

### Step 3.2: Preset editor screen

```
┌─────────────────────────────┐
│ ← Edit Preset: Default      │
│─────────────────────────────│
│ [Blocks]  [Regex]           │
│─────────────────────────────│
│ ☑ World Info Before  system │
│ ☑ User Persona       system │
│ ☑ Character Card     system │
│ ☐ Character Personality sys │
│ ☑ Scenario           system │
│ ☐ Example Dialogue   system │
│ ☑ World Info After   system │
│ ☑ Chat History       system │
│ ☑ Summary            system │
│ ☑ Author's Note      system │
│                             │
│ [+ Add Block]               │
└─────────────────────────────┘
```

- ReorderableListView for drag-to-reorder
- Tap block → opens block editor (role, content, depth, enabled)
- Import/Export preset as JSON

### Step 3.3: Block editor

```dart
class BlockEditorScreen extends ConsumerStatefulWidget {
  final PresetBlock block;
  final Character? character; // for macro preview
  // ...
}

// Body: TextField for content with macro preview button
// Role dropdown: system / user / assistant
// Insertion mode: relative / depth
// Depth slider (if insertion_mode == depth)
// Enabled toggle
```

### Step 3.4: Persona management

Port from JS `personaState.js` (197 lines).

```dart
// core/state/persona_provider.dart
class PersonaNotifier extends AsyncNotifier<List<Persona>> { ... }

// Persona connections: which persona is active per character/chat
class PersonaConnectionState {
  Map<String, String> characterConnections; // charId → personaId
  Map<String, String> chatConnections;      // chatId → personaId
  String? globalPersonaId;
}
```

Resolution order (from JS): Chat > Character > Global

### Step 3.5: Persona selector in chat

- Dropdown in chat AppBar showing active persona
- Tap to switch persona for this chat
- Persona management screen: create/edit/delete

### Deliverables Phase 3
- [x] Preset CRUD (create, read, update, delete)
- [x] Preset import from SillyTavern JSON format
- [x] Default presets pre-loaded on first launch
- [x] Block editor with macro preview
- [x] Regex editor (add/edit/delete regex scripts)
- [x] Persona CRUD + avatar
- [x] Persona connections per character/chat
- [x] Persona selector in chat screen

---

## Phase 4: Lorebooks + Vector Search (Day 24–31)

### Step 4.1: Lorebook data model

```dart
@freezed
class Lorebook with _$Lorebook {
  const factory Lorebook({
    required String id,
    required String name,
    String? comment,
    @Default([]) List<LorebookEntry> entries,
    @Default('global') String activationScope, // 'global' | 'character' | 'chat'
    String? activationTargetId,
    @Default(true) bool enabled,
    @Default(0) int updatedAt,
  }) = _Lorebook;
}

@freezed
class LorebookEntry with _$LorebookEntry {
  const factory LorebookEntry({
    required String id,
    @Default([]) List<String> keys,
    @Default([]) List<String> secondaryKeys,
    required String content,
    String? comment,
    @Default(true) bool enabled,
    @Default('before_char') String position,
    @Default(100) int insertionOrder,
    @Default(false) bool caseSensitive,
    @Default(false) bool constant,
    @Default(false) bool vectorSearch,
    @Default(5) int selectiveLogic,
  }) = _LorebookEntry;
}
```

### Step 4.2: Lorebook keyword scanner

Port from JS `lorebookSearchService.js` (182 lines). This is a pure function — perfect for isolate.

```dart
// core/llm/lorebook_scanner.dart
List<LorebookEntry> scanLorebooks({
  required List<ChatMessage> history,
  required Character? character,
  required String textToScan,
  required String? chatId,
  required List<Lorebook> activeLorebooks,
  required LorebookGlobalSettings globalSettings,
}) {
  // 1. Filter active lorebooks (enabled + character/chat activations)
  // 2. Collect candidate entries (skip disabled, apply characterFilter)
  // 3. Add constant entries
  // 4. Recursive scan loop (max 5 iterations):
  //    a. For each candidate, check primary keys match against scanSource
  //    b. Match logic: 'glaze' boundary mode, regex mode, plain includes
  //    c. If primary matched, check secondary keys with selective logic
  //    d. Apply sticky/cooldown
  //    e. Apply probability
  //    f. Add to relevant entries, append content to scanSource if recursive
  // 5. Sort by insertionOrder, slice to maxInjectedEntries
  // 6. Return matched entries
}
```

Match logic from JS `lorebookSearchService.js:66-110`:
- `wholeWords === 'glaze'` → boundary regex with `GLAZE_BOUNDARIES`
- `wholeWords === true` → `\b${pattern}\b`
- Default → `new RegExp(pattern, flags).test(sourceText)` or fallback to `.includes()`

`GLAZE_BOUNDARIES` constant (JS line 7):
```dart
const glazeBoundaries = r'[\s.,!?;:"\'\u201C\u201D\u2018\u2019\u00AB\u00BB(){}\[\]—–]';
```

### Step 4.3: Integrate scanner into prompt builder

In `buildPrompt()`:
```dart
// After building preset blocks, before chat history:
final lorebookEntries = scanLorebooks(
  history: payload.history,
  character: payload.character,
  textToScan: historyText,
  chatId: null, // MVP: no chat-scoped lorebooks
  activeLorebooks: payload.lorebooks,
  globalSettings: LorebookGlobalSettings.defaults(),
);

for (final entry in lorebookEntries) {
  var content = macro.replaceMacros(entry.content, ...);
  if (content.isNotEmpty) {
    messages.add({'role': 'system', 'content': content});
  }
}
```

### Step 4.5: Vector search — embedding storage

Vector search is the semantic counterpart to keyword lorebook scanning. Entries flagged `vectorSearch: true` skip keyword matching and instead match by cosine similarity against the current context.

Port from JS `core/llm/pipeline/steps.js:stepVectorSearch` + `core/llm/usecases/vectorLoreInjection.js`.

```dart
// core/llm/vector/embedding_service.dart
class EmbeddingService {
  final Dio _dio;
  final String _endpoint;
  final String _apiKey;
  final String _model;

  Future<List<double>> embed(String text) async {
    final response = await _dio.post(
      _endpoint,
      options: Options(headers: {'Authorization': 'Bearer $_apiKey'}),
      data: {'model': _model, 'input': text},
    );
    final embedding = response.data['data'][0]['embedding'] as List;
    return embedding.map((e) => (e as num).toDouble()).toList();
  }
}
```

Isar collection for embeddings:

```dart
@collection
class EmbeddingCollection {
  Id id = Isar.autoIncrement;
  late String sourceId;        // lorebook entry ID
  late String sourceType;      // 'lorebook_entry' | 'chat_message'
  late String sourceContent;   // original text (for display)
  late int updatedAt;
  String? vectorJson;          // JSON-encoded List<double>
}
```

### Step 4.6: Vector search — similarity engine

```dart
// core/llm/vector/vector_search.dart
class VectorSearchEngine {
  final EmbeddingService _embeddingService;
  final EmbeddingRepo _embeddingRepo;

  Future<List<VectorSearchHit>> search({
    required String query,
    required double threshold,       // cosine similarity cutoff (e.g. 0.7)
    required int maxResults,
    required List<String> sourceFilter, // e.g. ['lorebook_entry']
  }) async {
    // 1. Embed the query
    final queryVec = await _embeddingService.embed(query);

    // 2. Load all stored embeddings matching sourceFilter
    final candidates = await _embeddingRepo.getBySourceTypes(sourceFilter);

    // 3. Compute cosine similarity for each
    final hits = <VectorSearchHit>[];
    for (final candidate in candidates) {
      final vec = _parseVector(candidate.vectorJson);
      final similarity = _cosineSimilarity(queryVec, vec);
      if (similarity >= threshold) {
        hits.add(VectorSearchHit(
          sourceId: candidate.sourceId,
          sourceType: candidate.sourceType,
          content: candidate.sourceContent,
          score: similarity,
        ));
      }
    }

    // 4. Sort by score descending, take top maxResults
    hits.sort((a, b) => b.score.compareTo(a.score));
    return hits.take(maxResults).toList();
  }

  double _cosineSimilarity(List<double> a, List<double> b) {
    var dot = 0.0, normA = 0.0, normB = 0.0;
    for (var i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    return dot / (sqrt(normA) * sqrt(normB));
  }

  List<double> _parseVector(String? json) =>
    json != null ? List<double>.from(jsonDecode(json)) : [];
}
```

### Step 4.7: Vector search — pipeline integration

Port from JS `core/llm/pipeline/steps.js:stepVectorSearch` + `stepLateVectorLoreInjection`.

```dart
// In prompt_builder.dart, add after keyword lorebook scan:

Future<void> injectVectorLoreEntries(PromptPayload payload, List<Map<String, String>> messages) async {
  // 1. Build query text from last N messages
  final recentText = payload.history.reversed.take(3).map((m) => m.content).join('\n');

  // 2. Run vector search
  final hits = await VectorSearchEngine(...).search(
    query: recentText,
    threshold: 0.7,
    maxResults: 10,
    sourceFilter: ['lorebook_entry'],
  );

  // 3. Deduplicate against already-injected keyword entries
  final alreadyInjected = messages.map((m) => m['content']).toSet();
  final newHits = hits.where((h) => !alreadyInjected.contains(h.content));

  // 4. Inject before chat history (or after keyword lore, depending on position)
  for (final hit in newHits) {
    var content = macro.replaceMacros(hit.content, ...);
    if (content.isNotEmpty) {
      messages.add({'role': 'system', 'content': content});
    }
  }
}
```

### Step 4.8: Vector search — indexing

When a lorebook entry has `vectorSearch: true`:

```dart
// core/llm/vector/indexing_service.dart
class VectorIndexingService {
  final EmbeddingService _embeddingService;
  final EmbeddingRepo _embeddingRepo;

  Future<void> indexLorebookEntry(LorebookEntry entry) async {
    if (!entry.vectorSearch || entry.content.isEmpty) return;

    final existing = await _embeddingRepo.getBySourceId(entry.id);
    if (existing != null && existing.updatedAt >= entry.updatedAt) return; // up to date

    final vector = await _embeddingService.embed(entry.content);
    await _embeddingRepo.put(EmbeddingRecord(
      sourceId: entry.id,
      sourceType: 'lorebook_entry',
      sourceContent: entry.content,
      vector: vector,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    ));
  }

  Future<void> reindexAll(List<Lorebook> lorebooks) async {
    for (final lb in lorebooks) {
      for (final entry in lb.entries.where((e) => e.vectorSearch && e.enabled)) {
        await indexLorebookEntry(entry);
      }
    }
  }
}
```

### Step 4.9: Vector search — embedding config UI

- Settings: embedding endpoint, API key, model (default: `text-embedding-3-small`)
- "Reindex All" button
- Per-entry toggle in lorebook entry editor: "Enable vector search"
- Status indicator: indexed / not indexed / indexing...

### Step 4.10: Lorebook UI

- Lorebook list screen (all lorebooks, with activation indicators)
- Lorebook editor (name, entries, activation scope)
- Entry editor (keys, content, position, enabled, constant, selective logic, vector search toggle)
- Character detail: show attached lorebooks, toggle activation

### Deliverables Phase 4
- [x] Lorebook CRUD + Isar storage
- [x] Lorebook keyword scanner (runs in prompt isolate)
- [x] Constant entry injection
- [x] Recursive scan
- [x] Selective logic (any/all/not any/not all)
- [x] Sticky/cooldown
- [x] Activation per character/chat
- [x] Embedding service (OpenAI-compatible API)
- [x] Embedding storage (Isar)
- [x] Vector similarity search with cosine distance
- [x] Vector search pipeline step (after keyword scan)
- [x] Late vector lore injection (dedup vs keyword)
- [x] Indexing service (on-entry + reindex all)
- [x] Lorebook UI (list, editor, entry editor with vector toggle)
- [ ] Import lorebook from SillyTavern JSON
- [x] Embedding config UI (endpoint, model, reindex)

---

## Phase 5: Regex Service (Day 32–33)

### Step 5.1: Regex service

Port from JS `regexService.js` (172 lines).

```dart
// core/llm/regex_service.dart
class RegexService {
  String applyRegexes(String text, {
    required int placementFilter,
    required int ephemeralityFilter,
    required List<PresetRegex> allScripts,
    Character? char,
    Persona? persona,
    int? depth,
  }) {
    var processed = text;

    for (final script in allScripts) {
      if (script.disabled) continue;
      if (!script.placement.contains(placementFilter)) continue;
      if (!script.ephemerality.contains(ephemeralityFilter)) continue;
      if (depth != null) {
        if (script.minDepth != null && depth < script.minDepth!) continue;
        if (script.maxDepth != null && depth > script.maxDepth!) continue;
      }

      // 1. Trim tokens
      if (script.trimOut.isNotEmpty) {
        for (final token in script.trimOut.split('\n').where((t) => t.trim().isNotEmpty)) {
          processed = processed.replaceAll(token, '');
        }
      }

      // 2. Regex pattern
      if (script.regex.isNotEmpty) {
        var pattern = script.regex;
        var replacement = script.replacement;
        var flags = 'g';

        // Handle macros in pattern
        if (script.macroRules != '0') {
          pattern = MacroEngine().replaceMacros(pattern, charName: char?.name ?? 'Character', ...);
          replacement = MacroEngine().replaceMacros(replacement, ...);
        }

        // Support /pattern/flags format
        if (pattern.startsWith('/') && pattern.lastIndexOf('/') > 0) {
          final lastSlash = pattern.lastIndexOf('/');
          flags = pattern.substring(lastSlash + 1);
          if (!flags.contains('g')) flags += 'g';
          pattern = pattern.substring(1, lastSlash);
        }

        try {
          processed = processed.replaceAllMapped(RegExp(pattern), replacement);
        } catch (_) { /* invalid regex, skip */ }
      }
    }

    return processed;
  }
}
```

Note: Dart `replaceAllMapped` with a replacement string doesn't support `$1`/`$2` backreferences the same way as JS. For regex replacement with capture groups, use `replaceFn`:

```dart
processed = processed.replaceAllMapped(RegExp(pattern), (match) {
  // Apply replacement string with $1, $2 substitution
  var result = replacement;
  for (var i = 0; i <= match.groupCount; i++) {
    result = result.replaceAll('\$$i', match.group(i) ?? '');
  }
  return result;
});
```

### Step 5.2: Integrate into prompt builder

Apply regexes to:
- User input (placement=1) before adding to messages
- AI output (placement=2) after streaming completes
- World info content (placement=4) after lorebook injection

### Deliverables Phase 5
- [x] Regex service with placement/ephemerality/depth filtering
- [x] Trim token support
- [x] /pattern/flags parsing
- [x] Macro expansion in regex patterns
- [x] Backreference support in replacements
- [x] Integrated into prompt builder pipeline

---

## Phase 6: Chat Import/Export (Day 34–36)

### Step 6.1: SillyTavern JSONL import

Port from JS `chatImporter.js` (618 lines), specifically `importSillyTavernChat()`.

```dart
// core/services/chat_import_service.dart
class ChatImportService {
  Future<ImportResult> importSillyTavernChat({
    required String filePath,
    required String characterId,
    Persona? userPersona,
  }) async {
    final lines = await File(filePath).readAsLines();

    // 1. First line: metadata (user_name, character_name, chat_metadata)
    // 2. Remaining lines: one JSON object per line
    // 3. Each line: { name, is_user, is_system, send_date, mes, swipes, swipe_id, extra }
    // 4. Convert each to ChatMessage via _convertMessage()
    // 5. Create new session, save messages

    return ImportResult(characterId: characterId, sessionId: sessionId, messageCount: messages.length);
  }

  ChatMessage _convertMessage(Map<String, dynamic> stMsg, Persona? userPersona) {
    final role = stMsg['is_user'] == true ? 'user' : 'assistant';
    var timestamp = DateTime.now().millisecondsSinceEpoch;
    if (stMsg['send_date'] != null) {
      final parsed = DateTime.tryParse(stMsg['send_date']);
      if (parsed != null) timestamp = parsed.millisecondsSinceEpoch;
    }

    return ChatMessage(
      id: stMsg['extra']?['glazeMessageId'] ?? generateId(),
      role: role,
      content: stMsg['mes'] ?? '',
      timestamp: timestamp,
      personaId: role == 'user' ? userPersona?.id : null,
      personaName: role == 'user' ? (userPersona?.name ?? stMsg['name'] ?? 'User') : null,
      swipes: List<String>.from(stMsg['swipes'] ?? [stMsg['mes'] ?? '']),
      swipeId: stMsg['swipe_id'] ?? 0,
      reasoning: stMsg['extra']?['reasoning'],
    );
  }
}
```

Also support `.glzchat.json` format (Glaze native export).

### Step 6.2: Chat export to JSONL

Port from JS `chatImporter.js:293-438` `exportSillyTavernChat()`.

```dart
class ChatExportService {
  Future<void> exportSillyTavernChat(ChatSession session, String charName) async {
    final lines = <String>[];

    // 1. Metadata line
    lines.add(jsonEncode({
      'user_name': 'User',
      'character_name': charName,
      'create_date': _formatSTDate(DateTime.now()),
      'chat_metadata': {'exported_from': 'Glaze Flutter', 'import_date': DateTime.now().millisecondsSinceEpoch},
    }));

    // 2. Message lines
    for (final msg in session.messages) {
      final isUser = msg.role == 'user';
      lines.add(jsonEncode({
        'name': isUser ? (msg.personaName ?? 'User') : charName,
        'is_user': isUser,
        'is_system': msg.role == 'system',
        'send_date': _formatSTDate(DateTime.fromMillisecondsSinceEpoch(msg.timestamp ?? 0)),
        'mes': msg.content,
        'swipe_id': msg.swipeId,
        'swipes': msg.swipes,
        'extra': {
          if (msg.reasoning != null) 'reasoning': msg.reasoning,
          'glazeMessageId': msg.id,
        },
      }));
    }

    final filename = '${charName.replaceAll(RegExp(r'[/\\?%*:|"<>\.]'), '_')} - ${DateTime.now().toIso8601String().split('.')[0]}.jsonl';
    await FileSaver.save(filename, lines.join('\n'), 'application/jsonl');
  }
}
```

### Step 6.3: Character export

Port from JS `characterIO.js:549-680`.

- `exportCharacterAsV2Json` — straightforward JSON serialization
- `exportCharacterAsV2Png` — requires PNG manipulation (insert tEXt chunk)
- `exportCharacterAsCharX` — ZIP with card.json + images

PNG export is the hardest. Use `package:image` for canvas operations:
```dart
Future<Uint8List> exportPngWithCharacterData(Uint8List pngBytes, Map<String, dynamic> cardData) async {
  // 1. Find IHDR end (offset 33)
  // 2. Build tEXt chunk: 'chara' + null + base64(JSON)
  // 3. Compute CRC32 over type + data
  // 4. Assemble chunk: length(4) + type(4) + data(N) + crc(4)
  // 5. Insert after IHDR
  // 6. Return new PNG bytes
}
```

### Step 6.4: SillyTavern backup import

Port from JS `stBackupImporter.js` (207 lines).

```dart
class STBackupImporter {
  Future<ImportResult> importFromZip(String zipPath) async {
    final archive = ZipDecoder().decodeBytes(await File(zipPath).readAsBytes());

    // Phase 1: Characters from characters/*.png
    // Phase 2: Lorebooks from worlds/*.json
    // Phase 3: Presets from OpenAI Settings/*.json
    // Phase 4: Chats from chats/{charName}/*.jsonl
    // Phase 5: Personas from settings.json

    return result;
  }
}
```

### Step 6.5: Tavo backup import

Port from JS `tavoBackupReader.js` (857 lines). This is pure binary parsing — direct 1:1 port.

```dart
class TavoBackupImporter {
  TavoData parseLMDB(Uint8List buffer) {
    final dv = ByteData.view(buffer.buffer);
    final categories = <String, List<TavoEntity>>{};

    // Walk pages at 4096-byte intervals
    // For each leaf page: parse B-tree nodes
    // Extract entity_id, type_id, data
    // Parse ObjectBox/FlatBuffer entities using field definitions
    // Group messages by conversationId

    return TavoData(categories: categories, chats: chats);
  }

  Future<ImportResult> importFromZip(String zipPath) async {
    // 1. Extract data.mdb from ZIP
    // 2. Parse LMDB
    // 3. Convert each entity type to Glaze models
    // 4. Save to repos
  }
}
```

Field definitions from JS `tavoBackupReader.js:152-224`:
```dart
const characterFields = [
  FieldDef(index: 1, name: 'name', type: 'string'),
  FieldDef(index: 3, name: 'description', type: 'string'),
  FieldDef(index: 4, name: 'scenario', type: 'string'),
  FieldDef(index: 5, name: 'first_mes', type: 'string'),
  // ... (copy all from JS)
];
```

### Step 6.6: Full backup export/import

Port from JS `backupService.js` (221 lines).

- Export: serialize all Isar collections + SharedPreferences to JSON
- Import: clear DB, deserialize, write back

### Deliverables Phase 6
- [ ] SillyTavern JSONL chat import
- [ ] Glaze chat package (.glzchat.json) import
- [ ] Chat export to JSONL
- [ ] Character export as JSON
- [ ] Character export as PNG with embedded data
- [ ] Character export as CharX/ZIP
- [ ] SillyTavern backup ZIP import
- [ ] Tavo backup ZIP import
- [ ] Full backup export/import

---

## Phase 7: Image Generation (Day 37–41)

### Step 7.1: Image generation service

Port from JS `core/llm/usecases/imageGeneration.js` pattern. Calls an image generation API (OpenAI DALL-E, Stable Diffusion WebUI, etc.) and stores the result.

```dart
// core/services/image_generation_service.dart
class ImageGenerationService {
  final Dio _dio;

  Future<GeneratedImage> generate({
    required String prompt,
    required String endpoint,
    required String apiKey,
    required String model,
    required String size,        // e.g. '1024x1024'
    required int n,              // number of images
    String? negativePrompt,
    int? steps,
    double? cfgScale,
    String? sampler,
    int? seed,
  }) async {
    final response = await _dio.post(
      endpoint,
      options: Options(headers: {'Authorization': 'Bearer $apiKey'}),
      data: {
        'model': model,
        'prompt': prompt,
        'size': size,
        'n': n,
        if (negativePrompt != null) 'negative_prompt': negativePrompt,
        if (steps != null) 'steps': steps,
        if (cfgScale != null) 'cfg_scale': cfgScale,
        if (sampler != null) 'sampler_name': sampler,
        if (seed != null) 'seed': seed,
      },
    );

    // OpenAI format: response.data[0].url or .b64_json
    // SD WebUI format: response.images (base64)
    final images = <Uint8List>[];
    final data = response.data;

    if (data is Map && data.containsKey('data')) {
      for (final item in data['data']) {
        if (item['b64_json'] != null) {
          images.add(base64Decode(item['b64_json']));
        } else if (item['url'] != null) {
          final imgResponse = await _dio.get(item['url'], options: Options(responseType: ResponseType.bytes));
          images.add(imgResponse.data);
        }
      }
    } else if (data is Map && data.containsKey('images')) {
      for (final b64 in data['images']) {
        images.add(base64Decode(b64));
      }
    }

    return GeneratedImage(images: images, prompt: prompt, revisedPrompt: data['data']?[0]?['revised_prompt']);
  }
}
```

### Step 7.2: Image generation config

```dart
@freezed
class ImageGenConfig with _$ImageGenConfig {
  const factory ImageGenConfig({
    required String id,
    @Default('') String name,
    @Default('openai') String provider,        // 'openai' | 'sd_webui' | 'custom'
    @Default('') String endpoint,
    @Default('') String apiKey,
    @Default('dall-e-3') String model,
    @Default('1024x1024') String size,
    @Default(1) int n,
    String? negativePrompt,
    @Default(30) int steps,
    @Default(7.0) double cfgScale,
    String? sampler,
  }) = _ImageGenConfig;
}
```

### Step 7.3: Gallery storage

```dart
// core/services/gallery_service.dart
class GalleryService {
  final ImageStorage _imageStorage;
  final CharacterRepo _charRepo;

  Future<GalleryEntry> saveGeneratedImage({
    required Uint8List imageBytes,
    required String characterId,
    required String prompt,
    String? revisedPrompt,
  }) async {
    final imgId = generateId();
    final path = await _imageStorage.saveBytes(imageBytes, 'gallery/$characterId', imgId, 'png');

    final entry = GalleryEntry(
      id: imgId,
      characterId: characterId,
      imagePath: path,
      prompt: prompt,
      revisedPrompt: revisedPrompt,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );

    // Append to character's gallery list
    // (stored as JSON array in CharacterCollection.galleryJson)
    return entry;
  }
}
```

### Step 7.4: Image generation UI in chat

- `/imagine` command or dedicated button in input bar
- Generation dialog: prompt field, config selector, size picker, generate button
- Inline preview: shows generated image in chat as assistant message with image attachment
- Option: "Set as character avatar" after generation

```dart
// features/chat/widgets/image_gen_dialog.dart
class ImageGenDialog extends ConsumerStatefulWidget {
  final String characterId;
  final String? initialPrompt;
  // ...
}

// Shows:
// 1. Prompt text field (pre-filled with scene description)
// 2. Provider/config dropdown
// 3. Size selector
// 4. Generate button → shows progress → displays result
// 5. "Send to chat" / "Save to gallery" / "Set as avatar" buttons
```

### Step 7.5: Gallery screen

```
┌─────────────────────────────┐
│ ← Character Gallery          │
│─────────────────────────────│
│ ┌────┐ ┌────┐ ┌────┐       │
│ │ 🖼 │ │ 🖼 │ │ 🖼 │       │
│ └────┘ └────┘ └────┘       │
│ ┌────┐ ┌────┐               │
│ │ 🖼 │ │ 🖼 │               │
│ └────┘ └────┘               │
│                             │
│ [+ Generate]                │
└─────────────────────────────┘
```

- GridView of generated images
- Tap image → full-screen view with prompt details
- Long-press → delete / set as avatar / send to chat
- FAB: open generation dialog

### Step 7.6: Character avatar from generation

- After generating an image, option to set it as the character's avatar
- Auto-resize/crop to square (1:1 aspect ratio)
- Save to `avatars/{charId}.png`, update Character.avatarPath

### Deliverables Phase 7
- [ ] Image generation service (OpenAI + SD WebUI formats)
- [ ] Image generation config CRUD
- [ ] Gallery storage + retrieval
- [ ] Image generation dialog in chat
- [ ] Inline image display in chat messages
- [ ] Gallery screen (grid view, full-screen, actions)
- [ ] "Set as avatar" from generated image
- [ ] Macro support in image prompts ({{char}}, {{description}}, etc.)

---

## Phase 8: Cloud Sync (Day 42–48)

### Step 8.1: Sync crypto

Port from JS `syncCrypto.js` (144 lines).

```dart
// core/services/sync/crypto.dart
class SyncCrypto {
  static Future<Uint8List> generateAesKey() async {
    // Use pointycastle or encrypt package
    // AES-256-GCM key generation
  }

  static Future<String> exportKey(Uint8List key) => base64Encode(key);

  static Future<Uint8List> importKey(String base64Key) => base64Decode(base64Key);

  static Future<EncryptedPayload> encrypt(Uint8List data, Uint8List key) async {
    // AES-256-GCM: generate 12-byte IV, encrypt, return {iv, data}
  }

  static Future<Uint8List> decrypt(EncryptedPayload payload, Uint8List key) async {
    // AES-256-GCM decrypt
  }

  static Future<String> computeHash(Uint8List data) async {
    // SHA-256 via crypto package
    return sha256.convert(data).toString();
  }
}
```

JS uses `crypto.subtle` (Web Crypto API). Dart equivalent: `package:encrypt` for AES-GCM, `package:crypto` for SHA-256.

### Step 8.2: Cloud adapter interface

```dart
// core/services/sync/cloud_adapter.dart
abstract class CloudAdapter {
  Future<void> connect();
  Future<void> disconnect();
  Future<bool> isConnected();
  Future<void> ensureFolder(String path);
  Future<List<CloudEntry>> listFolder(String path);
  Future<void> upload(String path, String data);
  Future<void> uploadBinary(String path, Uint8List data);
  Future<String?> download(String path);
  Future<Uint8List?> downloadBinary(String path);
  Future<void> deleteFile(String path);
  Future<void> deleteFolder(String path);
  Future<AccountInfo?> getAccountInfo();
}
```

### Step 8.3: Dropbox adapter

Port from JS `dropboxAdapter.js` (356 lines) + `dropboxAuth.js`.

```dart
// core/services/sync/dropbox_adapter.dart
class DropboxAdapter implements CloudAdapter {
  final Dio _dio = Dio();

  // OAuth: use flutter_web_auth_2 for auth code flow
  Future<void> connect() async {
    // 1. Open browser to Dropbox auth URL
    // 2. Receive redirect with auth code
    // 3. Exchange code for access token
    // 4. Store token securely (flutter_secure_storage)
  }

  // Upload: POST to https://content.dropboxapi.com/2/files/upload
  // Download: POST to https://api.dropboxapi.com/2/files/download
  // List: POST to https://api.dropboxapi.com/2/files/list_folder
  // Delete: POST to https://api.dropboxapi.com/2/files/delete_v2
  // Token refresh: POST to https://api.dropboxapi.com/oauth2/token
}
```

### Step 8.4: Google Drive adapter

Port from JS `gdriveAdapter.js` + `gdriveAuth.js` + `gdriveFolders.js` + `gdriveFiles.js`.

```dart
// core/services/sync/gdrive_adapter.dart
class GDriveAdapter implements CloudAdapter {
  // OAuth: use google_sign_in package
  // Upload: PATCH https://www.googleapis.com/upload/drive/v3/files/{id}
  // Download: GET https://www.googleapis.com/drive/v3/files/{id}?alt=media
  // List: GET https://www.googleapis.com/drive/v3/files
  // Delete: DELETE https://www.googleapis.com/drive/v3/files/{id}
}
```

### Step 8.5: Sync manifest

Port from JS `syncManifest.js` (277 lines).

```dart
class SyncManifest {
  Future<ManifestV2> buildLocalManifest() async {
    // 1. Read all characters, compute hash for each
    // 2. Read all personas, compute hash
    // 3. Read all chats, compute hash
    // 4. Read lorebooks, presets, theme state → singleton entries
    // 5. Return ManifestV2 with entries
  }

  Future<ManifestV2?> readCloudManifest(CloudAdapter adapter) async {
    final data = await adapter.download('/Glaze/manifest.json');
    if (data == null) return null;
    return ManifestV2.fromJson(jsonDecode(data));
  }

  Future<void> writeLocalManifest(ManifestV2 manifest) async {
    // Store manifest in Isar keyvalue collection
  }
}
```

### Step 8.6: Sync engine

Port from JS `syncEngine.js` (453 lines).

```dart
class SyncEngine {
  final CloudAdapter adapter;
  final SyncCrypto crypto;
  final SyncManifest manifest;

  Future<PushResult> pushEntities({Uint8List? key, void Function(String)? onProgress}) async {
    final local = await manifest.buildLocalManifest();
    final cloud = await manifest.readCloudManifest(adapter);

    var pushed = 0, skipped = 0;
    for (final entry in local.entries.values) {
      final cloudEntry = cloud?.entries[entry.key];
      if (cloudEntry != null && cloudEntry.hash == entry.hash) { skipped++; continue; }

      // Serialize entity
      final data = await _serializeEntity(entry);
      final payload = key != null ? await crypto.encrypt(data, key) : data;

      // Upload
      await adapter.upload(entry.path, jsonEncode(payload));
      pushed++;
    }

    // Upload manifest
    await adapter.upload('/Glaze/manifest.json', jsonEncode(local.toJson()));
    return PushResult(pushed: pushed, skipped: skipped);
  }

  Future<PullResult> pullEntities({Uint8List? key, void Function(String)? onProgress, void Function(Conflict)? onConflict}) async {
    // 1. Read cloud manifest
    // 2. Build local manifest
    // 3. For each cloud entry newer than local:
    //    a. If local is newer → create conflict
    //    b. If cloud is newer → download, decrypt, apply to local DB
    // 4. Return results
  }
}
```

### Step 8.7: Sync UI

- Sync settings screen: choose provider, connect/disconnect
- Sync status indicator in app bar
- Conflict resolution dialog
- Progress bar during sync

### Deliverables Phase 8
- [ ] Sync crypto (AES-256-GCM, SHA-256)
- [ ] Cloud adapter interface
- [ ] Dropbox adapter (OAuth + file operations)
- [ ] Google Drive adapter (OAuth + file operations)
- [ ] Sync manifest build/read/write
- [ ] Push entities flow
- [ ] Pull entities flow
- [ ] Conflict detection + resolution
- [ ] Gallery image sync
- [ ] Encryption support
- [ ] Sync UI (settings, progress, conflicts)

---

## Phase 9: Theme System + Polish (Day 49–54)

### Step 9.1: Theme engine

Port from JS `themeState.js` (639 lines).

```dart
class AppThemeState {
  String accentColor;
  double bgOpacity;
  double bgBlur;
  double elementOpacity;
  double elementBlur;
  String? uiColor;
  String? customFontName;
  String? activePresetId;
  String chatLayout;
  String? userBubbleColor;
  String? charBubbleColor;
  double uiFontSize;
  double chatFontSize;
  // ... (all fields from JS ThemeState)
}
```

### Step 9.2: Theme persistence

- Save/load theme as Isar keyvalue
- Theme presets (import/export)
- Real-time theme preview

### Step 9.3: Swipe support

- Swipe left/right on assistant message to see alternatives
- Store swipes array on ChatMessage
- SwipeId tracks current active swipe

### Step 9.4: Branching

- Fork chat at any message
- Each branch = separate session with shared history up to fork point

### Step 9.5: Search

- Search across character names, descriptions
- Search within chat messages

### Step 9.6: Onboarding

- First-run: welcome screen, API setup, import character
- Check for existing Glaze JS data → offer migration

### Step 9.7: Crash recovery

Port from JS `db.js` crash recovery logic:
- Before generation: save state to Isar
- After generation: clear recovery state
- On app start: check for orphaned recovery state → offer resume

### Step 9.8: iOS keyboard handling

- `SafeArea` for keyboard avoidance
- `MediaQuery.viewInsets` for input bar positioning
- No WKWebView keyboard bugs

### Step 9.9: Notifications

- Background generation notification (local notification)
- Generation complete sound

### Step 9.10: App icons + splash

- iOS: AppIcon assets
- Android: launcher icons
- Windows: app icon
- Splash screen with Glaze branding

### Deliverables Phase 8
- [x] Full theme system with presets
- [x] Swipe for alternative responses
- [x] Chat branching
- [x] Search across characters/chats
- [x] Onboarding flow
- [x] Crash recovery
- [ ] iOS keyboard handling
- [ ] Local notifications
- [ ] App icons + splash screens

---

## Phase 10: CI/CD + Release (Day 55–57)

### Step 10.1: CI pipeline

```yaml
# .github/workflows/build.yml
name: Build
on: push
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
      - run: flutter test

  build-android:
    runs-on: ubuntu-latest
    needs: test
    steps:
      - run: flutter build apk --release

  build-ios:
    runs-on: macos-latest
    needs: test
    steps:
      - run: flutter build ios --release

  build-windows:
    runs-on: windows-latest
    needs: test
    steps:
      - run: flutter build windows --release
```

### Step 10.2: Release automation

- Tag-based releases
- APK + MSI + IPA uploaded to GitHub Releases
- Changelog generated from commit messages

### Step 10.3: Code signing

- iOS: Apple Developer certificate
- Android: signing key
- Windows: code signing certificate (optional)

### Deliverables Phase 10
- [ ] GitHub Actions CI for all 3 platforms
- [ ] Automated test run on every push
- [ ] Release builds on tags
- [ ] Code signing configured

---

## What's NOT in this plan (future work)

| Feature | Reason | When |
|---------|--------|------|
| Extensions/JS plugins | Need embedded JS engine (flutter_js) | Phase 11 |
| Memory books | Can use lorebooks as workaround for now | Phase 11 |
| Group chats | Complex UI + routing logic | Phase 12 |
| Catalog browsing | Needs backend server | Phase 13 |
| PWA/web version | Flutter Web is possible but not priority | Phase 13 |
| Tokenizer (real) | Current heuristic (len/3.35) works for MVP | Phase 11 |

---

## JS → Dart mapping reference

| JS Concept | Dart Equivalent |
|-----------|----------------|
| `ref()` / `reactive()` | `StateNotifier` / `ChangeNotifier` / Riverpod |
| `computed()` | `Provider` with selector |
| `postMessage` (Worker) | `compute()` / `Isolate.spawn()` |
| `IndexedDB` | `Isar` |
| `localStorage` | `SharedPreferences` |
| `fetch()` / `XHR` | `Dio` |
| `EventTarget` / `window` | `StreamController` / `EventHub` |
| `FileReader` | `File.readAsBytes()` |
| `JSZip` | `archive` package |
| `crypto.subtle` | `encrypt` + `crypto` packages |
| `DataView` | `ByteData.view()` |
| `Uint8Array` | `Uint8List` |
| `TextDecoder` | `utf8.decode()` |
| `atob()` / `btoa()` | `base64Decode()` / `base64Encode()` |
| `canvas.toDataURL()` | `image` package |
| `Notification` API | `flutter_local_notifications` |
| `CapacitorHttp` | `dart:io` `HttpClient` |
| `globalThis` | Riverpod providers (scoped) |

---

## Risk mitigation

| Risk | Mitigation |
|------|-----------|
| Rust-speed tokenizer not available | Use heuristic (len/3.35) for MVP, add real tokenizer later |
| iOS background execution limits | Generation only in foreground, notification on complete |
| Isar DB corruption | Crash recovery + backup system already designed |
| Large chat history (10k+ messages) | Lazy loading in CustomScrollView, Isar pagination |
| PNG export complexity | Start with JSON-only export, add PNG in Phase 6 |
| OAuth flow differences per platform | flutter_web_auth_2 + flutter_secure_storage |
