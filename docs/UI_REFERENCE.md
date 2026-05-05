# Glaze JS → Flutter UI Reference

Source: [hydall/Glaze](https://github.com/hydall/Glaze) (Vue 3 + Capacitor)
Analysis date: 2026-05-05

---

## Navigation Model

**Mobile**: Bottom tab bar (3 tabs) → full-screen views
**Desktop**: Left sidebar (dialog list + nav) + main content + right sidebar (Magic Drawer)

Flutter uses **bottom nav + GoRouter**. Desktop layout is Phase 6.

---

## Bottom Navigation Tabs

| Tab | Icon | View ID | Flutter Route | Status |
|-----|------|---------|---------------|--------|
| Chats | chat_bubble | view-dialogs | `/` | Done |
| Characters | person | view-characters | `/characters` | Done |
| Menu | more_horiz | view-menu | `/menu` | Done |

---

## Complete Screen Inventory

### 1. Chat History (`view-dialogs`)

**Route**: `/`
**What it shows**: List of chat sessions sorted by last message time
**Each item**: avatar, character name, last message preview, timestamp, message count badge

**Actions**:
- Tap session → `/chat/:charId`
- FAB "New Chat" → character picker → `/chat/:charId`
- Long-press session → delete, rename (TODO)

**Flutter file**: `features/chat_history/chat_history_screen.dart`

---

### 2. Character List (`view-characters`)

**Route**: `/characters`
**What it shows**: Grid of character cards (2:3 ratio)
**Each card**: avatar/thumbnail, name, description preview, favorite heart, token badge

**Actions**:
- Tap card → CharacterDetailSheet (bottom sheet with full card info + "Start Chat" button)
- "..." menu on card → Edit, Duplicate, Delete, Favorite, Export
- "+" FAB → Import (PNG/JSON/CHARX)
- Sort toggle (asc/desc) + sort type (Name/Date)

**Sub-tabs**: "My Characters" | "Catalog" (Catalog = Phase 7)

**Flutter file**: `features/character_list/character_list_screen.dart`

---

### 3. Menu Hub (`view-menu`)

**Route**: `/menu`

**Sections & items**:

| Section | Item | Icon | Target |
|---------|------|------|--------|
| Settings | Tools | build | `/tools` |
| Settings | App Settings | settings | `/settings` |
| Settings | Theme | palette | `/settings/theme` |
| Data | Cloud Sync | cloud | SyncSheet (Phase 5) |
| Data | Backups | backup | BackupSheet (Phase 6) |
| Info | About | info | AboutDialog |

**Flutter file**: `features/menu/menu_screen.dart`

---

### 4. Tools Hub (`view-tools`)

**Route**: `/tools`
**Grid of tool cards**:

| Tool | Icon | Target | Status |
|------|------|--------|--------|
| Presets | tune | `/tools/presets` | Repo done, UI TODO |
| API | api | `/tools/api` | Done |
| Lorebooks | menu_book | `/tools/lorebooks` | Repo done, UI TODO |
| Regex | code | `/tools/regex` | TODO |
| Personas | face | `/tools/personas` | Done |
| Glossary | help | `/tools/glossary` | TODO |

**Flutter file**: `features/tools/tools_screen.dart` (TODO)

---

### 5. Chat View (`view-chat`)

**Route**: `/chat/:charId`
**The primary screen of the app**

**Header**:
- Back button
- Character name + avatar (tappable → CharacterDetailSheet)
- ⚠ Stop button (while generating)
- ℹ Info button → `/character/:charId`
- "..." overflow menu:
  - Edit character → `/character/:charId/edit`
  - Change session → SessionPickerSheet
  - Sessions manager → `/chat/:charId/sessions`
  - Author's Note → AuthorsNoteSheet
  - Presets → `/tools/presets`
  - API settings → `/tools/api`
  - Regenerate last
  - Delete last message
  - Clear chat
  - Export chat

**Message list**:
- User messages (right-aligned, accent bubble)
- Character messages (left-aligned, dark bubble)
- Streaming indicator (typing dots)
- Reasoning block (collapsible, gray background)
- Swipe left/right on character messages for variant swipes

**Message long-press**:
- Edit message
- Delete message
- Copy message
- Regenerate (character messages only)
- Swipe navigation (1/3, 2/3)

**Input area**:
- Text field (multiline, send on Enter if setting enabled)
- Send/Stop button
- Image attachment button (TODO)

**Magic Drawer** (swipe up from input bar):
- Author's Note, Context, Summary, Sessions, Chat Stats
- Impersonate, Character Card, API, Presets, Lorebooks, Regex
- Image Gen, Glossary, Request Preview

**Flutter file**: `features/chat/chat_screen.dart`

---

### 6. Character Detail (`CharacterCardSheet`)

**Route**: `/character/:charId`
**Shows as bottom sheet in JS, full screen in Flutter**

**Content**:
- Large avatar (96px)
- Name, creator
- Tags (chip row)
- Description, Personality, Scenario, First Message, Example Dialogue, System Prompt, Creator Notes (each collapsible section)

**Actions**:
- "Start Chat" button → `/chat/:charId`
- "Edit" button → `/character/:charId/edit`
- "Favorite" toggle
- Close

**Flutter file**: `features/character_list/character_detail_screen.dart`

---

### 7. Character Editor (`view-character-edit`)

**Route**: `/character/:charId/edit`

**Fields**:
| Field | Type | Notes |
|-------|------|-------|
| Avatar | Image picker | Upload or change |
| Name | Text | Required |
| Description | Textarea | Expandable to full-screen editor |
| Personality | Textarea | Expandable |
| Scenario | Textarea | Expandable |
| First Message | Textarea | Expandable |
| Message Example | Textarea | Expandable |
| Creator Notes | Textarea | Expandable |
| System Prompt | Textarea | Expandable |
| Post-History Instructions | Textarea | Expandable |
| Tags | Comma-separated | |
| Creator | Text | |

**Actions**: Save, Delete, Back

**Flutter file**: `features/character_list/character_editor_screen.dart` (TODO)

---

### 8. Persona Manager (`view-personas`)

**Route**: `/tools/personas`

**Shows**: List of personas with avatar, name, prompt preview
**Active persona** highlighted with connection badge (global/character/chat)

**Actions**:
- Tap persona → set as active
- Connection button (colored: green=global, purple=character, orange=chat) → ConnectionsSheet
- Edit button → Persona Editor
- "Add Persona" FAB → Persona Editor (empty)

**Flutter file**: `features/personas/persona_list_screen.dart`

---

### 9. Persona Editor (`view-persona-edit`)

**Route**: `/tools/personas/:id/edit`

**Fields**:
| Field | Type |
|-------|------|
| Avatar | Image picker |
| Name | Text |
| Description | Textarea |
| Persona Prompt | Textarea |

**Flutter file**: Part of `persona_list_screen.dart` (inline editor)

---

### 10. API Configuration (`view-api`)

**Route**: `/tools/api`

**Shows**: List of configured API endpoints
**Each endpoint**: Name, provider, endpoint URL, model, active indicator

**Actions**:
- Add new endpoint
- Edit endpoint (name, URL, API key, model, max tokens, context size, temperature, top P, stream, reasoning)
- Delete endpoint
- Test connection
- Set active

**Flutter file**: `features/settings/api_settings_screen.dart`

---

### 11. Preset Manager (`view-presets`)

**Route**: `/tools/presets`

**Shows**: List of generation presets
**Each preset**: Name, parameter summary

**Actions**:
- Add new preset
- Edit preset blocks (role, content, depth, enabled, insertion mode)
- Edit preset regex scripts
- Duplicate, Delete
- Import/Export (SillyTavern JSON)
- Set active preset

**Flutter file**: `features/presets/preset_list_screen.dart` (TODO)

---

### 12. Lorebook Manager (`view-lorebook`)

**Route**: `/tools/lorebooks`

**Shows**: List of lorebooks
**Each lorebook**: Name, entry count, linked characters

**Actions**:
- Add lorebook
- Edit entries (keys, content, position, enabled, constant, priority)
- Delete lorebook
- Link to character/chat

**Flutter file**: `features/lorebooks/lorebook_list_screen.dart` (TODO)

---

### 13. Regex Manager (`view-regex`)

**Route**: `/tools/regex`

**Shows**: List of regex scripts
**Each script**: Name, find pattern, replace pattern, enabled toggle

**Flutter file**: TODO

---

### 14. App Settings (`view-settings`)

**Route**: `/settings`

**Items**:
| Setting | Type | Default |
|---------|------|---------|
| Enter to Send | Toggle | true |
| Battery Saver UI | Toggle | false |
| Group Dialogs | Toggle | false |
| Hide Tooltips | Toggle | false |
| Disable Swipe Regeneration | Toggle | false |
| Hide Message ID | Toggle | false |
| Hide Gen Time | Toggle | false |
| Hide Token Count | Toggle | false |
| Chat Layout | Selector (Default/Bubbles) | default |
| Language | Selector (EN/RU) | en |

**Flutter file**: `features/settings/app_settings_screen.dart` (TODO)

---

### 15. Theme Settings (`view-theme-settings`)

**Route**: `/settings/theme`
**Tabs**: General | Chat

**General tab**: Accent color, font, text color, font size, letter spacing, UI opacity/blur, border settings, noise texture, background image

**Chat tab**: Chat font, font size, bubble colors (user/char), reply colors, text colors, italic colors, live preview

**Flutter file**: `features/settings/theme_settings_screen.dart` (TODO — Phase 6)

---

### 16. Onboarding (`OnboardingView`)

**Shown**: First launch only
**Steps**: Welcome → API Setup → Import Character → Tutorial

**Flutter file**: `features/onboarding/onboarding_screen.dart` (TODO — Phase 6)

---

## Route Map (Flutter GoRouter)

```
/                           → ChatHistoryScreen (tab: Chats)
/characters                 → CharacterListScreen (tab: Characters)
/menu                       → MenuScreen (tab: Menu)
/chat/:charId               → ChatScreen
/character/:charId          → CharacterDetailScreen
/character/:charId/edit     → CharacterEditorScreen (TODO)
/tools                      → ToolsScreen (TODO)
/tools/api                  → ApiSettingsScreen
/tools/presets              → PresetListScreen (TODO)
/tools/lorebooks            → LorebookListScreen (TODO)
/tools/regex                → RegexListScreen (TODO)
/tools/personas             → PersonaListScreen
/tools/glossary             → GlossaryScreen (TODO)
/settings                   → AppSettingsScreen (TODO)
/settings/theme             → ThemeSettingsScreen (TODO — Phase 6)
```

---

## Status Tracker

| Screen | Route | UI | Logic | Notes |
|--------|-------|:--:|:-----:|-------|
| Chat History | `/` | ✅ | ✅ | |
| Character List | `/characters` | ✅ | ✅ | Grid cards + sort + FAB |
| Menu | `/menu` | ✅ | ✅ | |
| Chat | `/chat/:charId` | ✅ | ✅ | Context menu TODO |
| Character Detail | `/character/:charId` | ✅ | ✅ | |
| Character Editor | `/character/:charId/edit` | ❌ | ❌ | |
| Tools Hub | `/tools` | ✅ | ✅ | |
| API Settings | `/tools/api` | ✅ | ✅ | |
| Presets | `/tools/presets` | ❌ | ✅ | Repo done |
| Lorebooks | `/tools/lorebooks` | ❌ | ✅ | Repo done |
| Regex | `/tools/regex` | ❌ | ❌ | |
| Personas | `/tools/personas` | ✅ | ✅ | |
| App Settings | `/settings` | ✅ | ✅ | SharedPreferences |
| Glossary | `/tools/glossary` | ❌ | ❌ | |
| Theme Settings | `/settings/theme` | ❌ | ❌ | Phase 6 |
| Onboarding | overlay | ❌ | ❌ | Phase 6 |
