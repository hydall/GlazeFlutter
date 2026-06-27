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
│   │   ├── app_db.dart                 # AppDatabase singleton (18 tables, schema v42)
│   │   ├── tables.dart                 # Drift table class definitions
│   │   └── repositories/              # One repo per table (CRUD only)
│   │       ├── api_config_repo.dart
│   │       ├── character_repo.dart
│   │       ├── character_folder_repo.dart
│   │       ├── chat_repo.dart
│   │       ├── embedding_repo.dart
│   │       ├── extension_presets_repository.dart
│   │       ├── global_variables_repo.dart
│   │       ├── info_blocks_repository.dart
│   │       ├── lorebook_repo.dart
│   │       ├── memory_book_repo.dart
│   │       ├── memory_catalog_repo.dart
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
│   │   ├── prompt_regex_applicator.dart # Pure: applies preset+global regex scripts to final messages
│   │   ├── prompt_inputs.dart         # Freezed value object: inputs for isolate build
│   │   ├── prompt_inputs_collector.dart # Reads Riverpod state, assembles PromptInputs (no async work)
│   │   ├── prompt_payload_assembler.dart # Pure: PromptInputs → PromptPayload (no Riverpod)
│   │   ├── prompt_payload_builder.dart # Riverpod-aware: assembles PromptPayload (vector/memory async)
│   │   ├── prompt_isolate.dart        # Spawns isolate; delegates to prompt_worker
│   │   ├── prompt_worker.dart         # Top-level entry: buildPrompt() inside isolate
│   │   ├── prompt_worker_codec.dart   # Isolate boundary JSON codec (serialize/deserialize payload+result)
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
│   │   ├── memory_formatting.dart    # Shared formatMemoryItems / formatMemoryRange helpers
│   │   └── vector_math.dart          # cosineSimilarity, findTopK, findTopKMulti, BLOB helpers
│   ├── llm/converters/               # Protocol-specific message converters (pure)
│   │   ├── claude_messages.dart      # Anthropic /v1/messages shape
│   │   ├── gemini_messages.dart      # Google Gemini shape
│   │   ├── openrouter_messages.dart  # OpenRouter (Anthropic/OpenAI passthrough)
│   │   ├── message_merger.dart       # Consecutive same-role message merging
│   │   ├── attachment_encoder.dart   # Image/file → provider attachment payload
│   │   ├── cache_breakpoint_marker.dart # Anthropic/OpenRouter cache_control placement
│   │   └── thinking_budget.dart      # Extended-thinking budget mapping per protocol
│   ├── llm/transport/                # LLM HTTP/SSE transports (one per protocol)
│   │   ├── chat_transport.dart       # Abstract ChatTransport interface
│   │   ├── chat_transport_request.dart # Shared request value object
│   │   ├── llm_protocol.dart         # Protocol enum (openai/anthropic/gemini/openrouter)
│   │   ├── transport_factory.dart    # ApiConfig.protocol → ChatTransport
│   │   ├── openai_chat_transport.dart
│   │   ├── anthropic_chat_transport.dart
│   │   ├── gemini_chat_transport.dart
│   │   └── openrouter_chat_transport.dart
│   ├── navigation/
│   │   └── router.dart               # GoRouter routes + shell (used by app.dart)
│   ├── platform/                     # Platform-specific integrations
│   │   ├── haptics.dart              # Haptic feedback helpers
│   │   ├── system_settings.dart      # OS settings (wallpaper, dark mode)
│   │   └── wallpaper.dart            # Device wallpaper fetch
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
│   │   │   ├── bridge_handlers.dart         # Single source of truth: 27 JS handler names
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
│   │   ├── screens/                    # extensions_screen, preset_editor_screen export
│   │   │   └── preset_editor/          # scaffold, sections, block editor widgets
│   │   ├── services/
│   │   │   ├── extension_post_gen_service.dart # Thin orchestrator for block chain entrypoints
│   │   │   ├── blocks/                 # BlockProcessor, handlers, status/panel/image helpers
│   │   │   ├── js_bridge/              # JsBridgeService dispatcher + capability-gated handlers
│   │   │   ├── info_block_service.dart         # LLM call for infoblock type
│   │   │   └── info_block_injector.dart        # Injects stored outputs into prompt context
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
│   │   │   ├── sync_binary_asset_syncer.dart # Avatar/gallery push/pull (extracted from SyncEngine)
│   │   │   ├── sync_image_stripper.dart # Strips [IMG:*] tags from chat sessions before sync
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
│   │   ├── nav_height_provider.dart  # navHeightProvider: nav bar height for layout
│   │   ├── shell_header_provider.dart
│   │   └── desktop/                  # Desktop (≥768px) three-column layout
│   │       ├── desktop_shell.dart    # Shell wrapper; left/center/right columns
│   │       ├── desktop_layout_provider.dart
│   │       ├── desktop_left_sidebar.dart  # Chat list + nav (replaces bottom nav)
│   │       ├── desktop_right_sidebar.dart # Tools / MagicDrawer
│   │       ├── desktop_window_view.dart
│   │       ├── desktop_floating_provider.dart
│   │       └── desktop_glossary_popup.dart
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
| `/` | `ChatHistoryScreen` (mobile); redirects to `/characters` on desktop (width ≥ 768, non-mobile force) |
| `/characters` | `CharacterListScreen` |
| `/tools` (+ nested `api`, `personas`, `presets`, `regex`, `lorebooks`, `lorebooks/settings`, `embeddings`) | `ToolsScreen` |
| `/menu` (+ `settings`, `themes`, `about`, `glossary`) | `MenuScreen` |
| `/chat/:charId` | `ChatScreen` (query params: `?session=`, `?new=1`, `?msg=`) |
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

After `StreamGenerationService` returns, `ChatNotifier._runGeneration()` runs
`GenerationPipeline.run()` for **send** and **regenerate** only:

1. Persist assistant message (or regen/error rollback paths)
2. `ChatGenerationService.processImageTags()` — inline `[IMG:GEN]` tags
3. `ChatGenerationService.processExtensions()` → `extension_post_gen_service.dart`
4. Cloud sync notification + generation notification preview

**Continue exception:** `ChatNotifier.continueMessage()` calls
`ChatGenerationService.generate()` directly and merges text onto the last assistant
message. It does **not** use `GenerationPipeline` — no image-tag processing, extensions
post-gen, or pipeline sync notification. See `docs/INVARIANTS.md` INV-CM2.

**Talkativeness:** `sendMessage()` may skip generation when
`character.extensions['talkativeness']` rolls above the configured threshold.

### Request Types

| Type | State owner | Streaming | Abort |
|------|-------------|-----------|-------|
| Chat | `ChatState.isGenerating` per `charId` | Yes (SSE) | `AbortHandler`: `CancelToken` + `_activeGenId` |
| Image gen | `ChatState.isGeneratingImage` + `_imgGenCancelToken` | No (one-shot) | `_imgGenCancelToken` in `ChatNotifier` |
| Summary | Widget-local in `summary_sheet.dart` | No | Widget-scoped `CancelToken` |
| Memory draft | `MemoryBookController` (`_generatingDrafts`, `_cancelTokens`) | No | Per-draft `CancelToken`; mutex via `memory_active_drafts_provider` |

### Reasoning / Thinking

`ApiConfig.requestReasoning` controls whether Glaze asks the provider for
provider-native reasoning. `ApiConfig.omitReasoning` suppresses app-side
reasoning request fields such as OpenAI `reasoning_effort`, Anthropic/Gemini
thinking configs, and Studio final-agent reasoning persistence. It does **not**
guarantee that a provider/model disables its internal thinking.

Gemini 3.x models can think by default. For example, Gemini 3.1 Pro exposes
thinking levels (`low` / `medium` / `high`) rather than a documented full off
switch. Custom OpenAI-compatible proxies such as rout.my may still report or
bill thought tokens even when Glaze omits reasoning request fields. Do not add
provider-specific `reasoning: { exclude: true }` or similar body fields unless
the target provider documents the exact field and we intentionally support that
contract.

Studio Mode follows the same policy for its final agent: trackers force
reasoning off/omitted; the final generator inherits the resolved `ApiConfig`
reasoning settings. Studio also strips prompt-level hidden-reasoning directives
from final-generator instructions when reasoning is disabled/omitted, but
cannot disable model-internal thinking if the upstream model always performs
it.

### Studio Mode Pipeline

Studio Mode is a tracker-around-generator model (Phase 5 refactor — see
`docs/PLAN_AGENTIC_STUDIO.md`). One main LLM (the generator) writes the visible
reply; lightweight trackers run as sidecars and contribute notes/injections
that shape the next prompt, never duplicating the generator's output.

Studio settings are stored as reusable Studio profiles in `studio_config_rows`.
Sessions bind to a profile by `profileId`; starting a new session can reuse an
existing profile without rebuilding agents. Rebuilding only changes the selected
profile's agent prompts/settings.

At generation time `MemoryStudioService.runTrackerCycle` runs:

1. **Cache probe** (`_probeCache`): each due tracker is checked against
   `_briefCache` keyed by refresh policy (`turn` / `scene` / `static`).
   Cache hits are excluded from the LLM round-trip.
2. **Batching** (`TrackerBatcher.groupAgents`): trackers with the same
   `(provider, model)` and `!runIndividually` are packed into one LLM request
   via `<agents><agent_task>` XML with a single system prompt that orders shared
   context first (`<role>` + `<lore>` = static + dynamic + trimmed history) and
   per-agent instructions last (`<agents>`) — a prompt-cache-friendly layout
   (Phase 6.1). Heavy trackers (`expression` / `illustrator` / `lorebook` name
   match, or explicit `StudioAgent.runIndividually`) are pulled out of the batch
   and run as their own request.
3. **Run phase** (`TrackerBatcher.runPhase`, concurrency limit 4): batch groups
   + individual agents fire in parallel, subject to the concurrency cap. Each
   batch is one LLM call → `parseBatchResponse` (`<result agent="id">` with
   missing-close-tag tolerance + `<result_ID>` legacy fallback).
4. **In-batch retry (layer 1)**: if any agent in the batch comes back failed,
   re-request the whole batch ONCE.
5. **Individual fallback (layer 2, concurrency limit 2)**: any agent still
   failed from both attempts is re-run as its own LLM request.
6. **Final generator** (`_runFinalGenerator`): runs every turn after all
   trackers settle, using `maxFinalHistoryMessages` (default 15) for the
   trimmed history; trackers receive their own `contextSize` (default 5,
   hard-cap 200) via `_limitTrackerHistory` + `truncateAgentText`
   (head 40% + tail 60%) + `stripHtmlTags`.

`AgentRunFailedException` (Phase 5.7.5) wraps tracker failures so the
generator still runs with the successful briefs plus an error marker. The
generator's own failure aborts the turn.

Per-tracker model override (`StudioAgent.modelSource = 'custom'` picks an
`ApiConfig` by `agent.model`; `modelOverride` applied on top) and
`runInterval` (every-N-th-turn scheduling) are respected. Concurrency caps:
`_maxConcurrentGroups = 4`, `_maxConcurrentFallback = 2` (Phase 5.7.2,
conservative defaults for desktop).

POST-processing (Phase 1.3) stays separate from the tracker pipeline: the
POST-cleaner runs after the full reply, produces a green swipe diff via
`appendCleanerSwipe` (`post_cleaner_service.dart`), without hold mode.

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
- `{{memory}}` — triggered memory book entries. Memory can enter the prompt three ways: a dedicated `memory` ("Memory Book") preset block (addable from the editor, resolves like the macro), the `{{memory}}` macro, or — with `injectionTarget='hard_block'` (default) — an auto-injected "Memory Book" system message. With `injectionTarget='macro'` and no `{{memory}}` macro or `memory` block present, memory is dropped and `memoryMacroMissing` is flagged. See INV-PS5.
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
- `memory_injection_service.dart` + `memory_budget.dart` + `memory_excerpt_selector.dart` — scoring, packing, INV-PS4 token cap
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

`messageRange` is provenance metadata and must survive draft approval:
`MemoryDraft.messageRange` is copied to `MemoryEntry.messageRange`. Older
generated entries whose title is a plain range like `91-105` are read with a
compatibility backfill into `messageRange`.

### Injection Rule
Memory entries are injected only when all linked `messageIds` are already **outside** the active context window. This prevents double-coverage.

### Token budget (INV-PS4)
`MemoryInjectionBudget.maxInjectionTokens()` caps injected memory at
`contextBudgetTokens * maxInjectionBudgetPercent` (default 35%).
See `docs/INVARIANTS.md` INV-PS4.

### Packing modes (`memoryPackingMode`)

After `MemorySelector` scores candidates, `MemoryExcerptSelector` decides
**what text** from each entry is injected. Settings live in
`MemoryBookSettings` / `MemoryGlobalSettings` (UI: *Memory → Advanced
selector → Packing mode*).

| Mode | Behaviour |
|------|-----------|
| `full` | Inject whole entry bodies when they fit the budget. |
| `hybrid` | Prefer full entries; when the budget is tight, fall back to per-entry excerpts (top chunks inside each entry). |
| `chunk_first` | Always pack **chunks** globally by relevance × token cost, not full entries. |

**Chunking** (`memory_excerpt_selector.dart`): entry content is split on blank
lines (`\n\n`) into paragraph blocks up to
`memoryExcerptTokensPerChunk` tokens; oversized blocks are split further by
sentence/word windows.

**`chunk_first` two-phase packing** (`selectChunkFirstGlobal`):

1. **Floor pass** — top `chunkFirstTopEntries` entries by entry score (recency,
   vector, keywords, importance) each receive up to `chunkFirstTopChunks` of
   their best chunks. This keeps fresh or vector-implied memories from losing
   entirely to keyword-heavy older arcs. Set `chunkFirstTopEntries` to `0` to
   disable the floor pass.
2. **Global pass** — remaining budget is filled with globally ranked chunks
   until `memoryExcerptChunksPerEntry` per entry or the token budget is
   exhausted.

Chunk relevance blends keyword overlap, vector chunk hints, and entry-level
signals (recency / vector / importance). Entry-level score shown in the
Injected Memory UI is **not** identical to per-chunk relevance in
`chunk_first` mode.

**Deferred `{{memory}}`**: when `injectionTarget='macro'` and a preset block
contains `{{memory}}` (e.g. inside `<summary>` on the last user message),
`PromptBuilder` finalizes memory **after** the context cutoff is known,
replacing `[[GLAZE_DEFERRED_MEMORY_CONTEXT]]` with the excerpt-packed macro
content. `PromptPayload.memorySelection` must be populated (no shadowed local)
for this path to run.

**Diagnostics** (`memory_diagnostics.dart`, `memory_activity_card.dart`):
per-candidate reasons include `chunk_rank_trimmed` / `chunk_budget_trimmed`;
expanded rows show `N из M` chunks and chunk indexes. Labels like `121-135` are
**chat message ranges** (`messageRange`), not chunk indices.

---

## 5. Database Layer

**File:** `lib/core/db/app_db.dart` + `lib/core/db/repositories/`

### Tables (18 total, schema v42)

| Table | Repo | Notes |
|-------|------|-------|
| `Characters` | `character_repo.dart` | watchAll(); v18 `picksHash`, v19 `createdAt`, v13 `extensionsJson`, v32 `tokenCount`, v33 `variantGroupId`/`variantName`/`variantOrder`, v34 `hidden`. `updateExtensionsJson` is the atomic read-modify-write helper for the JS `character` variable scope. |
| `CharacterFolders` | `character_folder_repo.dart` | v31; local character folders (composite PK `{folderId, charId}`) |
| `CharacterFolderMembers` | `character_folder_repo.dart` | v31; folder membership (composite PK + 2 indexes) |
| `ChatSessions` | `chat_repo.dart` | Largest repo (~250 lines); patch via `patchChatData`. `updateSessionVarsJson` is the atomic helper for the JS `chat` variable scope. |
| `Presets` | `preset_repo.dart` | JSON blob per preset |
| `ApiConfigs` | `api_config_repo.dart` | v21: `cacheControlTtl`; v23: `protocol`; v24: `topK`/`frequencyPenalty`/`presencePenalty`; v25: `cacheBreakpointMode`/`sessionIdMode` |
| `Personas` | `persona_repo.dart` | |
| `Lorebooks` | `lorebook_repo.dart` | entries + settings as JSON |
| `Embeddings` | `embedding_repo.dart` | `entryId`, `vectorsBlob`, `retrievalHintsJson`, `errorJson` |
| `ChatSummaries` | `summary_repo.dart` | v30: `enabled`; one per session |
| `MemoryBookRows` | `memory_book_repo.dart` | |
| `MemoryCatalogRows` | `memory_catalog_repo.dart` | v29; rebuildable per-session Memory Catalog state |
| `ExtensionPresets` | `extension_presets_repository.dart` | v20 |
| `InfoBlocks` | `info_blocks_repository.dart` | v20; v22 adds `status` TEXT (default `'done'`) + `order` INTEGER (default 0); v27 adds `swipe_id` |
| `StudioConfigRows` | `studio_config_repo.dart` | v36; reusable Studio profiles, v42 adds `profileId`/`profileName` for session-to-profile binding |

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
Characters, sessions, presets, API configs, personas, lorebooks, theme presets, Studio profiles, active preset, selected app settings, extension presets/settings, and info-block rows. **Not synced:** generation state, UI state, embedding vectors, debug traces.

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
- `image_tag_markup.dart` — pure `[IMG:GEN]`/`[IMG:RESULT]`/`[IMG:ERROR]` tag text transforms (extracted from ImageGenService)
- `image_gen_provider.dart` — manages settings + generation state
- `image_gen_models.dart` — Freezed data models for image generation
- `image_gen_http.dart` — HTTP client for image generation APIs
- Provider adapters: `routmy_image_provider.dart`, `openai_image_provider.dart`, `gemini_image_provider.dart`, `naistera_image_provider.dart`
- UI: `widgets/image_gen_sheet.dart`, `widgets/image_content_renderer.dart`

---

## 9. Extensions (Info Blocks + JS Bridge SDK)

The extensions feature ships two surfaces that share a single Dart-side
`JsBridgeService`:

1. **Post-generation block chain** — preset-driven infoblock / imageGen /
   jsRunner / interactive blocks that run after the assistant message
   is saved on the normal/regen path.
2. **JS Bridge SDK** (`window.glaze`) — extension authors can call
   `glaze.*` from sandboxed iframes (interactive panels) or from a
   headless `InAppWebView` that runs in the background even when no
   chat is open.

Formal invariants: `docs/INVARIANTS.md` INV-EG1–INV-EG8 and
INV-JS1–INV-JS6.

### Block chain (post-generation)

Blocks within a preset are executed in `order` (ascending). Execution is **parallel by
default**; a block with `dependsOnPrevious = true` waits for the preceding block to
finish and receives its output as context (see INV-EG6).

| `dependsOnPrevious` | Behaviour |
|---|---|
| `false` (default) | Launched as a `Future`, not awaited — runs in parallel with adjacent blocks |
| `true` | `await`-ed; preceding block's `content` passed as `previousOutput` |

Each block is stored as an `InfoBlock` row keyed by `(sessionId, messageId, blockId)`.
`BlockRunStatus` (`pending → running → done / error / stopped`) is updated atomically
per block via `InfoBlocksRepository.updateStatus()`.

### Block types

| `BlockType` | Handler | Notes |
|---|---|---|
| `infoblock` | `blocks/infoblock_handler.dart` | Calls `InfoBlockService`; injects last N results into prompt context |
| `imageGen` | `blocks/image_gen_block_handler.dart` | Reads `[img gen:…]` tag, calls `ImageGenService`, saves via `ImageStorageService`; result stored as `[IMG:RESULT:<path>]` |
| `jsRunner` | `blocks/js_runner_block_handler.dart` | Runs JS via `JsBlockExecutor`: headless `JsEngineService` preferred, visual bridge fallback. Periodic ticks only ever run here. |
| `interactive` | `blocks/interactive_block_handler.dart` | LLM → strip code-fence → sandboxed iframe island under the assistant message. JS inside the panel has access to `window.glaze.*` |

### Block triggers

| `BlockTrigger` | When it runs | What it can do |
|---|---|---|
| `afterAssistant` | `ExtensionPostGenService.processAfterGeneration` (via `GenerationPipeline`) | all block types |
| `afterUser` | `ChatNotifier.sendMessage` (fire-and-forget `unawaited(_dispatchAfterUserBlocks(...))`) | all block types |
| `periodic` | `PeriodicTriggerScheduler` (`Timer.periodic(block.periodicIntervalSeconds)`) | `jsRunner` only — headless engine preferred, visual bridge fallback |

The chain filter is enforced by `BlockProcessor` and `SingleBlockRunner`, with
`ExtensionPostGenService` kept as the public entrypoint. The same chain is reused
for `afterAssistant` (`runBlocksForMessage`) and `afterUser`
(`runAfterUserBlocks`). The periodic scheduler calls `runJsBlock()` directly —
no chain, no `InfoBlock` row, just a side-effect tick.

### Periodic scheduler

`PeriodicTriggerScheduler` is a singleton Riverpod provider. It watches
`extensionPresetsProvider` + `extensionsSettingsProvider` and registers
as a `WidgetsBindingObserver` to pause on `paused` / `inactive` /
`hidden` / `detached` (no catch-up tick on resume). The
`debugLifecycleState` test seam is used by `periodic_lifecycle_test.dart`.

### Cancellation

`ExtensionPostGenService` owns an `extensionBlocksCancelToken` (`CancelToken`).
Calling `cancelBlocks()` sets the token; `SingleBlockRunner` and each concrete
handler check it before and after async work. Cancelled blocks are marked
`stopped`. The cancel token is independent of the chat text-generation token
(INV-EG5).

### Key configuration fields (`BlockConfig`)

| Field | Default | Meaning |
|---|---|---|
| `order` | 0 | Execution order (ascending) |
| `dependsOnPrevious` | false | Serial/parallel mode |
| `injectLastN` | 0 | Inject last N block outputs into LLM context; 0 = disabled |
| `inject` | false | Whether to insert block output as a system message in the prompt |
| `trigger` | `afterAssistant` | `afterAssistant` / `afterUser` / `periodic` |
| `periodicIntervalSeconds` | 60 | Tick interval when `trigger == periodic` |

### Capability permissions

Each extension preset carries a `PresetPermissions` freezed model with
19 capability toggles (default-deny except `showToast`). Every bridge
method enforces its capability via `JsBridgeService._requireCapability`,
which delegates to an injected `PermissionCheck` function — production
wiring in `ChatWebViewWidget` reads `activePresetPermissionsProvider`.

| Capability | Bridge method |
|---|---|
| `read_chat_vars` / `write_chat_vars` / `delete_chat_vars` | `glaze.getVariables / setVariables / deleteVariable` (`scope: 'chat'`) |
| `read_character_vars` / `write_character_vars` / `delete_character_vars` | same (`scope: 'character'`) |
| `read_global_vars` / `write_global_vars` / `delete_global_vars` | same (`scope: 'global'`) |
| `read_message_vars` / `write_message_vars` / `delete_message_vars` | same (`scope: 'message'`) |
| `generate_text` | `glaze.generateText(prompt, { preset })` |
| `trigger_generation` | `glaze.triggerGeneration({ mode })` |
| `inject_prompt` / `uninject_prompt` | `glaze.injectPrompt / uninjectPrompt` |
| `play_audio` | `glaze.playAudio(source, options)` |
| `execute_command` | `glaze.executeCommand(command, args)` |
| `show_toast` (default ALLOW) | `glaze.showToast(message, { severity })` |

### Connection profiles

`ExtensionPreset.connectionProfiles` is a freezed record with three
`apiConfigId` slots: `big` / `medium` / `small`. `glaze.generateText({
preset })` reads the matching slot and resolves it via
`ConnectionProfileResolver` (falls through to the active API config
when the slot is empty or stale). The UI picker in
`preset_editor_screen.dart` lists every `ApiConfig` plus an
"Использовать основной" default.

### Variable scopes

JS variables use four scopes, each persisted or in-memory:

| Scope | Storage | Atomic repo |
|---|---|---|
| `chat` | `ChatSession.sessionVars['__glaze_variables']` (JSON string) | `ChatRepo.updateSessionVarsJson` |
| `character` | `Character.extensions['glaze_variables']` (Map) | `CharacterRepo.updateExtensionsJson` |
| `global` | `SharedPreferences['glaze.global_variables']` (JSON) | `GlobalVariablesRepo` (64 KiB cap, serialized writes) |
| `message` | in-memory `MessageVariablesNotifier` (per `sessionId` + `messageId`) | n/a |

JSON payload is validated (`_validateJsonValue` in `JsBridgeService`)
for type compatibility and ≤ 64 KiB total.

### Real audio backend

`AudioBridgeService` routes `glaze.playAudio(source, options)` to:

* `click` / `alert` / `haptic` — `SystemSound` / `HapticFeedback`
  (built-in cues; no audio player)
* `file://` / `http(s)://` URLs / absolute paths / `data:audio/…;base64,…` —
  `audioplayers` with the matching `Source` subclass
* `volume` (clamped 0..1) and `loop` options map to the player

`routeSource(source)` is a `@visibleForTesting` static helper that
returns the `Source` subclass (or `null` for built-in cues).

### JS execution

User-authored JS runs in a `<iframe sandbox="allow-scripts">` (without
`allow-same-origin`) — null origin, no access to `window.parent`,
`window.flutter_inappwebview`, or any API keys. Two execution paths:

* **Visual WebView** — `ChatBridgeController.runJsBlock()` is used
  when the chat is open; the script is forwarded into the chat
  WebView's `assets/chat_webview/bridge/chat_bridge_controller.js`
  `runSandboxedScript()` path.
* **Headless engine** — `JsEngineService` is a singleton
  `HeadlessInAppWebView` that loads `assets/chat_webview/headless.html`
  (also `sandbox="allow-scripts"`) and shares the same
  `JsBridgeService` instance as the visual WebView. Preferred for
  background / periodic ticks. Throws `HeadlessUnavailableError` when
  not ready; callers fall back to the visual bridge.

Both paths use `Window.headlessBridge.runSandboxedScript(script, contextJson)`
and the same `JsBridgeService.dispatch` for `glaze.*` calls.

### Dart files

* `extension_post_gen_service.dart` — public orchestrator entrypoint; owns cancel token; exposes `runBlocksForMessage`, `runAfterUserBlocks`, `runJsBlock`, `rerunBlock`, `rerunImageOnly`
* `blocks/block_processor.dart` — order/filter/`dependsOnPrevious` orchestration
* `blocks/single_block_runner.dart` — placeholder prep, context construction, handler dispatch, per-block error wrapping
* `blocks/block_status_tracker.dart` — placeholder/status/error/dedupe lifecycle
* `blocks/block_panel_updater.dart` — shared panel update/throttling plumbing
* `blocks/image_pixel_renderer.dart` — image bytes → persisted file/result token
* `blocks/js_block_executor.dart` — message-bound `jsRunner` execution + headless/visual fallback persistence
* `blocks/periodic_js_block_runner.dart` — periodic headless/visual fallback execution
* `blocks/image_only_rerunner.dart` — manual image-only rerun validation/status update flow
* `blocks/*_block_handler.dart` — concrete `infoblock`, `imageGen`, `jsRunner`, `interactive` handlers
* `info_block_service.dart` — LLM call + prompt assembly for `infoblock` type
* `info_block_injector.dart` — inserts stored `InfoBlock` outputs into the prompt context
* `js_bridge_service.dart` — compatibility export for `js_bridge/js_bridge_service.dart`
* `js_bridge/js_bridge_service.dart` — pure dispatcher: `{ method, params, context }` → `{ ok, result/error }`; no Riverpod
* `js_bridge/handlers/*_handler.dart` — variables, generation, prompt injection, audio, commands, toast
* `js_bridge/capability_resolver.dart` + `permission_gate.dart` — method/scope capability mapping and default-deny enforcement
* `js_engine_service.dart` — singleton headless engine + `JsEngineBridgeHost` (optional `currentCharIdProvider` for `triggerGeneration` in headless mode)
* `panel_host_service.dart` — singleton panel registry + resize/event broadcast streams
* `audio_bridge_service.dart` — `SystemSound` + `audioplayers` routing
* `command_registry.dart` — `/trigger` / `/getvar` / `/setvar` / `/inject` / `/toast` registry; `buildWiredCommandRegistry(WiredCommandDeps)` is the production default
* `js_bridge_toast_controller.dart` — severity-aware toast surface
* `periodic_trigger_scheduler.dart` — `WidgetsBindingObserver` + `Timer.periodic` for periodic blocks
* `connection_profile_resolver.dart` — `big` / `medium` / `small` → `ApiConfig` mapping
* `runtime_prompt_injection_service.dart` — session-scoped depth blocks separate from `InfoBlock`
* `state/message_variables_notifier.dart` — in-memory per-message variables
* `models/block_config.dart` — `BlockType` (`infoblock`/`imageGen`/`jsRunner`/`interactive`), `BlockTrigger` (`afterUser`/`afterAssistant`/`periodic`)
* `models/extension_preset.dart` — `blocks`, `permissions`, `connectionProfiles`
* `models/preset_permissions.dart` — `PresetPermissions` + `GlazeCapability` (19 values)
* `models/connection_profiles.dart` — `big` / `medium` / `small` mapping
* `models/trigger_mode.dart` — `continueGeneration` / `regenerate` / `auto`
* `models/trigger_result.dart` — sealed `TriggerResult`
* `core/db/repositories/global_variables_repo.dart` — SharedPreferences-backed
* DB: `ExtensionPresets`, `InfoBlocks` tables (v20; v22 adds `status` + `order` columns)

### WebView asset modules

Active chat WebView JS is loaded as ES modules from `assets/chat_webview/index.html`:

* `assets/chat_webview/glaze_sdk.js` — `window.glaze` SDK loaded before bridge bootstrap
* `assets/chat_webview/formatter/index.js` — exports/exposes `Formatter`; implementation in `formatter/formatter.js`, marker rendering in `formatter/text_format.js`
* `assets/chat_webview/renderer/index.js` — exports/exposes `Renderer`; message DOM in `renderer/message_renderer.js`, Shadow DOM CSS in `renderer/shadow_style.js`
* `assets/chat_webview/bridge/index.js` — imports `Formatter` and `Renderer`, creates `window.bridge`, registers scaled wheel handling and `onWebViewReady`
* `assets/chat_webview/bridge/chat_bridge_controller.js` — main JS bridge facade, Flutter transport, message list API, ext-block panel, sandbox runner
* `assets/chat_webview/bridge/panel_host.js` — sandboxed interactive iframe lifecycle and `glaze:*` relay
* `assets/chat_webview/headless.html` — headless engine host

Legacy single-file paths (`bridge.js`, `renderer.js`, `formatter.js`) are
compatibility markers only; `bridge.legacy.js` is the retained pre-module bridge
snapshot.

### Bridge integration

`ChatBridgeController` exposes:
- `updateBlockStatus(messageId, status?)` — pushes `⬡` badge update to WebView
- `showExtBlocksPanel(messageId, blocks)` — renders/removes inline block panel
- `runJsBlock(...)` — runs a user script in the sandboxed iframe
- `openInteractivePanel / closeInteractivePanel / postToInteractivePanel` — `BlockType.interactive` panel lifecycle
- Callbacks: `onExtBlocksClick`, `onExtBlockStop`, `onExtBlockRegen`, `onExtBlockRegenImage`, `onExtBlockEdit`, `onExtBlockDelete`, `onPanelResize`, `onPanelEvent`

`ChatMessageMapper` adds `blockStatus` (`'running' | 'done' | 'error' | null`) from
`ChatMessageMapperContext.blockStatusByMessageId`; the WebView renders a `⬡` badge in
the message header.

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
- **JS extensions MVP** — `window.glaze` SDK, headless `JsEngineService`, capability permissions, periodic/afterUser triggers, interactive panels, audioplayers-backed audio, big/medium/small connection profiles, wired `CommandRegistry`, lifecycle-paused periodic scheduler. Current module boundaries are documented in § 9.
- **`sync_engine.dart` decomposition** — `SyncBinaryAssetSyncer` (avatar/gallery push/pull) + `sync_image_stripper.dart` extracted; `saveLorebookActivations` injected as callback (removed provider-layer import from service).
- **`prompt_builder.dart` decomposition** — regex application extracted to `prompt_regex_applicator.dart`; deferred-memory finalization extracted to `_finalizeDeferredMemory()`.
- **`image_gen_service.dart` decomposition** — `[IMG:*]` tag-markup text transforms extracted to `image_tag_markup.dart` (`ImageTagMarkup`).
- **`memory_injection_service.dart` arch fix** — removed `Ref` dependency; `MemoryGlobalSettings` injected via callback.
- **`prompt_worker.dart` decomposition** — isolate-boundary JSON codec extracted to `prompt_worker_codec.dart`.
- **Triplicated memory formatting helpers** — `_formatMemoryItems` / `_formatMemoryRange` deduplicated to `memory_formatting.dart`.
