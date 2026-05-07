# JS Backup Import — Missing Features

Features present in Glaze JS backups but not yet implemented in Flutter.
Data from these fields is lost on import.

## High Priority (core functionality)

- [ ] **Lorebook per-book settings** — `gz_lorebooks[].settings`
  - 25+ fields: scanDepth, maxInjectedEntries, contextPercent, budgetCap, reserveMode, reserveValue, insertionStrategy, injectionPosition, vectorSearchEnabled, vectorThreshold, vectorTopK, keywordVectorSplit, vectorScanDepth, keySearchEnabled, etc.
  - Need: `settingsJson` column in `lorebooks` table, UI to edit, engine to read
  - Import already extracts global settings, but per-book overrides are lost

- [ ] **Authors Notes** — `gz_chat_{id}.authorsNotes`
  - Per-chat author notes injected into prompt
  - Need: column in `chat_sessions` or separate table, UI, prompt injection

- [ ] **Chat currentId** — `gz_chat_{id}.currentId`
  - Tracks which session tab is active for a character
  - Need: state management, UI tab switching

- [ ] **Character extensions** — `characters[].extensions`
  - Contains: talkativeness, fav, world, depth_prompt, gallery (legacy)
  - Need: `extensionsJson` column in `characters`, UI for each extension

- [ ] **Message metadata** — in chat messages
  - `greetingIndex` — which alternate greeting was used
  - `contextRefs` — lorebook entries that were active for this message
  - `memoryCoverage` — memory book coverage info
  - `swipeDirection` — last swipe direction
  - `isEditing` — message is being edited
  - Need: fields in message model

## Medium Priority

- [ ] **Chat drafts** — `gz_chat_{id}.draft`
  - Unsent message text preserved across sessions
  - Need: column in `chat_sessions`, auto-save on input

- [ ] **Scroll position** — `gz_chat_{id}.lastScrollAnchor`
  - Remember scroll position per chat
  - Need: column in `chat_sessions`, scroll controller persistence

- [ ] **character_version** — `characters[].character_version`
  - Version string for the character card format
  - Need: column in `characters`

- [ ] **thumbnail / mini_thumbnail** — `characters[].thumbnail`
  - Optimized thumbnails for character lists
  - Need: image storage, lazy generation

- [ ] **Lorebook description** — `gz_lorebooks[].description`
  - Need: column in `lorebooks`

- [ ] **Global variables** — `gz_global_vars`, `gz_vars_{chatId}_{sessionIdx}`
  - Macro system variables ({{var::name}})
  - Need: variable storage, macro engine support

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
