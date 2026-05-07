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

## High Priority (core functionality)

- [ ] **Memory settings (global)** — `gz_memory_settings`
  - Imported to SharedPreferences but no UI/provider reads it yet
  - Fields: enabled, autoCreateEnabled, autoGenerateEnabled, maxInjectedEntries, autoCreateInterval, useDelayedAutomation, injectionTarget, batchSize, vectorSearchEnabled, keyMatchMode, generationSource, generationModel, generationEndpoint, generationApiKey, generationTemperature, generationMaxTokens, promptPreset, customPrompts

## Low Priority (nice to have)

- [ ] **Chat stats** — `gz_stat_*`
  - Per-chat/char/global: message count, token count, regenerations, first_msg stats
  - Need: stats table, UI dashboard

- [ ] **Time tracking** — `gz_time_*`
  - Time spent per chat/character/app
  - Need: timer service, UI

- [ ] **Image generation config** — `gz_imggen_*`
  - Imported to SharedPreferences but no imggen service yet
  - Fields: api_type, api_key, endpoint, model, quality, aspect_ratio, image_size, image_context_enabled, image_context_count, additional_refs, routmy_*, naistera_*

- [ ] **Sync** — `gz_sync_*`
  - Cloud sync (Google Drive)
  - Device ID, tokens, manifest, deleted entries

- [ ] **Theme** — `gz_theme_*`
  - Custom themes: accent, bg, blur, opacity, font, presets
  - Partially implemented in Flutter
