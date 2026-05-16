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
│   ├── db/
│   │   ├── app_db.dart               # AppDatabase singleton (9 tables, migrations v1–17)
│   │   ├── tables.dart               # Drift table class definitions
│   │   └── repositories/            # One repo per table (CRUD only)
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
│   │   ├── prompt_builder.dart       # Orchestrator: block ordering, lorebook merge, trimming
│   │   ├── prompt_block_resolver.dart# Maps preset block ID → resolved text
│   │   ├── prompt_payload_builder.dart # Riverpod-aware: assembles PromptPayload from state
│   │   ├── prompt_isolate.dart       # Runs buildPrompt() in a Dart isolate
│   │   ├── history_assembler.dart    # ChatMessage[] → PromptMessage[], macro application
│   │   ├── context_calculator.dart   # Token budget: trims history from oldest end
│   │   ├── fallback_prompt_builder.dart # Minimal prompt when no preset configured
│   │   ├── lorebook_scanner.dart     # Keyword scan: sticky/cooldown/probability/recursion
│   │   ├── lorebook_merger.dart      # Merges keyword + vector results, deduplicates
│   │   ├── lorebook_coverage.dart    # Diagnostic: full coverage report per entry/key
│   │   ├── lorebook_vector_search.dart # Cosine search + hybrid boost, Riverpod providers
│   │   ├── lorebook_embedding_service.dart # Indexes lorebook entries into embedding store
│   │   ├── memory_embedding_service.dart   # Indexes memory entries into embedding store
│   │   ├── memory_injection_service.dart   # Scores + selects memory entries for injection
│   │   ├── embedding_service.dart    # Calls embedding API, handles chunking + rate limits
│   │   ├── glaze_matcher.dart        # Pure regex keyword matching (3 whole-word modes)
│   │   ├── regex_service.dart        # Applies PresetRegex scripts to a string
│   │   ├── sse_client.dart           # SSE + non-streaming completions via Dio
│   │   ├── stream_accumulator.dart   # Parses inline <think>…</think> tags from stream
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
│   │   │   ├── backup_helpers.dart       # ZIP read/write, JSON helpers, V1→V2 upgrade
│   │   │   ├── flutter_backup_importer.dart  # Imports Glaze-native backup
│   │   │   ├── js_backup_importer.dart       # Imports SillyTavern ZIP (orchestrator)
│   │   │   ├── js_character_importer.dart    # Imports ST character PNG/JSON files
│   │   │   ├── js_chat_importer.dart         # Imports ST JSONL chat files
│   │   │   ├── js_api_config_importer.dart   # Parses ST settings → ApiConfig
│   │   │   ├── js_preset_importer.dart       # Imports ST preset JSON files
│   │   │   └── js_lorebook_importer.dart     # Imports ST lorebook JSON files
│   │   ├── migration_service.dart    # Migrates legacy Glaze-JS data to Drift DB
│   │   ├── preset_defaults.dart      # Ensures mandatory blocks exist in imported presets
│   │   ├── preset_seeder.dart        # Seeds built-in "Glaze Default" preset on first launch
│   │   ├── png_text_extractor.dart   # Reads tEXt chunks from PNG byte stream
│   │   ├── chat_import_export.dart   # Import/export individual chat sessions as JSONL
│   │   ├── file_export_service.dart  # Platform-aware file export (file_selector / share)
│   │   ├── deep_link_service.dart    # Listens for OAuth deep-link URIs
│   │   ├── generation_notification_service.dart # Android foreground/background notifications
│   │   ├── memory_prompt_presets.dart           # Built-in memory prompt templates
│   │   └── onboarding_service.dart   # !! MIXED: onboarding UI + completion logic — refactor candidate
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
│       ├── active_selection_provider.dart # Active preset/persona/globalVars/regexes
│       ├── character_provider.dart   # CharactersNotifier (watchAll reactive stream)
│       ├── lorebook_provider.dart    # LorebooksNotifier + settings/activations
│       ├── global_regex_provider.dart # GlobalRegexNotifier
│       └── memory_settings_provider.dart # MemoryGlobalSettings + notifier
├── features/
│   ├── chat/
│   │   ├── chat_provider.dart        # ChatNotifier: full ChatState lifecycle per charId
│   │   ├── chat_state.dart           # ChatState + StreamingState value objects
│   │   ├── chat_screen.dart          # UI: MessageList + ChatInputBar + header
│   │   ├── chat_generation_service.dart  # Orchestrates one generation cycle (SSE stream)
│   │   ├── chat_session_service.dart     # Creates/finds sessions, alternate greetings
│   │   ├── chat_message_service.dart     # Message-level mutations (edit/delete/hide/reorder)
│   │   ├── chat_actions_service.dart     # Branch/clear/rename/delete session
│   │   ├── initial_message_builder.dart  # Selects greeting, runs macros, returns first msg
│   │   ├── memory_draft_generator.dart   # LLM-based memory auto-generation
│   │   └── widgets/                      # Chat UI widgets (pure UI, large files OK)
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
│   ├── tools/                        # Developer tools screen (tokenizer, coverage, etc.)
│   └── menu/                         # Sidebar menu + About overlay
├── shared/
│   ├── shell/
│   │   ├── shell_screen.dart         # Bottom nav shell (GoRouter StatefulNavigationShell)
│   │   └── nav_height_provider.dart  # navHeightProvider: nav bar height for layout
│   ├── theme/
│   │   ├── theme_preset.dart         # Freezed ThemePreset model
│   │   ├── theme_provider.dart       # ThemeNotifier: loads + applies ThemeData
│   │   ├── theme_font_provider.dart  # ThemeFontNotifier: loads Google Fonts dynamically
│   │   └── app_colors.dart           # Color palette + fromPreset() factory
│   └── widgets/                      # Reusable UI primitives
│       ├── glaze_bottom_sheet.dart   # Primary bottom sheet (snap points, glassmorphic)
│       ├── sheet_view.dart           # SheetView: sheet-aware scaffold with header
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
| 7 | `lorebook_vector_search.dart` | Vector semantic search (runs after keyword scan) |
| 8 | `lorebook_merger.dart` | Merges keyword + vector results, deduplicates |
| 9 | `memory_injection_service.dart` | Scores memory entries, injects top-N |
| 10 | `history_assembler.dart` | Assembles chat history blocks with depth inserts |
| 11 | `context_calculator.dart` | Trims history from oldest end to fit token budget |
| 12 | `regex_service.dart` | Applies regex scripts to each prompt block |
| 13 | `macro_engine.dart` | Expands all `{{macro}}` tokens |
| 14 | `prompt_isolate.dart` | Runs prompt build off the UI thread |
| 15 | `sse_client.dart` | Sends request, streams SSE deltas back |
| 16 | `stream_accumulator.dart` | Splits text from inline `<think>` reasoning |
| 17 | `response_normalizer.dart` | Extracts final content (non-streaming path) |

### Request Types

| Type | Streaming | Registry | Abort |
|------|-----------|----------|-------|
| Chat | Yes (SSE) | `ChatState.isGenerating` per `charId` | `CancelToken` in `ChatNotifier` |
| Summary | No | None | Caller-owned |
| Memory draft | No | Own abort per draft ID | Per-draft controller in `MemoryDraftGenerator` |

### Prompt Ordering (invariant — do not reorder)

1. Keyword lorebook scan (synchronous in `PromptBuilder`)
2. Vector lorebook scan (async, after keyword scan, deduplicated against it)
3. Memory injection (guarded by 35% token budget)
4. Context cutoff — trims oldest messages first

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

**Comments:**
- `{{// comment}}` — single-line comment (removed)
- `{{ // }}...{{ /// }}` — multi-line scoped comment (removed)

**Escaping:** `\{\{` → `{{`, `\}\}` → `}}`

### Resolution Order (fixed)
1. Comment stripping
2. Static character macros
3. Trim
4. Session variable macros (`setvar`/`getvar`)
5. Global variable macros
6. Custom named macros
7. `{{random::}}` / `{{pick::}}`
8. Dice `{{roll::}}`
9. Date/Time
10. Reasoning tags
11. Escape handling

---

## 3. Lorebook System

### Files
- `lorebook_scanner.dart` — keyword scan: sticky/cooldown/probability/character-filter/recursion
- `lorebook_merger.dart` — merges keyword + vector results, deduplicates by entry ID
- `lorebook_coverage.dart` — diagnostic full coverage report
- `lorebook_vector_search.dart` — cosine similarity, hybrid boost (name/key/hint overlap)
- `lorebook_embedding_service.dart` — indexes lorebook entries (hash-based dirty check)
- `embedding_service.dart` — calls embedding API, auto-chunking, rate-limit handling
- `vector_math.dart` — `cosineSimilarity`, `findTopK`, `findTopKMulti` (MaxSim)
- `lorebook_provider.dart` — CRUD + activations + settings (SharedPreferences)

### Search Type System
- `searchType`: `'keys'` | `'vector'` | `'both'`
- `'keys'` — keyword-only (default)
- `'vector'` — vector-only semantic search
- `'both'` — combined (keyword results deduplicated from vector budget)

### Recursive Scan Bounds
- Max iterations: 5 (or 1 if `recursiveScan == false`)
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

### Token Budget Guard
If memory tokens ≥ 35% of `safeContext` OR memory tokens ≤ 0 → injection aborted.

---

## 5. Database Layer

**File:** `lib/core/db/app_db.dart` + `lib/core/db/repositories/`

### Tables (9 total, schema v17)
| Table | Repo | Notes |
|-------|------|-------|
| `Characters` | `character_repo.dart` | watchAll() reactive stream |
| `ChatSessions` | `chat_repo.dart` | 254 lines — largest repo |
| `Presets` | `preset_repo.dart` | JSON blob per preset |
| `ApiConfigs` | `api_config_repo.dart` | |
| `Personas` | `persona_repo.dart` | |
| `Lorebooks` | `lorebook_repo.dart` | entries + settings as JSON |
| `Embeddings` | `embedding_repo.dart` | vectors as binary BLOB |
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
- `dropbox/dropbox_adapter.dart` + `dropbox_auth.dart` — OAuth2 PKCE + API v2
- `gdrive/gdrive_adapter.dart` + `gdrive_auth.dart` + `gdrive_files.dart` + `gdrive_folders.dart`
- `oauth_local_server.dart` — desktop OAuth loopback (local HTTP server)
- `deep_link_service.dart` — mobile OAuth deep-link receiver

### What Is Synced
Characters, sessions, presets, API configs, personas, lorebooks, theme presets, active preset, selected app settings. **Not synced:** generation state, UI state, embedding vectors, debug traces.

---

## 7. Theme System

### Files
- `shared/theme/theme_preset.dart` — Freezed `ThemePreset` model
- `shared/theme/theme_provider.dart` — `ThemeNotifier`: loads active preset, generates `ThemeData`
- `shared/theme/theme_font_provider.dart` — `ThemeFontNotifier`: loads Google Fonts async at startup
- `shared/theme/app_colors.dart` — `AppColors.fromPreset()`: all palette slots with defaults

### `updatePreset(ThemePreset preset)` flow
1. `ThemeNotifier.updatePreset()` → saves to `ThemePresetStorage`
2. Rebuilds `ThemeData` from new preset
3. `ThemeFontNotifier` detects font change → reloads font family

---

## 8. Image Generation

### Files
- `image_gen_service.dart` — orchestrates: dispatches to provider adapters, saves images
- `image_gen_provider.dart` — manages settings + generation state
- Provider adapters: `routmy_image_provider.dart`, `openai_image_provider.dart`, `gemini_image_provider.dart`, `naistera_image_provider.dart`

---

## 9. Known Design Issues

See `docs/rules/` for enforcement rules. Issues tracked for refactor:

1. **`onboarding_service.dart`** (687 lines) — contains Flutter widget tree inside `services/`. Violates layer rule: services must not import `flutter/material.dart`. Refactor: extract UI to `features/onboarding/onboarding_screen.dart`, leave only completion-check logic in service.

2. **`magic_drawer_stats_service.dart`** (194 lines) — named "service" but lives in `features/chat/widgets/`. Move to `features/chat/` (provider or service level).

3. **`prompt_payload_builder.dart`** (224 lines) — reads 7+ Riverpod providers directly. Becoming a God object. Split: pure `PromptInputsCollector` (reads providers) + pure `PromptPayloadAssembler` (builds payload from collected inputs, no Riverpod dep).

4. **`chat_provider.dart`** (369 lines) — `ChatNotifier` does generate + swipe + edit + delete + branch + clear. Split responsibilities across dedicated notifiers or move action logic to services, leaving notifier as thin state owner.

5. **`lorebook_vector_search.dart`** — contains Riverpod provider declarations mixed with service logic. Riverpod providers should live in a `lorebook_vector_search_provider.dart`.
