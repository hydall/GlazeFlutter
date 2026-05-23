# Glaze WebView Migration — Anchored Summary

**Last updated:** 2026-05-21

## Project Status
**Branch:** `feat/webview-migration`  
**Remote:** `origin/feat/webview-migration` (up to date)  
**Latest commits:**
- `5cc655f` — docs: обновить чеклист миграции — отметить завершенные фазы A, B, C
- `de82c5e` — feat: Phase C — интеграция ChatWebView в экран чата
- `26d80b8` — feat: добавлен Phase A - JS bundle и Flutter интеграция для единого WebView

**Progress:** Phases A, B, C completed (26/30 checklist items)

## Architecture Overview

### Current State
- ✅ **JS bundle** (`assets/chat_webview/`): 6 files (index.html, bridge.js, renderer.js, virtual_list.js, formatter.js, styles.css)
- ✅ **Dart bridge** (`lib/features/chat/bridge/chat_bridge_controller.dart`): Full bidirectional communication
- ✅ **Widget integration**: `ChatWebViewWidget` replaces `MessageList` in `chat_screen.dart`
- ⏳ **Theme integration**: Basic `applyTheme()` exists, CSS variables not fully wired
- ⏳ **Search**: Basic `setSearch()` exists, highlighting logic incomplete
- ❌ **Message actions**: Swipe, edit, delete not yet connected
- ❌ **Pagination**: Basic structure exists, needs testing

### Key Components

#### JS Side (assets/chat_webview/)
- **Bridge class** (`bridge.js`): Handles Flutter↔JS communication
  - Methods: `setMessages()`, `appendMessage()`, `prependMessages()`, `updateMessage()`, `removeMessage()`, `clearAll()`, `updateStreaming()`, `applyTheme()`, `scrollToBottom()`, `scrollToMessage()`, `setSearch()`
  - Communication: `window.flutter_inappwebview.callHandler()`
- **Renderer** (`renderer.js`): Renders messages with Shadow DOM isolation
- **VirtualList** (`virtual_list.js`): Message container management (no virtualization yet)
- **Formatter** (`formatter.js`): Markdown/quote formatting

#### Dart Side
- **ChatBridgeController** (`lib/features/chat/bridge/chat_bridge_controller.dart`):
  - 134 lines, handles JSON serialization, CSS variable generation
  - Key methods mirror JS side + theme conversion (Color → CSS hex)
- **ChatWebViewWidget** (`lib/features/chat/widgets/chat_webview_widget.dart`):
  - 181 lines, ConsumerStatefulWidget
  - Core logic in `_syncMessages()` — diffs old vs new messages, sends minimal updates
  - Streaming handled via `ref.listen<StreamingState>()`
  - Theme applied in `_onReady()` with CSS variables

## Completed Tasks

### Phase A — JS Bundle ✅
- [x] A.1: Created `assets/chat_webview/`, added to pubspec.yaml
- [x] A.2: Ported `formatter.js` with quote detection, markdown parsing
- [x] A.3: Built `renderer.js` with Shadow DOM and custom HTML markers
- [x] A.4: Built `virtual_list.js` (basic, no virtualization)
- [x] A.5: Built `bridge.js` with bidirectional communication
- [x] A.6: Created `styles.css` with chat theming
- [x] A.7: Created `index.html` with asset loading

### Phase B — Dart Bridge ✅
- [x] B.1: Built `ChatWebViewWidget` as ConsumerStatefulWidget
- [x] B.2: Built `ChatBridgeController` with JSON serialization
- [x] B.3: Created `MessageDto` (unused — using `ChatMessage` directly)
- [x] B.4: ~~ChatWebViewNotifier~~ — deleted, logic moved to widget

### Phase C — Integration ✅
- [x] C.1: Replaced `MessageList` with `ChatWebViewWidget` in chat_screen.dart
- [x] C.2: Connected streaming via `ref.listen<StreamingState>()`
- [x] C.3: Basic pagination logic (needs testing)
- [ ] C.4: Message actions (swipe, edit, delete) — not yet connected
- [ ] C.5: Selection mode — not yet implemented

## Next Steps (Priority Order)

### 1. Testing (Critical)
**Goal:** Verify basic functionality works before adding more features.
- [ ] Run `flutter run` and open a chat
- [ ] Verify messages render in WebView
- [ ] Send a message and check it appears
- [ ] Test streaming during generation
- [ ] Check theme colors apply correctly
- [ ] Test scrolling behavior

### 2. Phase D — Theme Integration
**Goal:** Full theme support with dynamic updates.
- [ ] D.1: Wire CSS variables for message bubbles (user-bg, assistant-bg)
- [ ] D.2: Add CSS variables to Shadow DOM `:host` context
- [ ] D.3: Listen to `ThemeProvider` and call `bridge.applyTheme()` on changes
- [ ] Test with multiple themes

### 3. Phase E — Search
**Goal:** Search and highlight functionality in WebView.
- [ ] E.1: Implement `highlightSearch()` in renderer.js via Shadow DOM traversal
- [ ] E.2: Add `scrollIntoView()` for active match
- [ ] E.3: Remove `_highlightPhrases()` from Dart after migration verified
- [ ] Test with various search queries

### 4. Message Actions
**Goal:** Restore message interaction features.
- [ ] Connect swipe gestures (JS events → Flutter bridge)
- [ ] Connect edit action (modal/inline editing)
- [ ] Connect delete action (confirmation + API call)
- [ ] Connect regeneration (last assistant message)

### 5. Performance Optimization
**Goal:** Handle large chats efficiently.
- [ ] Implement virtual scrolling in VirtualList
- [ ] Add message recycling (reuse DOM nodes)
- [ ] Batch DOM updates during pagination
- [ ] Profile memory usage with 1000+ messages

### 6. Cleanup
**Goal:** Remove legacy code after all features work.
- [ ] Delete `message_list.dart` (replaced)
- [ ] Delete `html_block_view.dart` (no longer needed)
- [ ] Remove `GptMarkdown` rendering path from `message.dart`
- [ ] Update `HTML_RENDERING_PLAN.md` to mark phases 3+ obsolete

## Technical Notes

### Communication Pattern
```
Flutter → JS: evaluateJavascript('window.glazeBridge.methodName(json)')
JS → Flutter: window.flutter_inappwebview.callHandler('handlerName', args)
```

### Message Sync Logic
- On first load: `setMessages()` sends all messages
- On subsequent updates: `_syncMessages()` diffs old vs new, sends only changes
- Streaming: Separate path via `updateStreaming()` to avoid re-rendering full list
- Pagination: `prependMessages()` when loading older messages

### Theme System
- CSS variables defined in `styles.css` and applied via `:root`
- Shadow DOM inherits variables through `:host` context
- Flutter converts `Color` to CSS hex in `ChatBridgeController._convertColor()`
- Theme applied on WebView ready, updated on theme changes

### File Locations
- **Plan:** `docs/WEBVIEW_MIGRATION_PLAN.md`
- **JS files:** `assets/chat_webview/`
- **Dart files:** `lib/features/chat/bridge/`, `lib/features/chat/widgets/`
- **Chat screen:** `lib/features/chat/chat_screen.dart` (line ~520-540)

## Known Issues
1. **Pagination not tested** — basic logic exists but unverified
2. **Theme CSS variables incomplete** — only basic colors wired
3. **Search highlighting incomplete** — basic structure, no DOM traversal
4. **Message actions not connected** — swipe/edit/delete disabled
5. **Background image not handled** — old MessageList supported it
6. **Code block styling minimal** — needs enhancement
7. **Virtual scrolling not implemented** — performance risk for large chats

## Git Commands
```bash
# Current branch
git checkout feat/webview-migration

# Pull latest
git pull origin feat/webview-migration

# After making changes
git add .
git commit -m "feat: description"
git push origin feat/webview-migration

# Create PR (when ready)
gh pr create --repo hydall/GlazeFlutter --base master --head danvitv:feat/webview-migration
```

## References
- Original plan: `docs/WEBVIEW_MIGRATION_PLAN.md`
- HTML rendering investigation: `docs/HTML_RENDERING_PLAN.md`
- Glaze JS reference: `/c/Users/Даниил/Glaze project/glaze/src/utils/textFormatter.js`
- Tavo architecture notes: `/tmp/tavo_analysis.md`
