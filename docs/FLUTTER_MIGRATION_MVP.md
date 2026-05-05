# Glaze Flutter Migration — MVP Plan

## Goal

Working chat app on iOS/Android/Windows that proves: Flutter works, no WKWebView, Drift/SQLite DB, prompt building in isolate, API streaming works.

---

## Phase 0: Scaffold (Day 1-2) — DONE

### Project setup
```
glaze_flutter/
├── lib/
│   ├── main.dart
│   ├── app.dart
│   ├── core/
│   │   ├── db/              # Drift/SQLite database
│   │   ├── models/          # Data classes
│   │   ├── state/           # Riverpod providers
│   │   ├── llm/             # Generation pipeline
│   │   ├── sync/            # Sync engine (Phase 3)
│   │   └── services/        # Misc services
│   ├── features/
│   │   ├── chat/            # Chat UI + logic
│   │   ├── characters/      # Character list + editor
│   │   ├── presets/         # Preset management
│   │   ├── settings/        # API config, app settings
│   │   └── onboarding/      # First-run setup
│   └── shared/
│       ├── widgets/         # Reusable components
│       ├── theme/           # App theme
│       └── utils/
├── ios/
├── android/
├── windows/
├── test/
└── pubspec.yaml
```

### Dependencies
```yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_riverpod: ^2.6        # State management
  drift: ^2.22                   # Database (SQLite)
  sqlite3_flutter_libs: ^0.5     # SQLite native binaries
  dio: ^5.7                      # HTTP + streaming
  go_router: ^14.6               # Navigation
  freezed_annotation: ^2.4       # Immutable models
  json_annotation: ^4.9
  path: ^1.9
  shared_preferences: ^2.3
  flutter_markdown: ^0.7         # Markdown rendering
  url_launcher: ^6.3

dev_dependencies:
  build_runner: ^2.4
  freezed: ^2.5
  json_serializable: ^6.8
  drift_dev: ^2.22               # Drift codegen
  flutter_test:
    sdk: flutter
```

### Deliverables
- [x] `flutter create` project
- [x] Drift/SQLite DB initialized
- [x] GoRouter with shell route
- [x] Riverpod setup
- [x] Basic theme (dark mode, accent color)
- [x] App runs on iOS simulator, Android emulator, Windows

---

## Phase 1: Data Layer (Day 3-7) — DONE

### Models — 1:1 from JS, typed with Freezed

```dart
// lib/core/models/character.dart
@freezed
class Character with _$Character {
  const factory Character({
    required String id,
    required String name,
    String? avatar,          // file path, NOT data URL
    String? description,
    String? personality,
    String? scenario,
    String? firstMes,
    String? mesExample,
    String? systemPrompt,
    String? creator,
    String? creatorNotes,
    @Default([]) List<String> tags,
    @Default([]) List<String> alternateGreetings,
    String? color,
    String? sessionId,
    @Default(0) int updatedAt,
    // gallery: stored as files, not in DB
  }) = _Character;
}

// lib/core/models/chat_message.dart
@freezed
class ChatMessage with _$ChatMessage {
  const factory ChatMessage({
    required String id,
    required String role,      // 'user' | 'assistant' | 'system'
    required String content,
    int? timestamp,
    String? personaId,
    String? personaName,
    String? image,             // file path
  }) = _ChatMessage;
}

// lib/core/models/chat_session.dart
@freezed
class ChatSession with _$ChatSession {
  const factory ChatSession({
    required String id,        // '{charId}_{sessionId}'
    required String characterId,
    required int sessionIndex,
    @Default([]) List<ChatMessage> messages,
    @Default(0) int updatedAt,
  }) = _ChatSession;
}

// lib/core/models/preset.dart
@freezed
class Preset with _$Preset {
  const factory Preset({
    required String id,
    required String name,
    String? author,
    @Default(false) bool mergePrompts,
    @Default('system') String mergeRole,
    @Default([]) List<PresetBlock> blocks,
    @Default([]) List<PresetRegex> regexes,
    String? guidedGenerationPrompt,
    String? guidedImpersonationPrompt,
    String? summaryPrompt,
    @Default(false) bool reasoningEnabled,
    String? reasoningStart,
    String? reasoningEnd,
    @Default(0) int createdAt,
  }) = _Preset;
}

// lib/core/models/api_config.dart
@freezed
class ApiConfig with _$ApiConfig {
  const factory ApiConfig({
    required String id,
    @Default('openai_compatible') String providerId,
    String? endpoint,
    String? key,
    String? model,
    @Default(8000) int maxTokens,
    @Default(32000) int contextSize,
    @Default(0.7) double temperature,
    @Default(0.9) double topP,
    @Default(true) bool stream,
    @Default('medium') String reasoningEffort,
    String? name,              // display name for connection profile
  }) = _ApiConfig;
}

// lib/core/models/persona.dart
@freezed
class Persona with _$Persona {
  const factory Persona({
    required String id,
    required String name,
    String? prompt,
    String? avatar,
  }) = _Persona;
}
```

### Drift Tables

```dart
// lib/core/db/tables.dart
@DataClassName('CharacterRow')
class Characters extends Table {
  TextColumn get charId => text()();
  TextColumn get name => text()();
  TextColumn get avatarPath => text().nullable()();
  TextColumn get description => text().nullable()();
  TextColumn get personality => text().nullable()();
  TextColumn get scenario => text().nullable()();
  TextColumn get firstMes => text().nullable()();
  TextColumn get mesExample => text().nullable()();
  TextColumn get systemPrompt => text().nullable()();
  TextColumn get postHistoryInstructions => text().nullable()();
  TextColumn get creator => text().nullable()();
  TextColumn get creatorNotes => text().nullable()();
  TextColumn get color => text().nullable()();
  IntColumn get updatedAt => integer().withDefault(const Constant(0))();
  TextColumn get tagsJson => text().nullable()();
  TextColumn get alternateGreetingsJson => text().nullable()();

  @override
  Set<Column> get primaryKey => {charId};
}

@DataClassName('ChatSessionRow')
class ChatSessions extends Table {
  TextColumn get sessionId => text()();
  TextColumn get characterId => text()();
  IntColumn get sessionIndex => integer()();
  TextColumn get messagesJson => text()();
  IntColumn get updatedAt => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {sessionId};
}

@DataClassName('PresetRow')
class Presets extends Table {
  TextColumn get presetId => text()();
  TextColumn get name => text()();
  TextColumn get dataJson => text()();

  @override
  Set<Column> get primaryKey => {presetId};
}

@DataClassName('ApiConfigRow')
class ApiConfigs extends Table {
  TextColumn get configId => text()();
  TextColumn get name => text()();
  TextColumn get providerId => text().withDefault(const Constant('openai_compatible'))();
  TextColumn get endpoint => text().nullable()();
  TextColumn get apiKey => text().nullable()();
  TextColumn get model => text().nullable()();
  IntColumn get maxTokens => integer().withDefault(const Constant(8000))();
  IntColumn get contextSize => integer().withDefault(const Constant(32000))();
  RealColumn get temperature => real().withDefault(const Constant(0.7))();
  RealColumn get topP => real().withDefault(const Constant(0.9))();
  BoolColumn get stream => boolean().withDefault(const Constant(true))();
  TextColumn get reasoningEffort => text().nullable()();
  BoolColumn get requestReasoning => boolean().withDefault(const Constant(false))();
  TextColumn get reasoningTagStart => text().nullable()();
  TextColumn get reasoningTagEnd => text().nullable()();

  @override
  Set<Column> get primaryKey => {configId};
}

@DataClassName('PersonaRow')
class Personas extends Table {
  TextColumn get personaId => text()();
  TextColumn get name => text()();
  TextColumn get prompt => text().nullable()();
  TextColumn get avatarPath => text().nullable()();

  @override
  Set<Column> get primaryKey => {personaId};
}
```

### Repository pattern

```dart
// lib/core/db/repositories/character_repo.dart
class CharacterRepo {
  final AppDatabase _db;
  Future<List<Character>> getAll();
  Future<Character?> getById(String id);
  Future<void> put(Character character);
  Future<void> delete(String id);
}

// Same pattern for ChatRepo, PresetRepo, ApiConfigRepo, PersonaRepo
```

### Image storage migration
- JS stores images as data URLs in IDB → Flutter stores as files in app directory
- `Platform.environment['APPDATA']/Glaze` (Windows), `~/.local/share/Glaze` (Linux), `~/Library/Application Support/Glaze` (macOS)
- DB stores only file path reference
- Import: decode data URL → write to file → store path

### Deliverables
- [x] All models defined with Freezed
- [x] Drift tables with @DataClassName
- [x] Repository classes for CRUD
- [x] Image storage via filesystem
- [x] Unit tests for all repositories

---

## Phase 2: Core Feature — Chat (Day 8-18) — IN PROGRESS

> **UI Reference**: See [`docs/UI_REFERENCE.md`](./UI_REFERENCE.md) for the complete screen-by-screen inventory of all Glaze JS views, buttons, navigation paths, and their Flutter port status. Consult this before implementing any screen.

### 2a: Character list screen (Day 8-10)

```
┌─────────────────────────┐
│  Glaze          [+⚙️]   │
│─────────────────────────│
│ ┌───┐ Alice             │
│ │ 😊│ Last msg 2h ago   │
│ └───┘                   │
│ ┌───┐ Bob               │
│ │ 🤖│ Last msg yesterday│
│ └───┘                   │
│                         │
│    [+ Import Card]       │
└─────────────────────────┘
```

- Grid/list of characters with avatar, name, last message preview
- Import from PNG (V2/V3 card extraction)
- Import from JSON
- Tap → opens chat

### 2b: Chat screen (Day 11-16)

```
┌─────────────────────────┐
│ ← Alice        ⚙️📋     │
│─────────────────────────│
│                         │
│     Hi! How are you?    │
│                         │
│ I'm doing great!       │
│ The sun is shining...   │
│                         │
│     Tell me more        │
│                         │
│ Well, I was walking...  │
│░░░░░░░░░ (streaming)    │
│─────────────────────────│
│ [Type a message...]  ➤  │
└─────────────────────────┘
```

Key components:
- `ChatScreen` — Scaffold with AppBar + MessageList + InputBar
- `MessageList` — `SliverList` inside `CustomScrollView` for 60fps on 1000+ messages
- `MessageBubble` — user/assistant styling, markdown rendering
- `InputBar` — text field + send button, multiline support
- `StreamingIndicator` — shows while generating

### 2c: Prompt building in Isolate (Day 14-16)

```dart
// lib/core/llm/prompt_isolate.dart
Future<PromptResult> buildPrompt(PromptPayload payload) async {
  return await compute(_buildPromptInIsolate, payload);
}

PromptResult _buildPromptInIsolate(PromptPayload payload) {
  // Same logic as current generationWorker.js:
  // 1. Apply macro replacements
  // 2. Build lorebook context
  // 3. Assemble preset blocks
  // 4. Apply regexes
  // 5. Calculate token counts
  // 6. Return ordered messages
  return PromptResult(messages: [...], tokenBreakdown: [...]);
}
```

No Web Worker. No WKWebView. Just `compute()` — Dart's built-in isolate spawn.

### 2d: API streaming (Day 15-17)

```dart
// lib/core/llm/transport/sse_client.dart
Stream<String> streamChatCompletion({
  required String endpoint,
  required String apiKey,
  required String model,
  required List<ChatMessage> messages,
  required int maxTokens,
  required double temperature,
}) async* {
  final response = await _dio.post(
    endpoint,
    options: Options(
      headers: {'Authorization': 'Bearer $apiKey'},
      responseType: ResponseType.stream,
    ),
    data: {
      'model': model,
      'messages': messages.map(_toJson).toList(),
      'max_tokens': maxTokens,
      'temperature': temperature,
      'stream': true,
    },
  );

  await for (final chunk in response.data.stream) {
    // Parse SSE lines, yield text deltas
    for (final line in decodeSSE(chunk)) {
      if (line.delta != null) yield line.delta;
    }
  }
}
```

Riverpod provider ties it together:
```dart
// lib/features/chat/chat_provider.dart
@riverpod
class ChatNotifier extends _$ChatNotifier {
  StreamSubscription? _genSub;

  Future<void> sendMessage(String text) async {
    // 1. Add user message to DB
    // 2. Build prompt via isolate
    // 3. Stream response
    // 4. Update UI in real-time
    // 5. Save assistant message to DB
  }

  void abortGeneration() {
    _genSub?.cancel();
  }
}
```

### 2e: API Settings screen (Day 17-18)

```
┌─────────────────────────┐
│ ← API Settings          │
│─────────────────────────│
│ Provider: OpenAI Compat │
│ Endpoint: [__________]  │
│ API Key:  [__________]  │
│ Model:    [__________]  │
│ Max Tokens: [8000]      │
│ Context:    [32000]     │
│ Temperature: [0.7]      │
│ Stream: [✓]             │
│                         │
│    [Test Connection]    │
└─────────────────────────┘
```

- Form with validation
- Test connection button (sends minimal request)
- Save to Drift

### Deliverables
- [x] Character list with import
- [x] Chat screen with streaming
- [x] Markdown rendering in messages
- [x] Prompt building in isolate
- [x] API config screen
- [x] Send message → stream response → save
- [x] Abort generation
- [x] Swipe for alternative response
- [x] Runs on iOS, Android, Windows

---

## Phase 3: Presets & Personas (Day 19-23)

### Preset editor
- Block list (drag to reorder)
- Block editor: role, content, depth, enabled
- Regex editor
- Default presets pre-loaded
- Import SillyTavern presets (JSON)

### Persona management
- Create/edit/delete personas
- Persona-connection per character/chat
- Persona selector in chat

### Deliverables
- [x] Preset CRUD + editor
- [x] Preset import from SillyTavern format
- [x] Persona CRUD + connections
- [x] Macro replacement ({{char}}, {{user}}, etc.)

---

## Phase 4: Lorebooks (Day 24-28)

- Lorebook list + CRUD
- Entry editor: keys, content, position, enabled, constant
- Activation per character/chat
- Keyword scanning in prompt builder isolate
- Constant entry injection

### Deliverables
- [x] Lorebook CRUD + UI
- [x] Entry editor
- [x] Keyword scanning integration in prompt pipeline
- [x] Constant entry injection

---

## Phase 5: Cloud Sync (Day 29-40)

### Architecture (direct port from JS)

```dart
// lib/core/sync/sync_engine.dart
class SyncEngine {
  final SyncManifest _manifest;
  final SyncSerialization _serialization;
  final CloudAdapter _adapter;  // Dropbox or GDrive

  Future<SyncResult> pushEntities();
  Future<SyncResult> pullEntities();
}

// lib/core/sync/adapters/dropbox_adapter.dart
class DropboxAdapter implements CloudAdapter {
  Future<void> upload(String path, Uint8List data);
  Future<Uint8List> download(String path);
  Future<List<CloudEntry>> listFolder(String path);
  Future<void> delete(String path);
}

// lib/core/sync/adapters/gdrive_adapter.dart
class GDriveAdapter implements CloudAdapter { ... }
```

### OAuth flow
- Dropbox: OAuth2 via `flutter_web_auth_2`
- Google Drive: OAuth2 via `google_sign_in` or `flutter_web_auth_2`

### Deliverables
- [x] Manifest V2 build/read/write
- [x] Entity serialization + hashing
- [x] Encryption (AES-GCM via `encrypt` package)
- [x] Dropbox adapter
- [x] Google Drive adapter
- [x] Push/pull/sync flows
- [x] Conflict detection + resolution UI
- [x] Gallery sync (resumable upload)

---

## Phase 6: Polish (Day 41-50)

- [ ] Theme system (accent color, dark/light, custom colors)
- [ ] Onboarding flow (first-run setup)
- [ ] Chat export/import (.jsonl)
- [ ] Character export (PNG with embedded card)
- [ ] Search across characters/chats
- [ ] Background generation notification
- [ ] Crash recovery (save generation state to DB)
- [ ] iOS keyboard handling
- [ ] Android back button / intent system
- [ ] App icons + splash screens
- [ ] CI/CD (GitHub Actions for all 3 platforms)

---

## What's NOT in MVP (post-launch)

| Feature | Reason |
|---------|--------|
| Extensions/JS plugins | Need embedded JS engine — Phase 7 |
| Vector search / RAG | Complex, low priority |
| Memory books | Can use lorebooks as workaround |
| Image generation | Nice-to-have |
| Group chats | Complex, low priority |
| Catalog browsing | Needs backend |
| Electron/desktop web | PWA if needed |

---

## Data Migration from Glaze JS

One-time migration tool:

```dart
// lib/core/db/migration/from_js.dart
Future<void> migrateFromGlazeJS(String exportJsonPath) async {
  // 1. Read Glaze export JSON
  // 2. Parse characters, chats, personas, presets, lorebooks
  // 3. Decode data URLs → write images to filesystem
  // 4. Write to Drift tables
  // 5. Mark migration complete in SharedPreferences
}
```

User flow: Export from Glaze JS → Import in Glaze Flutter → Done.

---

## Success Criteria

After Phase 2 (Day 18), we know:
1. ✅ Flutter works on iOS without WKWebView bugs
2. ✅ Drift/SQLite DB performs well with real data
3. ✅ Prompt building in isolate is fast
4. ✅ API streaming works
5. ✅ Basic chat loop is functional

If any of these fail → pivot decision before investing in Phase 3+.

---

## Timeline Summary

| Phase | Days | Cumulative |
|-------|------|------------|
| Phase 0: Scaffold | 2 | 2 |
| Phase 1: Data Layer | 5 | 7 |
| Phase 2: Chat (MVP core) | 11 | 18 |
| Phase 3: Presets & Personas | 5 | 23 |
| Phase 4: Lorebooks | 5 | 28 |
| Phase 5: Cloud Sync | 12 | 40 |
| Phase 6: Polish | 10 | 50 |

**Go/No-Go checkpoint: Day 18** (after Phase 2)
