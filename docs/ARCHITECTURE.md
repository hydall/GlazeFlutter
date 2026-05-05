# Architecture — GlazeFlutter

Mobile-first LLM frontend for AI roleplay. Flutter rewrite of [Glaze](https://github.com/hydall/Glaze).
**Stack:** Flutter 3.41 + Riverpod 2 + Isar 3 + GoRouter. **Language:** Dart only. **License:** AGPL-3.0.

Related docs:
- Migration plan: `docs/FLUTTER_MIGRATION_MVP.md`, `docs/FLUTTER_MIGRATION_FULL_PLAN.md`
- Generation invariants: `docs/rules/generation.md`
- Race condition rules: `docs/rules/race-conditions.md`
- Database rules: `docs/rules/database.md`
- Formal invariants: `docs/INVARIANTS.md`

## 0. Architecture Overview

### Target Architecture

```text
UI (screens/widgets)
  → Riverpod providers (state + business logic)
    → Repositories (DB abstraction)
      → Isar (persistence)
    → Services (LLM, prompt builder, macro engine)
      → Dio (HTTP/SSE)
```

- `UI` gathers user intent and renders state.
- `Providers` own actions like chat generation, summary, memory-draft.
- `Repositories` abstract Isar persistence.
- `Services` handle LLM transport, prompt building, macro engine, sync.

### Event System

Internal events use `EventHub` (StreamController-based). No `window.dispatchEvent`.

---

## 0.1 Directory Tree

```text
lib/
├── main.dart
├── app.dart                        # MaterialApp + GoRouter
├── core/
│   ├── db/
│   │   ├── app_db.dart             # Isar instance singleton
│   │   ├── collections.dart        # Isar @collection classes
│   │   └── repositories/
│   │       ├── character_repo.dart
│   │       ├── chat_repo.dart
│   │       ├── preset_repo.dart
│   │       ├── api_config_repo.dart
│   │       └── persona_repo.dart
│   ├── models/                     # Freezed data classes
│   │   ├── character.dart
│   │   ├── chat_message.dart
│   │   ├── chat_session.dart
│   │   ├── preset.dart
│   │   ├── api_config.dart
│   │   └── persona.dart
│   ├── state/                      # Riverpod providers
│   │   ├── db_provider.dart
│   │   ├── character_provider.dart
│   │   ├── chat_provider.dart
│   │   ├── preset_provider.dart
│   │   ├── api_config_provider.dart
│   │   └── persona_provider.dart
│   ├── llm/
│   │   ├── macro_engine.dart       # Macro replacement
│   │   ├── prompt_builder.dart     # Prompt assembly logic
│   │   ├── prompt_isolate.dart     # compute() wrapper
│   │   ├── sse_client.dart         # Dio SSE streaming
│   │   ├── stream_accumulator.dart # Text/reasoning accumulation
│   │   ├── response_normalizer.dart# Response extraction
│   │   ├── tokenizer.dart          # Token estimation
│   │   ├── regex_service.dart      # Regex application
│   │   └── vector/
│   │       ├── embedding_service.dart
│   │       ├── vector_search.dart
│   │       └── indexing_service.dart
│   ├── services/
│   │   ├── image_storage.dart
│   │   ├── character_importer.dart
│   │   ├── migration_service.dart
│   │   └── file_saver.dart
│   ├── sync/
│   │   ├── sync_engine.dart
│   │   ├── sync_manifest.dart
│   │   ├── crypto/
│   │   │   ├── sync_crypto.dart
│   │   │   └── key_manager.dart
│   │   └── adapters/
│   │       ├── cloud_adapter.dart  # Abstract interface
│   │       ├── dropbox_adapter.dart
│   │       └── gdrive_adapter.dart
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
└── shared/
    ├── widgets/
    │   ├── glaze_scaffold.dart
    │   ├── glaze_text_field.dart
    │   └── loading_overlay.dart
    └── theme/
        ├── app_theme.dart
        └── app_colors.dart
```

---

## 1. Tokenizer

### Files
- `lib/core/llm/tokenizer.dart` — Token estimation
- `lib/core/llm/prompt_builder.dart` — Token calculation in `buildPrompt()`

### Structure

**Token Estimation:**
- `estimateTokens(text)` — Heuristic: `(text.length / 3.35).ceil()`
- Real tokenizer (gp-tokenizer equivalent) to be added post-MVP

**Context Calculation (`prompt_builder.dart`):**
- `buildPrompt()` computes token breakdown by source:
  - `character` — Character card content
  - `preset` — Preset blocks
  - `summary` — Summary sections
  - `lorebook` — Keyword lorebook entries
  - `vectorLore` — Vector search lorebook entries
  - `memory` — Memory book entries
  - `history` — Chat history

---

## 2. Vectorization

### Files
- `lib/core/llm/vector/embedding_service.dart` — Embedding API calls
- `lib/core/llm/vector/vector_search.dart` — Cosine similarity search
- `lib/core/llm/vector/indexing_service.dart` — Entry indexing with hash check
- `lib/core/db/repositories/embedding_repo.dart` — Isar persistence

### Structure

**Embedding Service:**
- `embed(text)` — Single text embedding
- `embedBatch(texts)` — Batch embedding
- `testConnection()` — Connection test

**Vector Search:**
- `cosineSimilarity(a, b)` — Standard cosine similarity
- `search(queryVec, candidates, k, threshold)` — Top-K search

**Dual-Channel Retrieval:**
1. Isolate scans entries with `scanLorebooks()` — keyword matching
2. Main thread runs `VectorSearchEngine.search()` — semantic search
3. Results merged, deduplicated by entry ID
4. Keyword matches prioritized over vector matches

---

## 3. MemoryBooks

### Data Model

```dart
@freezed
class MemoryBook with _$MemoryBook {
  const factory MemoryBook({
    required String id,
    required String sessionId,
    @Default([]) List<MemoryEntry> entries,
    @Default([]) List<DraftEntry> pendingDrafts,
    MemorySettings? settings,
    @Default(0) int updatedAt,
  }) = _MemoryBook;
}

@freezed
class MemoryEntry with _$MemoryEntry {
  const factory MemoryEntry({
    required String id,
    required String content,
    @Default([]) List<String> keys,
    @Default(false) bool vectorSearch,
    @Default([]) List<String> messageIds,
    String? status,       // 'active' | 'needs_rebuild' | 'stale'
    String? source,       // 'manual' | 'auto' | 'import_bootstrap'
  }) = _MemoryEntry;
}
```

### Generation Flow
1. `generateMemoryDraftForMessages()` — Creates draft from selected messages
2. `runBatchDraftGeneration()` — Parallel batch generation for pending drafts
3. `generateMemoryDraft()` — API call with continuity context
4. Draft parsed, user approves or regenerates

### Injection Rules
- Memory entries injected only if all linked `messageIds` are outside the active prompt context
- This avoids injecting memories for message ranges still present in the current prompt window

---

## 4. Macro Engine

### Files
- `lib/core/llm/macro_engine.dart`

### Supported Macros

**Character/User:**
- `{{char}}`, `{{description}}`, `{{scenario}}`, `{{personality}}`, `{{mesExamples}}`
- `{{user}}`, `{{persona}}`

**Variables (SillyTavern-compatible):**
- `{{setvar::name::value}}`, `{{getvar::name}}`
- `{{setglobalvar::name::value}}`, `{{getglobalvar::name}}`

**Lucid Loom / LumiverseHelper macros:**
- `{{lumiaDef}}`, `{{loomRetrofits}}`, etc.
- Read from global variables set via `setglobalvar`

**Utility:**
- `{{random::a::b::c}}`, `{{pick::a::b::c}}`
- `{{roll::1d20}}`, `{{trim}}`
- `{{date}}`, `{{time}}`, `{{weekday}}`

**Reasoning:**
- `{{reasoningPrefix}}`, `{{reasoningSuffix}}`

**Comments:**
- `{{// comment}}` — removed
- `{{ // }}...{{ /// }}` — scoped comment, removed

**Escaping:**
- `\{\{` → `{{` and `\}\}` → `}}`

---

## 5. Reasoning System

### Logic

**Settings Resolution:**
1. User enables "Show Native Reasoning" → `requestReasoning = true`
2. Preset can override ONLY to enable (`reasoningEnabled: true`)
3. Preset `reasoningEnabled: false` does NOT disable user's choice

**Extraction (ResponseNormalizer):**
1. `reasoning_content` field from API response → `finalReasoning`
2. Inline tags (`reasoningStart`...`reasoningEnd`) in content → `inlineReasoning`
3. Both combined and displayed to user

---

## 6. Network / LLM Requests

### Files
- `lib/core/llm/sse_client.dart` — SSE streaming via Dio
- `lib/core/llm/stream_accumulator.dart` — Text/reasoning accumulation
- `lib/core/llm/response_normalizer.dart` — Response extraction
- `lib/core/state/chat_provider.dart` — Chat state management
- `lib/features/chat/chat_screen.dart` — Chat UI
- `lib/features/settings/api_settings_screen.dart` — API settings

### Request Types
- `chat` — Main character response generation
- `summary` — Summary generation
- `memory_draft` — MemoryBook draft generation
- `model_discovery` — `/models` fetch

### Current End-to-End Flow

**Chat Generation:**
1. User taps send → `ChatNotifier.sendMessage(text)`
2. Add user message to state + Isar
3. Build prompt in isolate via `compute(buildPrompt, payload)`
4. After isolate returns, perform late enrichment:
   - Vector lore retrieval
   - Memory injection
   - Context breakdown assembly
5. Stream response via `streamChatCompletion()` with `CancelToken`
6. `onUpdate()` applies streaming text/reasoning to state
7. `onComplete()` finalizes message, persists to Isar, clears generation state
8. `onError()` restores state and writes formatted error output

**Cancel Signal Propagation:**
1. User presses stop → `cancelToken.cancel()`
2. Dio cancels HTTP request, closes TCP connection
3. SSE parser detects cancellation, stops reading chunks
4. `handleCancelOutcome()` routes with `userCanceled` flag
5. Error handler fast-paths `CancelException` → skips error toast, restores state

### Transport Behavior
- Request endpoint: `$apiUrl/chat/completions`
- Streaming: SSE parsing with `data: ...` lines and `[DONE]` termination
- Non-streaming: one-shot JSON response
- Cancel via Dio `CancelToken`
- Timeout via Dio `ReceiveTimeout` / `SendTimeout`
- Callback contract:
  - `onUpdate(delta, reasoningDelta, effectiveText, effectiveReasoning)`
  - `onComplete(text, reasoning)`
  - `onError(error)`

---

## 7. Cloud Sync

### Files
- `lib/core/sync/sync_engine.dart` — Manifest diffing, serialization, encryption-aware upload/download
- `lib/core/sync/sync_manifest.dart` — Manifest build/read/write
- `lib/core/sync/adapters/dropbox_adapter.dart` — Dropbox OAuth + file operations
- `lib/core/sync/adapters/gdrive_adapter.dart` — Google Drive OAuth + file operations
- `lib/core/sync/crypto/sync_crypto.dart` — AES-256-GCM payload encryption
- `lib/core/sync/crypto/key_manager.dart` — Recovery phrase generation/restoration

### Ownership Model
- Maintainer configures OAuth app credentials in `.env`
- End users authenticate into their own cloud accounts
- Synced files stored under `/Glaze` in user's cloud
- App never routes all users into one shared maintainer-owned storage account

### OAuth Flow
1. User taps Dropbox or Google Drive
2. Adapter builds OAuth URL with PKCE
3. `flutter_web_auth_2` opens browser, receives redirect with auth code
4. Adapter exchanges code for tokens, stores via `flutter_secure_storage`
5. Future API calls reuse stored access token

### Data Flow
1. `SyncEngine` picks adapter from `syncProvider`
2. `detectEncryptionState()` checks local sync key
3. `pushEntities()` / `pullEntities()` compare local vs cloud manifest
4. Entity payloads serialized per type, optionally encrypted, uploaded
5. Pull emits conflicts when both local and remote changed since baseline

### Encryption Model
- Optional, local-first
- Recovery phrase derives AES-256-GCM key through `KeyManager`
- Cloud never stores recovery phrase or decrypted key material
- Without encryption, payloads are plain JSON

### Synced Data
- Characters, personas, chats: full Isar collections
- Lorebooks: single Isar blob
- API connection presets: single Isar blob
- Theme presets: single Isar blob
- App/API runtime settings: SharedPreferences keys bundled under `local_storage` entity

Not synced: active generation state, temporary UI state, debug traces, embedding vectors

---

## Database Layer

### Isar

All data stored in Isar. Collections defined in `lib/core/db/collections.dart`.

### Write Transactions

All writes go through `isar.writeTxn()`. This serializes concurrent writes automatically.

### Repository Pattern

Each collection has a repository class that maps between Freezed models and Isar collections:

```dart
class CharacterRepo {
  final Isar _db;
  Future<List<Character>> getAll();
  Future<Character?> getById(String id);
  Future<void> put(Character character);
  Future<void> delete(String id);
}
```

### Read-Mutate-Write

Always inside a `writeTxn`:

```dart
await isar.writeTxn(() async {
  final col = await isar.chatSessionCollections
      .where().sessionIdEqualTo(id).findFirst();
  if (col == null) return;
  // mutate
  await isar.chatSessionCollections.put(col);
});
```

Never: `getById` → mutate → `put` outside a transaction.

### Image Storage

- Character avatars and chat images stored on file system
- `path_provider.getApplicationDocumentsDirectory()` → `avatars/`, `gallery/`, `chat_images/`
- Isar stores only relative file path strings, not binary data
- Import: decode data URL → write file → store path

### Crash Recovery

- `WidgetsBindingObserver.appLifecycleState` detects backgrounding
- Save intermediate state to Isar on `AppLifecycleState.paused`
- On resume, verify generation state consistency
- In-progress operations that were suspended may need restart

---

## Settings Ownership

| Setting | Owner | Location |
|---------|-------|----------|
| Embedding endpoint/key/model | API | `ApiConfigCollection` |
| Search type (keys/vector/both) | Lorebook | `LorebookGlobalSettings` |
| Vector threshold / topK | Lorebook | `LorebookGlobalSettings` |
| Memory search type | MemoryBook session | `MemorySettings` |
| Dropbox OAuth app key | Build config | `.env` |
| Google Drive OAuth client ID | Build config | `.env` |
| Connected sync provider | Sync state | SharedPreferences |
| Sync OAuth tokens | Sync state | `flutter_secure_storage` |
| Recovery phrase-derived key | Crypto | Isar |
| API endpoint/key/model | API runtime config | `ApiConfigCollection` |
| Temperature / stream / maxTokens | API runtime config | `ApiConfigCollection` |
| Reasoning toggle/tags | API + preset override | `ApiConfigCollection`, `Preset` |

---

## Testing Checklist

### Tokenizer
- [ ] Context breakdown shows correct proportions
- [ ] Token count updates on message hide/delete

### Vectorization
- [ ] Entries index successfully with progress display
- [ ] Vector search returns relevant results
- [ ] Dual-channel: keyword + vector results merged
- [ ] Force reindex rebuilds stale entries

### MemoryBooks
- [ ] Scan Chat creates planned segments
- [ ] Batch Generate creates drafts
- [ ] Approved memories show badge
- [ ] Memory injection skips entries whose messages are still in context

### Macros
- [ ] SillyTavern variables persist per session
- [ ] Global variables persist across sessions
- [ ] Comments are stripped from output

### Reasoning
- [ ] User reasoning toggle works regardless of preset
- [ ] Inline reasoning tags extracted from content
- [ ] Native `reasoning_content` field displayed

### Network / LLM Requests
- [ ] Chat requests succeed in both streaming and non-streaming modes
- [ ] User cancel closes the TCP connection immediately
- [ ] User cancel skips error toast
- [ ] Timeout cancel shows error toast
- [ ] Stale completions from previous generations do not mutate newer state
- [ ] Crash buffer recovery: messages survive app crash during generation

### Cloud Sync
- [ ] Push works with encryption disabled (`.json` payloads)
- [ ] Push/Pull works with encryption enabled (`.enc` payloads)
- [ ] Conflicts surface in UI and can be resolved
