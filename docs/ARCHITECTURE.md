# Architecture — Glaze Flutter

Related docs:
- Generation invariants (formal, with code refs): `docs/INVARIANTS.md`
- Generation lifecycle rules: `docs/rules/generation.md`
- Race condition rules: `docs/rules/race-conditions.md`
- Database rules: `docs/rules/database.md`

---

## 0. Architecture Overview

### Target Layer Order (dependency direction ↓)

```
UI (screens/widgets)
  → Providers (Riverpod AsyncNotifier / StateNotifier)
    → Services / Components (orchestrators and specialists)
      → Models (Freezed data classes)
      → Repos (Drift DB abstraction)
```

A layer may only import from its own level or below. Never upward.
UI → Providers → Services → Repos/Models. No circular imports.

### Key Rules

- **One class = one job.** If the class name needs "and", it is two classes.
- **Thin orchestrators, fat specialists.** Top-level service only calls specialists in order — zero business logic itself.
- **Constructor injection only.** Deps passed in, not looked up (except Riverpod `ref` at provider build time).
- **No raw DB writes outside repos.** All Drift access goes through a repo class.
- **Every sub-screen has a back button.** Use `leading: BackButton(onPressed: () => context.go('/parent'))` in AppBar because GoRouter `go()` replaces the stack.

---

## 0.1 Directory Tree

```
lib/
├── core/
│   ├── constants/
│   │   └── image_gen_patterns.dart     # IMG-tag regex constants
│   ├── db/
│   │   ├── app_db.dart                 # AppDatabase singleton (9 tables, migrations v1–19)
│   │   ├── tables.dart                 # Drift table class definitions
│   │   └── repositories/              # One repo per table (CRUD only)
│   │       ├── api_config_repo.dart
│   │       ├── character_repo.dart
│   │       ├── chat_repo.dart
│   │       ├── embedding_repo.dart
│   │       ├── lorebook_repo.dart
│   │       ├── memory_book_repo.dart
│   │       ├── persona_repo.dart
│   │       ├── preset_repo.dart
│   │       └── summary_repo.dart
│   ├── models/                       # Freezed data classes (pure data, no logic)
│   │   ├── api_config.dart
│   │   ├── character.dart
│   │   ├── chat_message.dart
│   │   ├── gallery_entry.dart
│   │   ├── lorebook.dart
│   │   ├── memory_book.dart
│   │   ├── persona.dart
│   │   └── preset.dart
│   ├── llm/                          # LLM pipeline specialists
│   │   ├── prompt_builder.dart        # Orchestrator: block ordering, lorebook merge, trimming
│   │   ├── prompt_block_resolver.dart # Maps preset block ID → resolved text
│   │   ├── prompt_payload_builder.dart # Riverpod-aware: assembles PromptPayload from state
│   │   ├── prompt_isolate.dart        # Runs buildPrompt() in a Dart isolate
│   │   ├── history_assembler.dart     # ChatMessage[] → PromptMessage[], macro application
│   │   ├── context_calculator.dart    # Token budget: trims history from oldest end
│   │   ├── fallback_prompt_builder.dart # Minimal prompt when no preset configured
│   │   ├── lorebook_scanner.dart      # Keyword scan: sticky/cooldown/probability/recursion
│   │   ├── lorebook_merger.dart       # Merges keyword + vector results, deduplicates
│   │   ├── lorebook_providers.dart    # Riverpod providers for vector search/embedding
│   │   ├── lorebook_coverage.dart     # Diagnostic: full coverage report per entry/key
│   │   ├── lorebook_vector_search.dart # Cosine search + hybrid boost
│   │   ├── lorebook_embedding_service.dart # Indexes lorebook entries into embedding store
│   │   ├── retrieval_hints.dart       # Retrieval hint extraction from lorebook entries
│   │   ├── embedding_service.dart     # Calls embedding API, handles chunking + rate limits
│   │   ├── embedding_types.dart       # Shared embedding type definitions
│   │   ├── embedding_error_labels.dart # Error classification for embedding status
│   │   ├── memory_embedding_service.dart   # Indexes memory entries into embedding store
│   │   ├── memory_injection_service.dart   # Scores + selects memory entries for injection
│   │   ├── glaze_matcher.dart         # Pure regex keyword matching (3 whole-word modes)
│   │   ├── regex_service.dart         # Applies PresetRegex scripts to a string
│   │   ├── sse_client.dart           # SSE + non-streaming completions via Dio
│   │   ├── stream_accumulator.dart   # Parses inline <think…> tags from stream
│   │   ├── response_normalizer.dart  # Extracts content from non-streaming response body
│   │   ├── summary_service.dart      # Reads/writes summaries, triggers LLM regeneration
│   │   ├── tokenizer.dart            # estimateTokens() with LRU cache, base64 stripping
│   │   ├── macro_engine.dart         # SillyTavern-compatible macro replacement engine
│   │   └── vector_math.dart          # cosineSimilarity, findTopK, findTopKMulti, BLOB helpers
│   ├── services/                     # Business logic services (no UI, no Riverpod ref)
│   │   ├── character_importer.dart   # Parses PNG/JSON/YAML V1/V2 character cards
│   │   ├── character_exporter.dart   # Exports character to PNG (tEXt chunk) or JSON
│   │   ├── character_book_converter.dart # character_book JSON ↔ Lorebook model
│   │   ├── image_storage_service.dart    # Avatars + thumbnails on disk
│   │   ├── gallery_service.dart          # Per-character image gallery CRUD
│   │   ├── backup_service.dart           # Top-level backup orchestrator (thin)
│   │   ├── backup/
│   │   │   ├── backup_exporter.dart      # Serializes to Glaze-native ZIP
│   │   │   ├── backup_helpers.dart       # ZIP read/write, JSON helpers
│   │   │   ├── flutter_backup_importer.dart  # Imports Glaze-native backup
│   │   │   ├── js_backup_importer.dart       # Imports SillyTavern ZIP (orchestrator)
│   │   │   ├── js_character_importer.dart    # Imports ST character PNG/JSON files
│   │   │   ├── js_chat_importer.dart         # Imports ST JSONL chat files
│   │   │   ├── js_api_config_importer.dart   # Parses ST settings → ApiConfig
│   │   │   ├── js_preset_importer.dart       # Imports ST preset JSON files
│   │   │   ├── js_preset_mapper.dart         # Maps ST preset fields → Glaze Preset
│   │   │   ├── js_lorebook_importer.dart     # Imports ST lorebook JSON files
│   │   │   ├── js_lorebook_mapper.dart       # Maps ST lorebook fields → Glaze Lorebook
│   │   │   ├── js_memory_importer.dart       # Imports ST memory book data
│   │   │   ├── js_message_normalizer.dart    # Normalizes ST message format
│   │   │   ├── profile_resolver.dart         # Resolves ST service profiles → API configs
│   │   │   ├── authors_note_helper.dart      # Authors note extraction from ST data
│   │   │   ├── data_url_helpers.dart         # Data URL parsing/encoding
│   │   │   ├── type_converters.dart          # ST→Glaze type conversions
│   │   │   └── service_prefs_writer.dart     # Writes imported prefs to SharedPreferences
│   │   ├── migration_service.dart    # Migrates legacy Glaze-JS data to Drift DB
│   │   ├── preset_defaults.dart      # Ensures mandatory blocks exist in imported presets
│   │   ├── preset_seeder.dart        # Seeds built-in "Glaze Default" preset on first launch
│   │   ├── png_text_extractor.dart   # Reads tEXt chunks from PNG byte stream
│   │   ├── chat_import_export.dart   # Import/export individual chat sessions as JSONL
│   │   ├── file_export_service.dart  # Platform-aware file export (file_selector / share)
│   │   ├── deep_link_service.dart    # Listens for OAuth deep-link URIs
│   │   ├── generation_notification_service.dart # Android foreground/background notifications
│   │   ├── memory_prompt_presets.dart           # Built-in memory prompt templates
│   │   └── onboarding_service.dart   # Completion check logic only (UI in features/onboarding/)
│   ├── import/
│   │   ├── silly_tavern_preset_parser.dart  # ST preset JSON → Glaze Preset (pure)
│   │   └── st_lorebook_importer.dart        # ST lorebook JSON → Glaze Lorebook (pure)
│   ├── utils/
│   │   ├── cast_helpers.dart         # computeHash, dataUrlToBytes, toStringList
│   │   ├── id_generator.dart         # generateId(): base-36 milliseconds
│   │   ├── platform_paths.dart       # getAppDataDir() per platform
│   │   ├── sync_deletion_tracker.dart # Appends deletion tombstones for cloud sync
│   │   ├── time_helpers.dart         # currentTimestampSeconds()
│   │   └── html_to_markdown.dart     # HTML → Markdown converter (ST card fields)
│   ├── events/
│   │   └── event_hub.dart            # Lightweight pub/sub bus (broadcast StreamControllers)
│   └── state/                        # Global Riverpod providers
│       ├── db_provider.dart          # AppDatabase + all repo providers
│       ├── shared_prefs_provider.dart # SharedPreferences FutureProvider
│       ├── active_selection_provider.dart # Active preset/persona/globalVars/regexes
│       ├── character_provider.dart   # CharactersNotifier (watchAll reactive stream)
│       ├── lorebook_provider.dart    # LorebooksNotifier + settings/activations
│       ├── global_regex_provider.dart # GlobalRegexNotifier
│       └── memory_settings_provider.dart # MemoryGlobalSettings + notifier
├── features/
│   ├── chat/
│   │   ├── chat_provider.dart        # ChatNotifier: full ChatState lifecycle per charId
│   │   ├── chat_state.dart           # ChatState + StreamingState value objects
│   │   ├── editing_message_provider.dart # Tracks which message is being edited
│   │   ├── chat_screen.dart          # UI: WebView + ChatInputBar + header
│   │   ├── chat_generation_service.dart  # Orchestrates one generation cycle (SSE stream)
│   │   ├── chat_session_service.dart     # Creates/finds sessions, alternate greetings
│   │   ├── chat_message_service.dart     # Message-level mutations (edit/delete/hide/reorder)
│   │   ├── chat_actions_service.dart     # Branch/clear/rename/delete session
│   │   ├── initial_message_builder.dart  # Selects greeting, runs macros, returns first msg
│   │   ├── memory_draft_generator.dart   # LLM-based memory auto-generation
│   │   ├── bridge/                       # WebView ↔ Flutter bridge
│   │   │   ├── chat_bridge_controller.dart  # Dart-side bridge methods
│   │   │   ├── chat_message_mapper.dart     # ChatMessage → JS map conversion
│   │   │   └── chat_webview_keep_alive.dart # Keep-alive key provider
│   │   └── widgets/                      # Chat UI widgets
│   ├── chat_history/
│   │   ├── chat_history_provider.dart    # All sessions across all characters
│   │   └── chat_history_screen.dart      # Root/home screen
│   ├── settings/
│   │   ├── api_list_provider.dart        # ApiListNotifier + activeApiConfigProvider
│   │   ├── app_settings_provider.dart    # App-level preferences
│   │   ├── api_settings_screen.dart
│   │   ├── api_editor_screen.dart
│   │   ├── app_settings_screen.dart
│   │   ├── theme_editor_screen.dart
│   │   ├── theme_preset_screen.dart
│   │   ├── theme_preview.dart
│   │   └── widgets/
│   ├── lorebooks/                    # Lorebook UI screens + widgets
│   ├── presets/                      # Preset UI screens + widgets
│   ├── personas/                     # Persona UI screens + provider
│   ├── backup/                       # Backup UI screen + provider
│   ├── catalog/                      # Character discovery: UI + provider + API services
│   ├── character_list/               # Character list/detail/editor screens + widgets
│   ├── character_gallery/            # Gallery screen + provider
│   ├── regex/                        # Global regex list screen
│   ├── cloud_sync/                   # Cloud sync UI, provider, services (Dropbox/GDrive)
│   ├── image_gen/                    # Image generation UI, provider, services
│   ├── onboarding/                   # First-run onboarding screen
│   ├── picks/                        # Featured picks grid + detail launcher
│   ├── tools/                        # Developer tools screen (tokenizer, coverage, etc.)
│   └── menu/                         # Sidebar menu + About overlay
├── shared/
│   ├── shell/
│   │   ├── shell_screen.dart         # Bottom nav shell (GoRouter StatefulNavigationShell)
│   │   └── nav_height_provider.dart  # navHeightProvider: nav bar height for layout
│   ├── theme/
│   │   ├── theme_preset.dart         # Freezed ThemePreset model
│   │   ├── theme_preset_storage.dart # ThemePresetStorage: load/save/import presets
│   │   ├── theme_provider.dart       # ThemeNotifier: loads + applies ThemeData
│   │   ├── theme_font_provider.dart  # ThemeFontNotifier: loads Google Fonts dynamically
│   │   ├── app_colors.dart           # Color palette + fromPreset() factory
│   │   └── app_theme.dart            # AppTheme builder: ColorScheme from preset
│   └── widgets/                      # Reusable UI primitives
│       ├── glaze_bottom_sheet.dart   # Primary bottom sheet (snap points, glassmorphic)
│       ├── sheet_view.dart           # SheetView: sheet-aware scaffold with header
│       ├── colored_markdown.dart     # Custom InlineMd/BlockMd classes for markers
│       └── ...
├── app.dart                          # GlazeApp: GoRouter config + boot-time init
└── main.dart                         # Entry point: orientation lock, services init
```

---

## 1. Generation Pipeline

### Files (in call order)

| Step | File | Role |
|------|------|------|
| 1 | `chat_provider.dart` | Owns `ChatState`, calls `ChatGenerationService.generate()` |
| 2 | `chat_generation_service.dart` | Orchestrates: builds payload → isolate → SSE stream |
| 3 | `prompt_payload_builder.dart` | Reads all Riverpod state, assembles `PromptPayload` |
| 4 | `prompt_builder.dart` | Builds ordered prompt blocks from payload |
| 5 | `prompt_block_resolver.dart` | Resolves each block ID → text via character fields |
| 6 | `lorebook_scanner.dart` | Keyword scan of lorebook entries against chat history |
| 7 | `lorebook_vector_search.dart` | Vector semantic search (runs in PromptPayloadBuilder before isolate) |
| 8 | `lorebook_merger.dart` | Merges keyword + vector results, deduplicates |
| 9 | `memory_injection_service.dart` | Scores memory entries, injects top-N |
| 10 | `history_assembler.dart` | Assembles chat history blocks with depth inserts |
| 11 | `context_calculator.dart` | Trims history from oldest end to fit token budget |
| 12 | `regex_service.dart` | Applies regex scripts to each prompt block |
| 13 | `macro_engine.dart` | Expands all `{{macro}}` tokens |
| 14 | `prompt_isolate.dart` | Runs prompt build off the UI thread |
| 15 | `sse_client.dart` | Sends request, streams SSE deltas back |
| 16 | `stream_accumulator.dart` | Splits text from inline `<think…>` reasoning |
| 17 | `response_normalizer.dart` | Extracts final content (non-streaming path) |

### Request Types

| Type | State owner | Streaming | Abort |
|------|-------------|-----------|-------|
| Chat | `ChatState.isGenerating` per `charId` | Yes (SSE) | `CancelToken` + `_activeGenId` in `ChatNotifier` |
| Image gen | `ChatState.isGeneratingImage` + `_imgGenCancelToken` | No (one-shot LLM) | `_imgGenCancelToken` in `ChatNotifier` |
| Summary | Widget-local `_isGenerating` in `summary_sheet.dart` | No | Widget-scoped `CancelToken` |
| Memory draft | Widget-local `_generatingDrafts` in `memory_books_sheet.dart` | No | Per-draft `CancelToken` in `_cancelTokens` map |

### Prompt Ordering (invariant — do not reorder)

1. Vector lorebook scan (async, in `PromptPayloadBuilder`, before isolate)
2. Keyword lorebook scan (synchronous in `PromptBuilder`, inside isolate)
3. Merge: keyword + vector, deduplicate vector against keyword
4. Memory injection
5. Context cutoff — trims oldest messages first

---

## 2. Macro Engine

**File:** `lib/core/llm/macro_engine.dart`

### Supported Macros

**Character/User:**
- `{{char}}` — character name
- `{{user}}` — user/persona name
- `{{description}}`, `{{personality}}`, `{{scenario}}`, `{{mesExamples}}` — character card fields
- `{{persona}}` — user persona prompt

**Variables (SillyTavern-compatible):**
- `{{setvar::name::value}}` — session variable (per `charId+sessionId`, stored in `MacroContext.sessionVars`)
- `{{getvar::name}}` — get session variable
- `{{setglobalvar::name::value}}` — global variable (cross-session, `globalVarsProvider`)
- `{{getglobalvar::name}}` — get global variable

**Utility:**
- `{{random::a::b::c}}` — random choice
- `{{pick::a::b::c}}` — deterministic pick (hash-stable per session)
- `{{roll::1d20}}` — dice roll
- `{{trim}}` — trim whitespace
- `{{date}}`, `{{time}}`, `{{weekday}}`

**Reasoning:**
- `{{reasoningPrefix}}`, `{{reasoningSuffix}}` — inline reasoning tag config

**Dynamic content:**
- `{{summary}}` — current chat summary
- `{{lorebooks}}` — triggered lorebook content
- `{{guidance}}` — guided swipe instruction

**Comments:**
- `{{// comment}}` — single-line comment (removed)
- `{{ // }}...{{ /// }}` — multi-line scoped comment (removed)

**Escaping:** `\{\{` → `{{`, `\}\}` → `}}`

### Resolution Order (fixed, matches code)

1. Comment stripping
2. Static character macros
3. `{{reasoningPrefix}}` / `{{reasoningSuffix}}`
4. `{{summary}}` / `{{lorebooks}}` / `{{guidance}}`
5. Trim
6. Session variable macros (`setvar`/`getvar`)
7. Global variable macros (`setglobalvar`/`getglobalvar`)
8. Custom named macros
9. `{{random::}}` / `{{pick::}}`
10. Dice `{{roll::}}`
11. Date/Time
12. Escape handling

---

## 3. Lorebook System

### Files
- `lorebook_scanner.dart` — keyword scan: sticky/cooldown/probability/character-filter/recursion
- `lorebook_merger.dart` — merges keyword + vector results, deduplicates by entry ID
- `lorebook_providers.dart` — Riverpod providers for vector search and embedding
- `lorebook_coverage.dart` — diagnostic full coverage report
- `lorebook_vector_search.dart` — cosine similarity, hybrid boost (name/key/hint overlap)
- `lorebook_embedding_service.dart` — indexes lorebook entries (hash-based dirty check)
- `retrieval_hints.dart` — extracts retrieval hints from lorebook entries
- `embedding_service.dart` — calls embedding API, auto-chunking, rate-limit handling
- `embedding_types.dart` — shared embedding type definitions
- `embedding_error_labels.dart` — error classification for embedding status UI
- `vector_math.dart` — `cosineSimilarity`, `findTopK`, `findTopKMulti` (MaxSim)
- `lorebook_provider.dart` — CRUD + activations + settings (SharedPreferences)

### Search Type System
- `searchType`: `'keys'` | `'vector'` | `'both'`
- `'keys'` — keyword-only (default)
- `'vector'` — vector-only semantic search
- `'both'` — combined (keyword results deduplicated from vector budget)

### Recursive Scan Bounds
- Max iterations: 5 when `recursiveScan == true`, else 1
- Prevents infinite loops from circular lorebook references

---

## 4. Memory Books

### Files
- `memory_draft_generator.dart` — LLM-based draft generation, batching, progress
- `memory_injection_service.dart` — scoring (keyword + vector), top-N selection, injection
- `memory_embedding_service.dart` — indexes/reindexes memory entries
- `memory_book_repo.dart` — DB persistence for `MemoryBook` rows
- `core/state/memory_settings_provider.dart` — global settings (SharedPreferences)

### Data Model (key fields)
```dart
MemoryBook {
  entries: List<MemoryEntry>
  pendingDrafts: List<MemoryDraft>
  settings: MemoryBookSettings
}

MemoryEntry {
  id, content, keys, glazeKeys
  vectorSearch: bool
  messageIds: List<String>
  messageRange: { start, end }
  status: 'active' | 'needs_rebuild' | 'stale'
  source: 'manual' | 'auto'
}

MemoryDraft {
  id, title, messageIds, messageRange
  generationStatus: 'pending' | 'generating' | 'completed' | 'failed'
}
```

### Injection Rule
Memory entries are injected only when all linked `messageIds` are already **outside** the active context window. This prevents double-coverage.

---

## 5. Database Layer

**File:** `lib/core/db/app_db.dart` + `lib/core/db/repositories/`

### Tables (9 total, schema v19)
| Table | Repo | Notes |
|-------|------|-------|
| `Characters` | `character_repo.dart` | watchAll() reactive stream; v18: `picksHash`, v19: `createdAt` |
| `ChatSessions` | `chat_repo.dart` | Largest repo (~210 lines) |
| `Presets` | `preset_repo.dart` | JSON blob per preset |
| `ApiConfigs` | `api_config_repo.dart` | |
| `Personas` | `persona_repo.dart` | |
| `Lorebooks` | `lorebook_repo.dart` | entries + settings as JSON |
| `Embeddings` | `embedding_repo.dart` | `entryId`, `vectorsBlob`, `retrievalHintsJson`, `errorJson` |
| `ChatSummaries` | `summary_repo.dart` | one per session |
| `MemoryBookRows` | `memory_book_repo.dart` | DriftAccessor |

### Write Rule
**Never** do `getChat → mutate → saveChat`. Use `patchChatData` to serialize reads.
See `docs/rules/database.md`.

---

## 6. Cloud Sync

### Files
- `sync_service.dart` — high-level orchestrator, lock management
- `sync_engine.dart` — manifest diff, upload/download, conflict detection
- `sync_manifest.dart` — reads/writes cloud JSON manifest (ETags + timestamps)
- `sync_serialization.dart` — entity → JSON envelope
- `sync_conflict.dart` — winner = newer `updatedAt`
- `sync_queue.dart` — serial queue preventing duplicate uploads
- `sync_config.dart` — sync configuration model
- `sync_models.dart` — sync data models
- `sync_provider.dart` — Riverpod provider for sync state
- `sync_repo_interfaces.dart` — Abstract repo interfaces for sync
- `cloud_adapter.dart` — Abstract adapter interface for cloud providers
- `dropbox/dropbox_adapter.dart` + `dropbox_auth.dart` — OAuth2 PKCE + API v2
- `gdrive/gdrive_adapter.dart` + `gdrive_auth.dart` + `gdrive_files.dart` + `gdrive_folders.dart`
- `oauth_local_server.dart` — desktop OAuth loopback (local HTTP server)
- `deep_link_service.dart` — mobile OAuth deep-link receiver
- `widgets/sync_sheet.dart` — Sync UI sheet

### What Is Synced
Characters, sessions, presets, API configs, personas, lorebooks, theme presets, active preset, selected app settings. **Not synced:** generation state, UI state, embedding vectors, debug traces.

---

## 7. Theme System

### Files
- `shared/theme/theme_preset.dart` — Freezed `ThemePreset` model
- `shared/theme/theme_preset_storage.dart` — `ThemePresetStorage`: load/save/import presets (SharedPreferences)
- `shared/theme/theme_provider.dart` — `ThemeNotifier`: loads active preset, generates `ThemeData`
- `shared/theme/theme_font_provider.dart` — `ThemeFontNotifier`: loads Google Fonts async at startup
- `shared/theme/app_colors.dart` — `AppColors.fromPreset()`: all palette slots with defaults
- `shared/theme/app_theme.dart` — `AppTheme` builder: generates `ThemeData` + `ColorScheme` from preset

### `updatePreset(ThemePreset preset)` flow
1. `ThemeNotifier.updatePreset()` → saves to `ThemePresetStorage`
2. Rebuilds `ThemeData` from new preset
3. `ThemeFontNotifier` detects font change → reloads font family

---

## 8. Image Generation

### Files
- `image_gen_service.dart` — orchestrates: dispatches to provider adapters, saves images
- `image_gen_provider.dart` — manages settings + generation state
- `image_gen_models.dart` — Freezed data models for image generation
- `image_gen_http.dart` — HTTP client for image generation APIs
- Provider adapters: `routmy_image_provider.dart`, `openai_image_provider.dart`, `gemini_image_provider.dart`, `naistera_image_provider.dart`
- UI: `widgets/image_gen_sheet.dart`, `widgets/image_content_renderer.dart`

---

## 9. Known Design Issues

Issues tracked for refactor:

1. **`onboarding_service.dart`** — partially fixed: UI extracted to `features/onboarding/onboarding_screen.dart`. Remaining issue: service still imports `package:flutter/material.dart` for `BuildContext` and calls `rootNavigatorKey.currentState.push()`.

2. **`magic_drawer_stats_service.dart`** (~236 lines) — named "service" but lives in `features/chat/widgets/`. Move to `features/chat/` (provider or service level).

3. **`prompt_payload_builder.dart`** (~240 lines) — reads 7+ Riverpod providers directly. Becoming a God object. Split: pure `PromptInputsCollector` (reads providers) + pure `PromptPayloadAssembler` (builds payload from collected inputs, no Riverpod dep).

4. **`chat_provider.dart`** (~1000 lines) — `ChatNotifier` does generate + swipe + edit + delete + branch + clear + image gen + continue. Split responsibilities across dedicated notifiers or move action logic to services, leaving notifier as thin state owner.

5. ~~**`lorebook_vector_search.dart`** — contained Riverpod provider declarations mixed with service logic.~~ **Fixed** — providers extracted to `lorebook_providers.dart`.

6. **Mutual exclusion between chat generation and memory draft is not enforced.** Neither `ChatNotifier.sendMessage()` nor `memory_books_sheet.dart._generateDraft()` checks for the other's active state. See `docs/INVARIANTS.md` INV-M3/INV-M4.

7. **Session variable rollback on abort is not implemented.** `ChatNotifier.abortGeneration()` does not restore pre-generation `sessionVars`. See `docs/INVARIANTS.md` INV-C5.

8. **35% memory token budget guard is not implemented.** `MemoryInjectionService.buildInjection()` has no threshold check. Memory injection proceeds unconditionally. See `docs/INVARIANTS.md` INV-PS4.
