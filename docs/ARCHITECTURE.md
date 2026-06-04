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
│   │   ├── app_db.dart                 # AppDatabase singleton (11 tables, schema v21)
│   │   ├── tables.dart                 # Drift table class definitions
│   │   └── repositories/              # One repo per table (CRUD only)
│   │       ├── api_config_repo.dart
│   │       ├── character_repo.dart
│   │       ├── chat_repo.dart
│   │       ├── embedding_repo.dart
│   │       ├── extension_presets_repository.dart
│   │       ├── info_blocks_repository.dart
│   │       ├── lorebook_repo.dart
│   │       ├── memory_book_repo.dart
│   │       ├── persona_repo.dart
│   │       ├── preset_repo.dart
│   │       └── summary_repo.dart
│   ├── glossary/
│   │   ├── glossary_models.dart
│   │   └── glossary_provider.dart
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
│   │   ├── prompt_inputs.dart         # Freezed value object: inputs for isolate build
│   │   ├── prompt_inputs_collector.dart # Reads Riverpod state, assembles PromptInputs (no async work)
│   │   ├── prompt_payload_assembler.dart # Pure: PromptInputs → PromptPayload (no Riverpod)
│   │   ├── prompt_payload_builder.dart # Riverpod-aware: assembles PromptPayload (vector/memory async)
│   │   ├── prompt_isolate.dart        # Spawns isolate; delegates to prompt_worker
│   │   ├── prompt_worker.dart         # Top-level entry: buildPrompt() inside isolate
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
│   │   ├── memory_budget.dart         # INV-PS4 token cap for memory injection
│   │   ├── glaze_matcher.dart         # Pure regex keyword matching (3 whole-word modes)
│   │   ├── regex_service.dart         # Applies PresetRegex scripts to a string
│   │   ├── preset_macro_attribution.dart # Preset macro source attribution (debug)
│   │   ├── sse_client.dart           # SSE + non-streaming completions via Dio
│   │   ├── stream_accumulator.dart   # Parses inline <think…> tags from stream
│   │   ├── response_normalizer.dart  # Extracts content from non-streaming response body
│   │   ├── summary_service.dart      # Reads/writes summaries, triggers LLM regeneration
│   │   ├── tokenizer.dart            # estimateTokens() with LRU cache, base64 stripping
│   │   ├── macro_engine.dart         # SillyTavern-compatible macro replacement engine
│   │   └── vector_math.dart          # cosineSimilarity, findTopK, findTopKMulti, BLOB helpers
│   ├── navigation/
│   │   └── router.dart               # GoRouter routes + shell (used by app.dart)
│   ├── services/                     # Business logic services (no UI, no Riverpod ref)
│   │   ├── character_importer.dart   # Parses PNG/JSON/YAML V1/V2 character cards
│   │   ├── character_exporter.dart   # Exports character to PNG (tEXt chunk) or JSON
│   │   ├── character_book_converter.dart # character_book JSON ↔ Lorebook model
│   │   ├── image_storage_service.dart    # Avatars + thumbnails on disk
│   │   ├── gallery_service.dart          # Per-character image gallery CRUD
│   │   ├── api_connection_tester.dart    # API endpoint connectivity check
│   │   ├── backup_service.dart           # Top-level backup orchestrator (thin)
│   │   ├── backup/
│   │   │   ├── backup_exporter.dart      # Serializes to Glaze-native ZIP
│   │   │   ├── backup_helpers.dart       # ZIP read/write, JSON helpers
│   │   │   ├── backup_cancel.dart        # Cooperative cancel for long imports
│   │   │   ├── archive_stream.dart       # Streaming ZIP entry reader
│   │   │   ├── flutter_backup_importer.dart  # Imports Glaze-native backup
│   │   │   ├── js_backup_importer.dart       # Legacy ST ZIP import (orchestrator)
│   │   │   ├── st_backup_importer.dart       # SillyTavern ZIP import (orchestrator)
│   │   │   ├── tavo_backup_importer.dart     # Tavo/LMDB backup import
│   │   │   ├── tavo_lmdb_reader.dart         # LMDB reader for Tavo archives
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
│   │   └── onboarding_service.dart   # Completion check + showOnboarding (UI in features/onboarding/)
│   ├── import/
│   │   ├── silly_tavern_preset_parser.dart  # ST preset JSON → Glaze Preset (pure)
│   │   └── st_lorebook_importer.dart        # ST lorebook JSON → Glaze Lorebook (pure)
│   ├── utils/
│   │   ├── cast_helpers.dart         # computeHash, dataUrlToBytes, toStringList
│   │   ├── id_generator.dart         # generateId(): base-36 milliseconds
│   │   ├── platform_paths.dart       # getAppDataDir() per platform
│   │   ├── sync_deletion_tracker.dart # Appends deletion tombstones for cloud sync
│   │   ├── time_helpers.dart         # currentTimestampSeconds()
│   │   ├── think_tags.dart           # Reasoning tag parsing helpers
│   │   └── html_to_markdown.dart     # HTML → Markdown converter (ST card fields)
│   ├── events/
│   │   └── event_hub.dart            # Lightweight pub/sub bus (broadcast StreamControllers)
│   └── state/                        # Global Riverpod providers
│       ├── db_provider.dart          # AppDatabase + all repo providers
│       ├── shared_prefs_provider.dart # SharedPreferences FutureProvider
│       ├── active_selection_provider.dart # Active preset/persona/globalVars/regexes
│       ├── active_regex_provider.dart     # Active regex scripts for prompt build
│       ├── character_provider.dart   # CharactersNotifier (watchAll reactive stream)
│       ├── lorebook_provider.dart    # LorebooksNotifier + settings/activations
│       ├── global_regex_provider.dart # GlobalRegexNotifier
│       ├── memory_settings_provider.dart # MemoryGlobalSettings + notifier
│       ├── memory_book_ops_provider.dart # Memory book CRUD helpers
│       ├── chat_session_ops_provider.dart # Cross-session ops (branch, delete, etc.)
│       ├── persona_resolution.dart   # Resolves active persona for a character
│       ├── preset_resolution.dart    # Resolves active preset for a character
│       └── dev_mode_provider.dart    # Developer mode flag
├── features/
│   ├── chat/
│   │   ├── chat_provider.dart        # ChatNotifier: state owner; delegates to controllers + pipeline
│   │   ├── chat_state.dart           # ChatState + StreamingState value objects
│   │   ├── editing_message_provider.dart # Tracks which message is being edited
│   │   ├── chat_screen.dart          # UI: WebView + ChatInputBar + header
│   │   ├── chat_drawer_controller.dart # Magic drawer open/close + layout state
│   │   ├── chat_generation_service.dart  # Thin facade: generate / processImageTags / processExtensions
│   │   ├── chat_session_service.dart     # Creates/finds sessions, alternate greetings
│   │   ├── chat_message_service.dart     # Message-level mutations (edit/delete/hide/reorder)
│   │   ├── chat_actions_service.dart     # Branch/clear/rename/delete session
│   │   ├── initial_message_builder.dart  # Selects greeting, runs macros, returns first msg
│   │   ├── memory_draft_generator.dart   # LLM-based memory auto-generation (called by controller)
│   │   ├── image_recovery_service.dart   # Recovers failed inline image gen results
│   │   ├── abort_handler.dart        # genId + cancel tokens + restoration snapshot
│   │   ├── controllers/              # Extracted ChatNotifier responsibilities
│   │   │   ├── chat_session_controller.dart
│   │   │   ├── chat_swipe_controller.dart
│   │   │   ├── chat_message_ops_controller.dart
│   │   │   ├── chat_message_selection_controller.dart
│   │   │   ├── chat_draft_controller.dart
│   │   │   └── chat_image_recovery_controller.dart
│   │   ├── services/
│   │   │   ├── generation_pipeline.dart  # Post-SSE: persist, rollback, image tags, extensions, sync
│   │   │   ├── saved_message_writer.dart # Pure builders for assistant/error/regen messages
│   │   │   ├── stream_generation_service.dart # SSE + prompt build + stream accumulate + save
│   │   │   ├── image_gen_processor.dart
│   │   │   ├── magic_drawer_layout_service.dart
│   │   │   └── magic_drawer_stats_service.dart
│   │   ├── bridge/                       # WebView ↔ Flutter bridge
│   │   │   ├── chat_bridge_controller.dart  # Host: shared state + iterates bridgeHandlers
│   │   │   ├── bridge_handlers.dart         # Single source of truth: 24 JS handler names
│   │   │   ├── bridge_message_commands.dart # set/append/update/remove messages, scroll
│   │   │   ├── bridge_theme_commands.dart   # applyTheme, fonts, background, performance
│   │   │   ├── bridge_identity_commands.dart # setIdentity, applyLayout, regex context
│   │   │   ├── bridge_layout_commands.dart  # padding, search, edit, selection, settings
│   │   │   ├── bridge_memory_commands.dart  # memory book data updates + state sets
│   │   │   ├── chat_message_mapper.dart     # ChatMessage → JS map conversion
│   │   │   ├── chat_webview_keep_alive.dart # Keep-alive key provider
│   │   │   └── chat_webview_settings.dart   # WebView performance/config flags
│   │   ├── models/
│   │   │   └── message_dto.dart
│   │   ├── state/
│   │   │   ├── chat_body_selectors.dart # batteryAware dual-read helper
│   │   │   ├── cached_token_breakdown.dart
│   │   │   └── token_breakdown_cache.dart
│   │   ├── utils/
│   │   │   └── message_preview.dart   # Notification preview text helper
│   │   └── widgets/                      # Chat UI widgets (sheets, header, webview, etc.)
│   ├── memory/
│   │   ├── controllers/
│   │   │   └── memory_book_controller.dart # Draft gen, cancel tokens, mutex with chat gen
│   │   └── state/
│   │       └── memory_active_drafts_provider.dart # SessionIds with active memory drafts
│   ├── extensions/                   # Info blocks + post-generation extension pipeline
│   │   ├── models/                     # extension_preset, info_block, block_config, settings
│   │   ├── providers/                  # extension_presets, info_blocks, extensions_settings
│   │   ├── screens/                    # extensions_screen, preset_editor_screen
│   │   ├── services/
│   │   │   ├── extension_post_gen_service.dart # Runs after assistant message saved
│   │   │   ├── info_block_service.dart
│   │   │   ├── info_block_injector.dart
│   │   │   └── image_block_service.dart
│   │   └── widgets/
│   ├── chat_history/
│   │   ├── chat_history_provider.dart    # All sessions across all characters
│   │   └── chat_history_screen.dart      # Root/home screen (shell tab `/`)
│   ├── settings/
│   │   ├── api_list_provider.dart        # ApiListNotifier + activeApiConfigProvider
│   │   ├── app_settings_provider.dart    # App-level preferences
│   │   └── ...                           # api/app/theme screens + widgets
│   ├── lorebooks/                    # Lorebook UI screens + widgets
│   ├── presets/                      # Preset UI screens + widgets
│   ├── personas/                     # Persona UI screens + provider
│   ├── backup/                       # Backup UI screen + provider
│   ├── catalog/                      # Character discovery: UI + provider + API services
│   ├── character_list/               # Character list/detail/editor screens + widgets
│   ├── character_gallery/            # Gallery screen + provider
│   ├── regex/                        # Global regex list screen
│   ├── cloud_sync/                   # Cloud sync UI + provider
│   │   ├── sync_provider.dart
│   │   ├── sync_config.dart / sync_models.dart / sync_repo_interfaces.dart
│   │   ├── cloud_adapter.dart
│   │   ├── services/
│   │   │   ├── sync_service.dart       # High-level orchestrator, lock management
│   │   │   ├── sync_engine.dart        # Manifest diff, upload/download, conflicts
│   │   │   ├── sync_controller.dart    # UI-facing sync actions
│   │   │   ├── sync_manifest.dart / sync_serialization.dart / sync_conflict.dart
│   │   │   ├── sync_queue.dart
│   │   │   ├── oauth_local_server.dart # Desktop OAuth loopback
│   │   │   ├── dropbox/                # dropbox_adapter, dropbox_auth
│   │   │   └── gdrive/                 # gdrive_adapter, gdrive_auth, gdrive_files, gdrive_folders
│   │   └── widgets/                    # sync_sheet, sync_sheet_widgets, sync_icons
│   ├── image_gen/                    # Image generation UI, provider, services
│   │   ├── image_gen_provider.dart
│   │   ├── image_gen_models.dart
│   │   ├── services/                    # image_gen_service, http, provider adapters
│   │   └── widgets/                     # sheet, rows, connection_fields, model_fields, renderer
│   ├── glossary/
│   │   └── glossary_sheet.dart         # Glossary UI (route `/menu/glossary`)
│   ├── onboarding/                   # First-run onboarding screen
│   ├── picks/                        # Featured picks grid + detail launcher
│   ├── tools/                        # Developer tools screen (tokenizer, coverage, etc.)
│   ├── dev/                          # Internal UI demos (menu group demo)
│   └── menu/                         # Sidebar menu + About overlay/screen
├── shared/
│   ├── shell/
│   │   ├── shell_screen.dart         # Bottom nav shell (GoRouter StatefulNavigationShell)
│   │   └── nav_height_provider.dart  # navHeightProvider: nav bar height for layout
│   ├── theme/                        # ThemePreset, storage, provider, fonts, app_colors, app_theme
│   ├── utils/
│   │   └── color_utils.dart
│   └── widgets/                      # Reusable UI primitives (glaze_bottom_sheet, sheet_view, …)
├── app.dart                          # GlazeApp: wires routerProvider + boot-time init
└── main.dart                         # Entry point: orientation lock, prompt_worker init
```

### Navigation (`lib/core/navigation/router.dart`)

GoRouter lives in `router.dart`, not `app.dart`. Shell tabs and overlay routes:

| Route | Screen |
|-------|--------|
| `/` | `ChatHistoryScreen` |
| `/characters` | `CharacterListScreen` |
| `/tools` (+ nested `api`, `personas`, `presets`, `regex`, `lorebooks`, `embeddings`) | `ToolsScreen` |
| `/menu` (+ `settings`, `themes`, `about`, `glossary`) | `MenuScreen` |
| `/chat/:charId` | `ChatScreen` |
| `/character/create`, `/character/:charId`, `…/edit`, `…/gallery` | Character CRUD overlays |
| `/sync` | `SyncSheet` |
| `/extensions`, `/extensions/preset-editor/:presetId` | Extensions screens |

---

## 1. Generation Pipeline

### Phase A — SSE stream (in call order)

| Step | File | Role |
|------|------|------|
| 1 | `chat_provider.dart` | Owns `ChatState`; starts gen, delegates to `ChatGenerationService` |
| 2 | `chat_generation_service.dart` | Thin facade → `StreamGenerationService.run()` |
| 3 | `stream_generation_service.dart` | Payload build, isolate, SSE, `SavedMessageWriter` on success/error |
| 4 | `prompt_payload_builder.dart` | Reads Riverpod state; async vector lore + memory scoring |
| 5 | `prompt_isolate.dart` + `prompt_worker.dart` | Runs `buildPrompt()` off UI thread |
| 6 | `prompt_builder.dart` | Block ordering inside isolate |
| 7 | `prompt_block_resolver.dart` | Resolves each block ID → text |
| 8 | `lorebook_vector_search.dart` | Vector scan (async, before isolate, in payload builder) |
| 9 | `lorebook_scanner.dart` | Keyword scan (sync, inside isolate) |
| 10 | `lorebook_merger.dart` | Merges keyword + vector, deduplicates |
| 11 | `memory_injection_service.dart` + `memory_budget.dart` | Scores entries, applies INV-PS4 token cap |
| 12 | `history_assembler.dart` | Assembles history blocks with depth inserts |
| 13 | `context_calculator.dart` | Trims history from oldest end |
| 14 | `regex_service.dart` | Applies regex scripts per block |
| 15 | `macro_engine.dart` | Expands `{{macro}}` tokens |
| 16 | `sse_client.dart` | Sends request, streams SSE deltas |
| 17 | `stream_accumulator.dart` | Splits text from inline `<think…>` reasoning |
| 18 | `response_normalizer.dart` | Non-streaming response extraction |

### Phase B — Post-SSE (`generation_pipeline.dart`)

After `StreamGenerationService` returns, `ChatNotifier` runs `GenerationPipeline.run()`:

1. Persist assistant message (or regen/error rollback paths)
2. `ChatGenerationService.processImageTags()` — inline `[IMG:GEN]` tags
3. `ChatGenerationService.processExtensions()` → `extension_post_gen_service.dart`
4. Cloud sync notification + generation notification preview

### Request Types

| Type | State owner | Streaming | Abort |
|------|-------------|-----------|-------|
| Chat | `ChatState.isGenerating` per `charId` | Yes (SSE) | `CancelToken` + `_activeGenId` in `ChatNotifier` |
| Image gen | `ChatState.isGeneratingImage` + `_imgGenCancelToken` | No (one-shot) | `_imgGenCancelToken` in `ChatNotifier` |
| Summary | Widget-local in `summary_sheet.dart` | No | Widget-scoped `CancelToken` |
| Memory draft | `MemoryBookController` (`_generatingDrafts`, `_cancelTokens`) | No | Per-draft `CancelToken`; mutex via `memory_active_drafts_provider` |

### Prompt Ordering (invariant — do not reorder)

1. Vector lorebook scan (async, in `PromptPayloadBuilder`, before isolate)
2. Keyword lorebook scan (synchronous in `PromptBuilder`, inside isolate)
3. Merge: keyword + vector, deduplicate vector against keyword
4. Memory injection (with optional token budget — see INV-PS4)
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
- `{{summary}}` — current chat summary (user-authored only)
- `{{memory}}` — triggered memory book entries. With `injectionTarget='macro'` this is the only way memory enters the prompt; with `injectionTarget='hard_block'` (default) the system already injects a "Memory Book" system message and `{{memory}}` lets the user place additional copies with custom wrapper tags.
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
4. `{{summary}}` / `{{memory}}` / `{{lorebooks}}` / `{{guidance}}`
5. Trim
6. Session variable macros (`setvar`/`getvar`)
7. Global variable macros (`setglobalvar`/`getglobalvar`)
8. Custom named macros
9. `{{random::}}` / `{{pick::}}`
10. Dice `{{roll::}}`
11. Date/Time
12. Escape handling

### Session variables on abort/error

`pendingSessionVars` from the isolate are written to the DB **only** on the success path (`SavedMessageWriter.writeAssistant`). Error/regen-error paths keep the pre-generation `sessionVars`. See `docs/INVARIANTS.md` INV-C5.

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
- `features/memory/controllers/memory_book_controller.dart` — UI-facing draft gen, cancel, mutex
- `features/memory/state/memory_active_drafts_provider.dart` — cross-feature mutex with chat gen
- `memory_draft_generator.dart` — LLM-based draft generation, batching, progress
- `memory_injection_service.dart` + `memory_budget.dart` — scoring, top-N, INV-PS4 token cap
- `memory_embedding_service.dart` — indexes/reindexes memory entries
- `memory_book_repo.dart` — DB persistence for `MemoryBook` rows
- `core/state/memory_settings_provider.dart` — global settings (SharedPreferences)

### Data Model (key fields)
```dart
MemoryBook {
  entries: List<MemoryEntry>
  pendingDrafts: List<MemoryDraft>
  settings: MemoryBookSettings  // includes maxInjectionBudgetPercent (default 0.35)
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

### Token budget (INV-PS4)
`MemoryInjectionBudget.maxInjectionTokens()` caps injected memory at
`contextBudgetTokens * maxInjectionBudgetPercent` (default 35%).
See `docs/INVARIANTS.md` INV-PS4.

---

## 5. Database Layer

**File:** `lib/core/db/app_db.dart` + `lib/core/db/repositories/`

### Tables (11 total, schema v21)

| Table | Repo | Notes |
|-------|------|-------|
| `Characters` | `character_repo.dart` | watchAll(); v18 `picksHash`, v19 `createdAt`, v13 `extensionsJson` |
| `ChatSessions` | `chat_repo.dart` | Largest repo (~250 lines); patch via `patchChatData` |
| `Presets` | `preset_repo.dart` | JSON blob per preset |
| `ApiConfigs` | `api_config_repo.dart` | v21: `cacheControlTtl` |
| `Personas` | `persona_repo.dart` | |
| `Lorebooks` | `lorebook_repo.dart` | entries + settings as JSON |
| `Embeddings` | `embedding_repo.dart` | `entryId`, `vectorsBlob`, `retrievalHintsJson`, `errorJson` |
| `ChatSummaries` | `summary_repo.dart` | one per session |
| `MemoryBookRows` | `memory_book_repo.dart` | |
| `ExtensionPresets` | `extension_presets_repository.dart` | v20 |
| `InfoBlocks` | `info_blocks_repository.dart` | v20 |

### Write Rule
**Never** do `getChat → mutate → saveChat`. Use `patchChatData` to serialize reads.
See `docs/rules/database.md`.

---

## 6. Cloud Sync

All service implementations live under `lib/features/cloud_sync/services/`.

### Files
- `sync_service.dart` — high-level orchestrator, lock management
- `sync_engine.dart` — manifest diff, upload/download, conflict detection
- `sync_controller.dart` — UI-facing sync actions
- `sync_manifest.dart` — reads/writes cloud JSON manifest (ETags + timestamps)
- `sync_serialization.dart` — entity → JSON envelope
- `sync_conflict.dart` — winner = newer `updatedAt`
- `sync_queue.dart` — serial queue preventing duplicate uploads
- `sync_config.dart` / `sync_models.dart` — configuration and data models
- `sync_provider.dart` — Riverpod provider for sync state
- `sync_repo_interfaces.dart` — abstract repo interfaces for sync
- `cloud_adapter.dart` — abstract adapter interface for cloud providers
- `dropbox/dropbox_adapter.dart` + `dropbox_auth.dart` — OAuth2 PKCE + API v2
- `gdrive/gdrive_adapter.dart` + `gdrive_auth.dart` + `gdrive_files.dart` + `gdrive_folders.dart`
- `oauth_local_server.dart` — desktop OAuth loopback (local HTTP server)
- `core/services/deep_link_service.dart` — mobile OAuth deep-link receiver
- `widgets/sync_sheet.dart` — Sync UI sheet

### What Is Synced
Characters, sessions, presets, API configs, personas, lorebooks, theme presets, active preset, selected app settings. **Not synced:** generation state, UI state, embedding vectors, extension/info-block rows, debug traces.

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

## 9. Extensions (Info Blocks)

Post-generation extension pipeline runs after the assistant message is saved.

### Files
- `extension_post_gen_service.dart` — orchestrator called from `ChatGenerationService.processExtensions`
- `info_block_service.dart` / `info_block_injector.dart` — block CRUD + prompt injection
- `image_block_service.dart` — image-type blocks
- `extension_presets_provider.dart` / `info_blocks_provider.dart` — Riverpod state
- DB: `ExtensionPresets`, `InfoBlocks` tables (schema v20)

---

## 10. Known Design Issues

Open issues:

1. **`onboarding_service.dart`** — UI lives in `features/onboarding/onboarding_screen.dart`, but the service still imports `package:flutter/material.dart` for `BuildContext` and pushes via `rootNavigatorKey.currentState.push()`.

Resolved (kept for history; details in git / PR notes):

- **magic_drawer_stats_service** — moved to `features/chat/services/`.
- **prompt_payload_builder split** — `prompt_inputs_collector` + `prompt_payload_assembler`.
- **chat_provider decomposition** — controllers + `generation_pipeline` + `saved_message_writer` (~420 lines; further splits possible).
- **lorebook_vector_search providers** — extracted to `lorebook_providers.dart`.
- **Chat ↔ memory draft mutex** — `memory_active_drafts_provider` + `MemoryBookController` (INV-M3/INV-M4).
- **Session vars on abort/error** — only success path persists isolate vars (INV-C5).
- **Memory injection token budget** — `memory_budget.dart` + INV-PS4.
