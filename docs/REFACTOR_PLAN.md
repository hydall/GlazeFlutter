# Refactoring Plan — GlazeFlutter

Branch: `refactor/webview-and-core`
Each phase = separate PR. Each task = separate commit.

---

## Phase 0: Characterization Tests (safety net)

- [x] 0.1 SharedPrefs keys & AppSettings defaults (`shared_prefs_keys_test.dart`)
- [x] 0.2 UI→DB violation catalog (`ui_db_violations_test.dart` — 17 files, 24 tests)
- [x] 0.3 JS bridge: selection, edit, swipe, batching (`bridge_selection_edit_swipe_test.dart` — 54 tests)
- [x] 0.4 WebView callback contract: widget ↔ bridge controller (`webview_callback_contract_test.dart` — 10 tests)
- [x] 0.5 ChatNotifier abort + image recovery, ChatState, StreamingState (`chat_notifier_abort_image_test.dart` — 27 tests)

## Phase 1: Extract Constants & Utilities (low risk, high ROI)

- [x] 1.1 IMG-tag regex → `lib/core/constants/image_gen_patterns.dart` (6 files affected)
- [x] 1.2 `SharedPrefsProvider` — single Riverpod provider (see detail below)
- [x] 1.3 Token estimation: `length/4` → `estimateTokens()` in `chat_generation_service.dart`
- [x] 1.4 Remove dead code `resetLoadingTags` in `image_gen_service.dart`
- [x] 1.5 `_messagePreview`: `List` → `List<ChatMessage>`, remove `as dynamic` in `chat_provider.dart`

### 1.2 Detail — SharedPrefsProvider Migration

**New file:** `lib/core/state/shared_prefs_provider.dart`
```dart
final sharedPreferencesProvider = FutureProvider<SharedPreferences>((ref) {
  return SharedPreferences.getInstance();
});
```

**Pattern — Riverpod classes (have `ref`):** replace `await SharedPreferences.getInstance()` → `await ref.read(sharedPreferencesProvider.future)`

| File | Type |
|------|------|
| `app_settings_provider.dart` | AsyncNotifier |
| `active_selection_provider.dart` | standalone functions (WidgetRef/Ref) |
| `global_regex_provider.dart` | AsyncNotifier |
| `memory_settings_provider.dart` | StateNotifier (added `Ref _ref`) |
| `lorebook_provider.dart` | AsyncNotifier + standalone functions |
| `api_list_provider.dart` | AsyncNotifier |
| `preset_list_provider.dart` | AsyncNotifier |
| `image_gen_provider.dart` | AsyncNotifier |
| `catalog_provider.dart` | StateNotifier (has `Ref _ref`) |
| `preset_seeder.dart` | WidgetRef function |

**Pattern — ConsumerWidgets:** replace `await SharedPreferences.getInstance()` → `await ref.read(sharedPreferencesProvider.future)`

| File |
|------|
| `chat_screen.dart` |
| `magic_drawer.dart` |
| `chat_stats_sheet.dart` |
| `session_lifecycle_tracker.dart` |
| `api_settings_screen.dart` |
| `embedding_settings_screen.dart` |
| `sync_sheet.dart` |

**Pattern — Plain Dart services (no `ref`):** optional `SharedPreferences?` param with fallback to `getInstance()`

| File | Approach |
|------|----------|
| `onboarding_service.dart` | Optional `prefs` param |
| `sync_deletion_tracker.dart` | Optional `prefs` param |
| `image_storage_service.dart` | Optional `prefsArg` param |
| `lorebook_provider.dart` (save functions) | Optional `prefs` param |
| `ThemePresetStorage` | Constructor injection + `create()` factory |

**Not migrated** (backup/migration/sync services — no `ref`, low testability priority):
`sync_service.dart`, `sync_manifest.dart`, `sync_engine.dart`, `migration_service.dart`, `backup_service.dart`, `backup_exporter.dart`, `js_backup_importer.dart`, `js_preset_importer.dart`, `js_lorebook_importer.dart`, `js_api_config_importer.dart`, `service_prefs_writer.dart`, `gdrive_auth.dart`, `dropbox_auth.dart`, `janny_provider.dart`, `datacat_provider.dart`

## Phase 2: Data Safety Fixes (medium risk, critical)

- [x] 2.1 Await all `chatRepo.put()` calls in `chat_generation_service.dart`, `chat_message_service.dart`
- [x] 2.2 Remove silent `catch (_) {}` — add logging in `chat_session_service.dart`
- [x] 2.3 SSE stream `onError` → call `onError?.call(e)` in `sse_client.dart`
- [x] 2.4 Static `_cache` → LRU or Provider-scoped cache in `chat_session_service.dart`
- [ ] 2.5 UI→DB violations: route through providers (17 widget files — see characterization tests)

### 2.5 Detail — Violation Inventory

| Widget file | Repo(s) called | Methods |
|---|---|---|
| `magic_drawer.dart` | chatRepo | `.delete()`, `.getById()`, `.put()` |
| `summary_sheet.dart` | chatRepo | `.put()` |
| `authors_note_sheet.dart` | chatRepo | `.put()` |
| `chat_stats_sheet.dart` | characterRepo, chatRepo | `.getAll()`, `.getAllSessions()` |
| `lorebook_coverage_sheet.dart` | characterRepo, lorebookRepo | `.getById()`, `.getAll()` |
| `context_info_sheet.dart` | lorebookRepo | `.getAll()` |
| `chat_dialogs.dart` | presetRepo, personaRepo | `.getAll()` |
| `memory_books_sheet.dart` | memoryBookRepo | `.ensureForSession()`, `.put()` |
| `regex_list_screen.dart` | presetRepo | `.getAll()`, `.put()` |
| `persona_list_screen.dart` | personaRepo | `.put()` |
| `persona_connections_sheet.dart` | personaRepo, chatRepo | `.getAll()`, `.getAllSessions()` |
| `character_editor_screen.dart` | characterRepo | `.getById()`, `.put()` |
| `character_detail_screen.dart` | characterRepo, chatRepo | `.getById()`, `.getByCharacterId()` |
| `character_list_screen.dart` | lorebookRepo | `.put()` |
| `tools_screen.dart` | personaRepo, presetRepo | `.getById()` |
| `preset_editor_screen.dart` | presetRepo | `.put()` |
| `picks_detail_launcher.dart` | lorebookRepo | `.put()` |

**Strategy:** 
- Reads → `AsyncNotifierProvider` (watchable, cached)
- Mutations → `FutureProvider` or dedicated Notifier methods
- Keep repo import only in provider layer

## Phase 3: WebView Bridge Decomposition (high risk, high ROI)

- [x] 3.1 Extract `InteractionDispatch` — 270-line click handler → action map with `data-action`
- [x] 3.2 Extract `SelectionManager` — selection bar + selection mode state
- [x] 3.3 Extract `EditController` — startEdit/stopEdit + textarea events
- [x] 3.4 Extract `SwipeGestureHandler` — swipe gestures, swipe context helper
- [x] 3.5 Extract `GenTimer` — start/stop gen timer
- [x] 3.6 Normalize `renderMessage` — always return array, remove 4× duplication
- [x] 3.7 `renderer._selectionMode` → public API getter (encapsulation)

## Phase 4: WebView Streaming Optimization (high risk)

- [x] 4.1 `updateMessageContent` patch instead of rebuild — patch `shadowRoot.querySelector('.glaze-message').innerHTML` for text-only chunks
- [ ] 4.2 Batch Flutter→WebView messages — collect chunks in `requestAnimationFrame`
- [x] 4.3 `_createGenStat` — single function, remove 4× DOM construction duplication
- [ ] 4.4 Reduce `ChatWebViewWidget` callback props (22→~10) — group into typed callback objects

## Phase 5: God Object Decomposition (high risk)

- [ ] 5.1 `ChatNotifier` (1127 lines) → extract `AbortHandler` + `ImageRecoveryService`
- [ ] 5.2 `ChatScreen` (1289 lines) → `ChatDrawerController` + `ChatSearchDelegate` + `ChatBody`
- [ ] 5.3 `ChatActionsService`: `WidgetRef` → `Ref` + context param
- [ ] 5.4 `ChatGenerationService` → Riverpod provider instead of inline creation
- [ ] 5.5 God widgets: split SyncSheet, ThemeEditor, PresetEditor, BottomSheet into sections

## Phase 6: ImgGen Utility Consolidation

- [ ] 6.1 Extract `_replaceFirstImgErrorOrGen` + `_resetImgTagsToGen` → `ImgTagRecoveryService`
- [ ] 6.2 Move `_stripThinkTags` from `ChatBridgeController` → shared utility
- [ ] 6.3 Unify ChatMessage ↔ JS map conversion in `ChatMessageMapper`

---

## Phase 7: Tokenizer Accuracy (medium risk)

- [ ] 7.1 Add `o200k_base` encoding support via custom `Tiktoken` constructor — download vocab from `https://openaipublic.blob.core.windows.net/encodings/o200k_base.tiktoken` (~2MB), cache locally, load into existing `tiktoken` Dart package using `Tiktoken(name, patStr, mergeableRanks, specialTokens)`
- [ ] 7.2 Model-aware encoding selector — map model name → encoding (`cl100k_base` for GPT-4/3.5, `o200k_base` for GPT-4o/4.1/5.x, heuristic multiplier for Claude/other providers)
- [ ] 7.3 Heuristic multiplier fallback for non-OpenAI models — Claude: `×0.69`, Gemini/Mistral: `×0.7` (approximate, no local tokenizer available)
- [ ] 7.4 Replace `estimateTokens()` global with `estimateTokens(text, {modelEncoding})` — encoding selection based on current `ApiConfig.model`

**Context:** `cl100k_base` overestimates by ~45% for both Claude (113k vs 78k actual) and GPT-5.4 (~113k vs 71k). The Dart `tiktoken` 1.0.3 package does not support `o200k_base` natively, but allows extending via constructor. JS Glaze uses `gpt-tokenizer` (cl100k_base only) — same problem exists there too.

---

## Progress Log

| Date | Phase | Task | Status |
|------|-------|------|--------|
| 2026-05-25 | — | Plan created | Done |
| 2026-05-25 | 1.1 | IMG regex → ImgGenPatterns | Done |
| 2026-05-25 | 1.3 | Token estimation → estimateTokens() | Done |
| 2026-05-25 | 1.4 | Remove dead resetLoadingTags | Done |
| 2026-05-25 | 1.5 | _messagePreview type fix | Done |
| 2026-05-25 | 2.1 | Unawaited put() → _persistSession with error logging | Done |
| 2026-05-25 | 2.2 | Silent catch → debugPrint logging | Done |
| 2026-05-25 | 2.3 | SSE stream onError → completeError | Done |
| 2026-05-25 | 2.4 | Static cache → LRU eviction (max 20) | Done |
| 2026-05-25 | 3.1 | InteractionDispatch extraction | Done |
| 2026-05-25 | 3.5 | GenTimer extraction | Done |
| 2026-05-25 | 3.6 | renderMessage always returns array | Done |
| 2026-05-25 | 3.7 | _selectionMode → public getter | Done |
| 2026-05-25 | 4.1 | Streaming fast path patch | Done |
| 2026-05-25 | 4.3 | _createGenStat dedup | Done |
| 2026-05-25 | 0.1–0.5 | Characterization tests (125 tests, 4 files) | Done |
| 2026-05-25 | 1.2 | SharedPrefsProvider — 30 files migrated | Done |
| 2026-05-25 | docs | Rewrote ARCHITECTURE.md, INVARIANTS.md, rules/generation.md, rules/database.md, markdown-markers.md, rules/race-conditions.md | Done |
| 2026-05-25 | 3.2 | SelectionManager extraction from bridge.js + renderer.js | Done |
| 2026-05-25 | 3.3 | EditController extraction from bridge.js | Done |
| 2026-05-25 | 3.4 | SwipeGestureHandler extraction from bridge.js | Done |
| 2026-05-25 | merge | Upstream/master 3ab55fc merged — noise overlay, contextmenu handoff, isEditing class | Done |
| 2026-05-25 | merge | Upstream/master 8c38b6e merged — reasoning block hiding fix, editing guard in SelectionManager | Done |
| 2026-05-25 | 4.2 | MessageUpdateBatcher — coalesce updateMessage calls via requestAnimationFrame, flush before structural ops (15 characterization tests) | Done |
