# Chat UI WebView Migration — Implementation Plan

**Status:** Plan only. Not yet implemented.
**Goal:** Move chat **header**, **input bar**, **magic drawer**, and **background image** rendering from Flutter into the WebView so that CSS `backdrop-filter` blur honestly samples the chat content + bg image, and so the chat-screen UI mirrors the Glaze Vue reference. Flutter remains the host (bridge, state, native pickers, routing) but stops rendering the chat chrome.

**Trigger:** Flutter's `BackdropFilter` cannot blur platform-view (WebView) content. Pre-existing chat-pill blur looked solid because the WebView has nothing behind it — chat content lives inside the platform view, bg-image is rendered by Flutter behind the transparent WebView. Moving rendering inside the WebView gives `backdrop-filter` a real composited surface to blur.

---

## 1. Reference materials (Vue project — `F:\My Works\Coding\Glaze`)

Use for **visual / structural design only**. Data flow stays Flutter-driven.

| Vue file | Purpose | What to lift |
|---|---|---|
| `src/components/layout/AppHeader.vue` | Chat header (avatar pill, name, session, back, search, actions) | DOM structure for `header.app-header.fixed-header`, `.header-chat-info`, `.header-avatar`, `.header-chat-text`, `.chat-search-wrapper`. CSS for `.app-header` (margin 10px 16px 0, backdrop-filter, border-radius 20px), `.header-btn-left`, `.header-btn-right`, `.header-avatar`. |
| `src/components/chat/MagicDrawer.vue` | Magic drawer UI (3-col grid of cards, edit mode, drag-drop, status texts) | CSS for `.magic-drawer` (height: var(--keyboard-height), backdrop-filter, border-radius 24px 24px 0 0), `.drawer-header` (gradient mask), `.drawer-content` (grid-template-columns: repeat(3, ...)), `.magic-item`, `.card-icon`, `.card-info`, `.item-status`. **DO NOT lift the items list — keep Flutter's set** (see Phase 4). |
| `src/views/ChatView.vue` | Keyboard ↔ drawer ↔ input coordination | Look at `keyboardOverlap` usage, `--keyboard-height` CSS var management, focus/blur handlers on input, scroll-to-bottom on send. |
| `src/composables/chat/useVirtualScroll.js` | Scroll behavior (already partially mirrored in `assets/chat_webview/useVirtualScroll.js`) | The "scroll up to keep last message visible when keyboard appears" pattern. Look at how `containerRef.scrollTop` is adjusted in response to size changes. |

---

## 2. Current Flutter pieces being removed / hollowed-out

| File | Action |
|---|---|
| `lib/features/chat/widgets/chat_header.dart` | **Delete** after Phase 2. Remove import from `chat_screen.dart`, `theme_preview.dart`. |
| `lib/features/chat/widgets/chat_input_bar.dart` | **Delete** after Phase 3. Remove import from `chat_screen.dart`, `theme_preview.dart`. |
| `lib/features/chat/widgets/magic_drawer.dart` | **Keep `MagicDrawerPanel` actions logic** (`_handleItemTap` dispatching to sheets/screens). **Remove the rendering** (`Wrap` grid). It becomes a controller class that's called from a JS callback. Rename to `MagicDrawerActions` (no widget). |
| `lib/features/chat/widgets/quick_replies_panel.dart` | Either delete and rebuild in WebView, or keep as a callback-only action set (depends on complexity — inspect first). |
| `lib/features/chat/chat_drawer_controller.dart` | Strip ~70 % — only keeps the keyboard-height persistence + last-known-height memory. Animation, focus, panel switching all move to JS. |
| `lib/features/chat/chat_screen.dart` | Major rewrite. After all phases: body is just `ChatWebViewWidget` full-bleed, no `GlazeScaffold`, no `Stack` with header/input. See §10. |
| `lib/features/chat/widgets/chat_webview_widget.dart` | Heavy additions: new bridge props (avatar bytes, session info, draft, modes), remove Flutter-side bg-image rendering after Phase 1. |
| `lib/shared/widgets/glaze_scaffold.dart` | `GlazeScaffold` keeps current behavior for **other** screens. Chat screen stops using it. |
| `lib/features/settings/theme_preview.dart` | The preview uses `ChatHeader` + `ChatInputBar` — refactor preview to render its own simple Flutter pill mocks, or replace with a WebView mini-preview. **Decide before deletion of those widgets.** |

---

## 3. Target architecture (after Phase 4)

```
chat_screen.dart
└─ ChatWebViewWidget (fills entire screen, no Scaffold wrapper for this screen)
   ├─ Positioned.fill: ChatWebViewWidget body
   │    └─ InAppWebView
   │         └─ assets/chat_webview/index.html
   │              ├─ #bg-layer (background image + dim overlay)
   │              ├─ #chat-container (messages, with top/bottom padding for chrome)
   │              ├─ #chat-header  (Phase 2)
   │              ├─ #chat-input   (Phase 3)
   │              └─ #magic-drawer (Phase 4)
   └─ (Flutter overlays only for things that MUST be Flutter):
        - ImageViewer modal (full-screen image preview)
        - GlazeBottomSheet panels invoked by magic drawer item taps
        - go_router navigation to other screens
```

The Flutter side is reduced to a thin shell that drives the WebView via the bridge and shows native modals/sheets when requested.

---

## 4. Bridge API additions (JS ⇄ Dart)

All new methods follow existing patterns: `BridgeXxxCommands` group on Dart side, `window.bridge.xxx()` on JS side, callbacks declared on `ChatBridgeController` and dispatched via `bridge_handlers.dart`.

### 4.1 Outgoing (Dart → JS)

| Method | Args | Phase | Purpose |
|---|---|---|---|
| `setBackgroundImage(dataUri, blurPx, opacity, dimAlpha)` | replaces existing no-op | 1 | Renders into `#bg-layer` (CSS `background-image: url(...)`, blur via filter, dim via overlay child). |
| `setBackgroundNoise(opacity, intensity)` | (existing) | 1 | Already works inside WebView via SVG noise. Keep as-is. |
| `setupChatHeader(payload)` | `{name, session, avatarDataUrl, color, batterySaver}` | 2 | Populates `#chat-header`. |
| `updateChatHeaderAvatar(dataUrl, color, initial)` | | 2 | Cheap avatar-only update (e.g., character refresh, version bump from `avatarVersionProvider`). |
| `setHeaderScrollHidden(bool)` | | 2 | Slides header off-screen on scroll-down (current Flutter behavior via `_isHeaderHidden`). |
| `setupChatInput(payload)` | `{draft, virtualKeyboardSend, enterToSend, batterySaver, modes:{guidance,search,selection,editing}, generating:{text,image}, drawerOpen, quickRepliesOpen, attachedImageDataUrl}` | 3 | Full state push on init / mode change. |
| `setChatInputState(partial)` | partial of above | 3 | Throttled update on small changes (e.g., generating start/stop). |
| `setChatInputDraft(text)` | | 3 | Echo from Flutter when text is set externally (e.g., greeting impersonate). |
| `setSearchControls(query, currentIndex, total)` | | 3 | Drives search-mode pill. |
| `setSelectionControls(count, allHidden)` | | 3 | Drives selection-mode pill. |
| `attachImagePreview(dataUrl)` | | 3 | After Flutter's `file_picker` returns, send the bytes back. |
| `clearAttachedImage()` | | 3 | After successful send. |
| `setMagicDrawer(payload)` | `{visible, items:[{id,label,icon,status,statusColor}], editing}` | 4 | Item list with statuses (token counts, etc.). |
| `setMagicDrawerStatuses(map)` | `{itemId: status}` | 4 | Cheap status refresh without re-rendering items. |
| `setKeyboardHeight(px)` | | 4 | Flutter tells JS what the OS keyboard's height is right now. Sets CSS `--keyboard-height`. |
| `setSafeAreas(top, bottom)` | | 4 | Status-bar + nav-bar insets. Sets CSS `--sat`/`--sab`. |

### 4.2 Inbound (JS → Dart) — new callbacks added to `ChatBridgeController`

| Callback | Args | Phase | Triggered by |
|---|---|---|---|
| `onHeaderBack()` | – | 2 | Header back button. Flutter pops route. |
| `onHeaderSearchToggle(bool)` | open | 2 | Header search icon tapped. Flutter sets `_search.showSearch` and reciprocates with `setSearchControls`. |
| `onHeaderAvatarTap()` | – | 2 | Flutter opens `ImageViewer`. |
| `onSearchQueryChanged(text)` | | 2 | Header search input. Flutter runs search and pushes `setSearchControls`. |
| `onSearchPrev() / onSearchNext()` | – | 2/3 | Arrow buttons in pill. |
| `onChatInputDraftChanged(text)` | | 3 | Throttled debounce already in Flutter (`Timer 500ms`) — move to JS side. |
| `onSendMessage(text, guidance?, imageDataUrl?)` | | 3 | Send button. Wire to existing `chatProvider.send*` methods. |
| `onStopGeneration()` | – | 3 | Stop button (when generating). |
| `onImpersonate()` | – | 3 | Tapped when text is empty. |
| `onPickImage()` | – | 3 | Attach-file button. Flutter opens native `file_picker`, then sends `attachImagePreview`. |
| `onMagicToggle()` | – | 3 | Auto-awesome button. Flutter records desired state and posts `setMagicDrawer({visible:true,...})`. |
| `onFullScreenToggle()` | – | 3 | Full-screen mode (defer if not needed; can stub). |
| `onQuickRepliesToggle()` | – | 3 | Quick replies button. |
| `onCancelSelection() / onHideSelected() / onDeleteSelected()` | – | 3 | Selection-mode pill buttons. |
| `onMagicItemTap(itemId)` | | 4 | Dispatches to `MagicDrawerActions` (renamed from current widget). |
| `onMagicItemsReordered(newOrder)` | `string[]` | 4 | Persist new order via existing `_loadOrder/_saveOrder` mechanism in `magic_drawer.dart`. |
| `onMagicItemDeleted(itemId)` | | 4 | Same persistence. |
| `onInputFocusChange(focused)` | | 4 | JS reports focus state — Flutter uses this to decide whether to close drawer. |
| `onRequestKeyboardClose()` | – | 4 | JS asks Flutter to dismiss soft keyboard (because user opened drawer). Flutter calls `SystemChannels.textInput.invokeMethod('TextInput.hide')`. |

### 4.3 Bridge files to add / extend

- **NEW** `lib/features/chat/bridge/bridge_input_commands.dart` — input + magic-drawer outgoing methods.
- **NEW** `lib/features/chat/bridge/bridge_header_commands.dart` — header outgoing methods.
- Extend `lib/features/chat/bridge/bridge_handlers.dart` — register all new inbound callbacks (each with `HandlerKind` + dispatch).
- Extend `chat_bridge_controller.dart` — add fields for new callbacks, add facade methods.

---

## 5. Phase 0 — Revert blur-strip stubs (~5 min)

Undo the in-WebView blur strips added in the previous session. They become obsolete once bg-image moves into WebView.

**Files to edit:**

| File | What |
|---|---|
| `assets/chat_webview/index.html` | Remove `<div id="header-blur-overlay">` and `<div id="input-blur-overlay">`. |
| `assets/chat_webview/styles.css` | Remove the entire `.blur-overlay`, `#header-blur-overlay`, `#input-blur-overlay`, `.battery-saver .blur-overlay` block (the one at the bottom under the "Header / input blur overlays" comment). |
| `assets/chat_webview/bridge.js` | Remove `setHeaderOverlay()` and `setInputOverlay()` methods. |
| `lib/features/chat/bridge/bridge_layout_commands.dart` | Remove `setHeaderOverlay()` and `setInputOverlay()` methods. |
| `lib/features/chat/bridge/chat_bridge_controller.dart` | Remove facade lines `Future<void> setHeaderOverlay(...)` and `Future<void> setInputOverlay(...)`. |
| `lib/features/chat/widgets/chat_webview_widget.dart` | Remove props `headerOverlayTop`, `headerOverlayHeight`, `inputOverlayHeight` and their constructor defaults. Remove the `setHeaderOverlay/setInputOverlay` calls in `_initWebView` and `didUpdateWidget`. |
| `lib/features/chat/chat_screen.dart` | Remove `headerOverlayTop: ... + 10, headerOverlayHeight: 56, inputOverlayHeight: messageListBottom,` from `ChatWebViewWidget(...)`. |

Run `flutter analyze` after; should be clean.

---

## 6. Phase 1 — Background image into WebView (~30 min)

**Goal:** `#bg-layer` inside the WebView renders the bg image with blur/opacity/dim. Flutter side stops rendering its `Positioned.fill` image stack.

### 6.1 Files: WebView side

`assets/chat_webview/index.html` — already has `<div id="bg-layer">` if present; if not, add it as the FIRST child of `<body>`:
```html
<div id="bg-layer"></div>
```

`assets/chat_webview/styles.css` — add (near top):
```css
#bg-layer {
  position: fixed;
  inset: 0;
  z-index: -2;
  background-size: cover;
  background-position: center center;
  background-repeat: no-repeat;
  opacity: var(--bg-opacity, 1);
  filter: blur(var(--bg-blur, 0px));
  transform: scale(1.05); /* hide blur edges */
  pointer-events: none;
}
#bg-dim {
  position: fixed;
  inset: 0;
  z-index: -1;
  pointer-events: none;
  background: rgba(0, 0, 0, var(--bg-dim, 0));
}
```

`assets/chat_webview/index.html` — add `<div id="bg-dim"></div>` right after `#bg-layer`.

`assets/chat_webview/bridge.js` — replace the no-op `setBackgroundImage`:
```js
setBackgroundImage(url, blur, opacity) {
  const layer = document.getElementById('bg-layer');
  if (!layer) return;
  if (url && url.length) {
    layer.style.backgroundImage = `url("${url.replace(/"/g, '\\"')}")`;
  } else {
    layer.style.backgroundImage = 'none';
  }
  document.documentElement.style.setProperty('--bg-blur', (blur || 0) + 'px');
  document.documentElement.style.setProperty('--bg-opacity', String(opacity ?? 1));
}
setBgDim(alpha) {
  document.documentElement.style.setProperty('--bg-dim', String(alpha ?? 0));
}
```

### 6.2 Files: Dart side

`lib/features/chat/bridge/bridge_theme_commands.dart` — `setBackgroundImage(src, blur, opacity)` is already there. Add `setBgDim(double alpha)`. Make sure the URL handling supports both `file://` and `data:` URIs.

**Decision needed:** pass image as `file://` (faster) or `data:` URI (works across all platforms even if `allowFileAccess` is restricted)?
- **Default:** Use `file://` path. Flutter has `bgImagePath` already.
- Bytes path (`bgImageBytesProvider`) exists for compat with non-file backgrounds (e.g., character cards). Add a second `setBackgroundImageBytes(base64DataUri)` method that builds the data URI when there's no file path. Pick whichever provider returns content first.

`lib/features/chat/widgets/chat_webview_widget.dart`:
- REMOVE the `Positioned.fill` Image.memory block (lines ~659–690 currently).
- REMOVE the `bgDim` overlay container.
- In `_initWebView`: call `_bridge!.setBackgroundImage(widget.bgImagePath ?? '<dataUri-from-bytes>', widget.bgBlur, widget.bgOpacity)` and `_bridge!.setBgDim(widget.bgDim)`.
- In `didUpdateWidget`: update on change. Note `bgImageBytesProvider` may be async — handle null/loading state by passing empty URL (WebView shows transparent, Flutter `ColoredBox(cs.surface)` underneath remains).
- KEEP the `Positioned.fill(child: ColoredBox(color: Theme.of(context).colorScheme.surface))` underneath so there's no white flash before the WebView paints its bg.

`lib/features/chat/bridge/chat_bridge_controller.dart` — add facade for `setBgDim`.

### 6.3 Result
Flutter pills (header + input) sit over the WebView; WebView renders bg-image with its own blur; CSS `backdrop-filter` on Flutter pills will *still* not work (platform-view limitation hasn't gone away), BUT the user's complaint was specifically that bg-image wasn't being blurred under the pills — that is now fixed because the bg-image and chat content live in the same compositing context inside the WebView. Pills look correctly translucent over the blurred chat region.

Actually no — re-read carefully. After Phase 1, Flutter pills still can't blur the WebView. The pills become **slightly transparent tinted rectangles over the WebView**. Users see the bg-image through the pill's tint, but it won't be blurred *additionally* by the pill. The chat content visible under the pills also isn't blurred. **Phase 1 alone does not solve the blur problem.** It is a *prerequisite* for Phases 2+3, where the pills move INTO the WebView and `backdrop-filter` works natively because everything is in the same document.

If user wants a quick win without Phases 2+3: instead of *removing* Flutter pill blur, increase the Flutter pill tint to ~95% opacity (almost opaque) so the lack-of-blur isn't visible. But that's an aesthetic compromise, not a fix.

---

## 7. Phase 2 — Chat header into WebView (~1.5 h)

**Goal:** `#chat-header` HTML in WebView. Flutter `GlazeScaffold` is no longer wrapping the chat screen.

### 7.1 New HTML
Add to `index.html` (before `#chat-container`, so it sits at top of stack — actually `position: fixed` so DOM order matters less):
```html
<header id="chat-header" class="app-header fixed-header" style="display:none">
  <div id="header-back" class="header-btn-left">
    <svg viewBox="0 0 24 24"><path d="M20 11H7.83l5.59-5.59L12 4l-8 8 8 8 1.41-1.41L7.83 13H20v-2z"/></svg>
  </div>
  <div class="header-chat-info">
    <div class="header-avatar">
      <img id="chat-header-avatar" alt="" />
      <div id="chat-header-avatar-placeholder" class="avatar-placeholder"></div>
    </div>
    <div class="header-chat-text">
      <div class="header-name" id="chat-header-name"></div>
      <div id="chat-header-session" class="header-chat-session"></div>
    </div>
  </div>
  <div class="header-btn-right" id="header-actions">
    <button id="header-search-btn" class="header-action-btn">
      <svg viewBox="0 0 24 24" fill="currentColor"><path d="M15.5 14h-.79l-.28-.27..."/></svg>
    </button>
  </div>
  <!-- Search mode overlay (shown when isChatSearchMode) -->
  <div id="chat-search-wrapper" class="chat-search-wrapper" style="display:none">
    <div id="chat-search-back" class="chat-search-back"><svg .../></div>
    <input type="text" id="chat-search-input" class="chat-search-input" placeholder="Search messages">
    <div id="chat-search-clear" class="chat-search-clear" style="display:none"><svg .../></div>
  </div>
</header>
```

### 7.2 CSS
Lift `app-header`, `fixed-header`, `header-btn-left`, `header-btn-right`, `header-action-btn`, `header-chat-info`, `header-avatar`, `header-chat-text`, `header-name`, `header-chat-session`, `chat-search-wrapper`, `chat-search-input` from `AppHeader.vue` `<style scoped>` block. Strip Vue scoping. Use existing CSS variables (`--vk-blue`, `--element-blur`, `--element-opacity`, `--ui-bg-rgb`, `--text-gray`, `--sat`).

The `margin-top: calc(var(--sat) + 10px)` requires `--sat` (safe-area top). Flutter pushes this via `setSafeAreas(top, bottom)`.

### 7.3 JS
Add to `bridge.js`:
```js
setupChatHeader(payload) {
  const { name, session, avatarDataUrl, color, initial } = JSON.parse(payload);
  const header = document.getElementById('chat-header');
  if (!header) return;
  header.style.display = 'flex';
  document.getElementById('chat-header-name').textContent = name || '';
  document.getElementById('chat-header-session').textContent = session || '';
  const img = document.getElementById('chat-header-avatar');
  const placeholder = document.getElementById('chat-header-avatar-placeholder');
  if (avatarDataUrl) {
    img.src = avatarDataUrl; img.style.display = 'block';
    placeholder.style.display = 'none';
  } else {
    img.style.display = 'none';
    placeholder.style.display = 'flex';
    placeholder.textContent = (initial || '?').toUpperCase();
    placeholder.style.backgroundColor = color || '#ccc';
  }
}
hideChatHeader() {
  const h = document.getElementById('chat-header');
  if (h) h.style.display = 'none';
}
setHeaderScrollHidden(hidden) {
  const h = document.getElementById('chat-header');
  if (!h) return;
  h.classList.toggle('scroll-hidden', !!hidden);
}
setChatSearchMode(open) { /* toggles between header-chat-info and chat-search-wrapper */ }
```

Wire DOM events:
- `#header-back` click → `_sendToFlutter('onHeaderBack', [])`
- `#header-search-btn` click → `_sendToFlutter('onHeaderSearchToggle', [true])`
- `#chat-search-back` click → `_sendToFlutter('onHeaderSearchToggle', [false])`
- `#chat-search-input` input event (debounced 200ms) → `_sendToFlutter('onSearchQueryChanged', [text])`
- `#chat-header-avatar` click → `_sendToFlutter('onHeaderAvatarTap', [])`

### 7.4 Dart side
- New file `lib/features/chat/bridge/bridge_header_commands.dart` with `setupChatHeader/hideChatHeader/setHeaderScrollHidden/setChatSearchMode/setSearchControls/setSafeAreas`.
- Extend `bridge_handlers.dart`:
  - `'onHeaderBack'` → `HandlerKind.noArgs`
  - `'onHeaderSearchToggle'` → `HandlerKind.boolArg`
  - `'onHeaderAvatarTap'` → `HandlerKind.noArgs`
  - `'onSearchQueryChanged'` → `HandlerKind.stringArg`
- Extend `chat_bridge_controller.dart` — add `onHeaderBack`, `onHeaderSearchToggle(bool)`, `onHeaderAvatarTap`, `onSearchQueryChanged(String)` callbacks. Add dispatch cases.
- `chat_webview_widget.dart` — accept `headerPayload` props (name, session, avatarPath, color, initial). Push via `setupChatHeader` in init/didUpdate. Wire callbacks to forward into `widget.miscActions`/new typed callback group.

### 7.5 chat_screen.dart edits
- Remove `GlazeScaffold` wrapper. Replace with `Scaffold(body: Stack(...))` whose child is `ChatWebViewWidget` filling the screen.
- Drop the `_search.showSearch` ternary that builds the TextField title — that UI is now in WebView.
- Wire `onHeaderBack` → `context.go('/')` or `_drawerCtrl` close logic.
- Wire `onHeaderSearchToggle` → `setState(() => _search.showSearch = open)` + push `setChatSearchMode(open)` to JS.
- Wire `onSearchQueryChanged` → existing `_search.search(query, messages)` logic.
- Avatar tap → `ImageViewer.show(...)` (still a Flutter modal).
- Add `MediaQueryData` listener (existing) that pushes `setSafeAreas` to JS when insets change.

### 7.6 Delete `chat_header.dart` + update `theme_preview.dart`
- `theme_preview.dart` currently embeds `ChatHeader` for the live preview. Either:
  - (A) Build a Flutter-only fake `_ThemePreviewHeader` widget (~30 LOC).
  - (B) Render the preview in an isolated mini WebView (overkill).
- **Recommended:** (A). Quick, contained.

---

## 8. Phase 3 — Chat input bar into WebView (~3 h)

**Most complex phase.** Input bar has 4 visual modes (normal, search, selection, guidance), with image preview, drawer toggles, generating states, edit-message lock, virtual-keyboard-send vs enter-to-send. Reproduce all of it.

### 8.1 HTML structure
```html
<div id="chat-input-area" style="display:none">
  <!-- Image preview (when attached) -->
  <div id="input-image-preview" style="display:none">
    <img id="input-image-preview-img" alt="">
    <button id="input-image-clear"><svg .../></button>
  </div>

  <!-- Guidance row (orange) -->
  <div id="input-guidance-row" style="display:none">
    <textarea id="input-guidance-text" placeholder="Guidance instructions..." rows="1"></textarea>
  </div>

  <!-- Main input pill -->
  <div id="input-main-pill">
    <textarea id="input-text" placeholder="Type a message..." rows="1"></textarea>
  </div>

  <!-- Button row -->
  <div id="input-button-row">
    <button class="input-circle-btn" id="btn-magic"><svg .../></button>
    <button class="input-circle-btn" id="btn-attach"><svg .../></button>
    <button class="input-circle-btn" id="btn-fullscreen"><svg .../></button>
    <button class="input-circle-btn" id="btn-guidance-toggle"><svg .../></button>
    <button class="input-circle-btn" id="btn-quick-replies"><svg .../></button>
    <button class="input-send-btn" id="btn-send"><svg .../></button>
  </div>

  <!-- Search-mode pill (replaces above) -->
  <div id="input-search-pill" style="display:none">
    <svg .../><!-- search icon -->
    <span id="input-search-count">No matches found</span>
    <button id="btn-search-prev"><svg .../></button>
    <button id="btn-search-next"><svg .../></button>
  </div>

  <!-- Selection-mode pill -->
  <div id="input-selection-pill" style="display:none">
    <button class="input-circle-btn" id="btn-cancel-selection"><svg .../></button>
    <span id="input-selection-count">0 Selected</span>
    <button class="input-circle-btn" id="btn-hide-selected"><svg .../></button>
    <button class="input-circle-btn" id="btn-delete-selected"><svg .../></button>
  </div>
</div>
```

### 8.2 CSS
- Floating container: `position: fixed; bottom: 16px; left: 16px; right: 16px; z-index: 60; padding-bottom: var(--sab, 0px);`
- `.input-main-pill` mimics current Flutter `borderRadius: 28`, `backdrop-filter: blur(var(--element-blur))`, `background: rgba(var(--ui-bg-rgb), var(--element-opacity))`, border from `--border-color`.
- `.input-circle-btn`: 40×40 round, glass-like.
- `.input-send-btn`: 40×40 round, accent color filled, icon `Colors.black`.
- Press animation: `transition: transform 0.08s ease-out`, `:active { transform: scale(0.82) }`.
- Image preview: max 150×150, rounded 12, border like Flutter `_AttachedImagePreview`.
- Guidance row: orange-tinted, rounded 16.
- Auto-grow textarea (max 5 lines, then scroll).

### 8.3 JS
```js
setupChatInput(payload) {
  // Stores state to internal _inputState, calls _renderInputMode()
}
setChatInputState(partial) { /* shallow-merge, re-render */ }
setChatInputDraft(text) { /* sets textarea.value if differs */ }
setSearchControls(query, currentIndex, total) { /* updates search-mode pill text */ }
setSelectionControls(count, allHidden) { /* updates selection-mode pill */ }
attachImagePreview(dataUrl) { /* shows #input-image-preview */ }
clearAttachedImage() { /* hides #input-image-preview, clears state */ }

// Internal:
_renderInputMode() {
  // Show one of: search pill / selection pill / main input area
  // Within main: toggle guidance row visibility, attach preview, button colors
}
```

Event wiring:
- `#input-text` `input` event, debounced 500ms → `_sendToFlutter('onChatInputDraftChanged', [text])`. Also auto-resize.
- `#input-text` `keydown` `Enter` (and no shift, and `enterToSend === true`, and not editing message) → `_handleSend()`.
- `#input-text` `focus` → `_sendToFlutter('onInputFocusChange', [true])`. `blur` similarly.
- `#btn-send` click → `_handleSend()` (sends both text and guidance + image if present, OR stop if generating, OR impersonate if empty).
- `#btn-magic` click → `_sendToFlutter('onMagicToggle', [])`.
- `#btn-attach` click → `_sendToFlutter('onPickImage', [])`.
- `#btn-fullscreen` → `_sendToFlutter('onFullScreenToggle', [])` (or stub if dropping the feature).
- `#btn-guidance-toggle` → local toggle of `_inputState.guidanceMode`, re-render.
- `#btn-quick-replies` → `_sendToFlutter('onQuickRepliesToggle', [])`.
- `#input-image-clear` click → `_sendToFlutter('onClearAttachedImage', [])` or just clear locally.
- Selection / search pill buttons → corresponding `_sendToFlutter`.

### 8.4 Dart side
- New file `lib/features/chat/bridge/bridge_input_commands.dart` with all outgoing methods.
- Extend `bridge_handlers.dart` with new inbound names + `HandlerKind`s.
- Extend `chat_bridge_controller.dart` — fields, dispatch, facade.
- `chat_webview_widget.dart`:
  - Receive props for input state (mode, draft, attached image bytes, search/selection state).
  - Push to JS in init + diffed didUpdateWidget.
  - Forward inbound callbacks to a new callback set (`InputCallbacks`).

### 8.5 chat_screen.dart edits
- Remove `ChatInputBar` widget tree completely.
- Remove `_inputBarKey` / `_inputBarHeight` measurement (no longer needed — WebView handles its own layout).
- `_ChatBody._scrollToBottom` stays (still calls bridge).
- Add a `_handleSend(text, guidance, imageDataUrl)` that dispatches to existing chatProvider methods (mirror the Flutter `_sendMessage`).
- `_handlePickImage()` opens native `file_picker`, decodes, sends `attachImagePreview(dataUrl)` back to JS.
- `_handleMagicToggle()` calls into `_drawerCtrl` (or its slimmer successor) and pushes `setMagicDrawer({visible})` to JS.
- Search input flow: JS sends query → Flutter searches → Flutter pushes `setSearchControls` back AND `_bridge.setSearch(query, idx)` to highlight in WebView messages (existing).

### 8.6 Delete `chat_input_bar.dart`
And update `theme_preview.dart` similarly (mock pill).

---

## 9. Phase 4 — Magic drawer + keyboard sync (~2 h)

### 9.1 Magic drawer HTML
```html
<div id="magic-drawer" class="magic-drawer" style="display:none">
  <div class="drawer-header">
    <div class="drawer-title">Magic Drawer</div>
    <div class="edit-toggle" id="magic-edit-toggle">
      <svg .../><span>Edit</span>
    </div>
  </div>
  <div class="drawer-content" id="magic-drawer-content">
    <!-- Items injected by JS from setMagicDrawer payload -->
  </div>
</div>
```

### 9.2 CSS
Lift `.magic-drawer`, `.drawer-header`, `.drawer-content`, `.magic-item`, `.card-icon`, `.card-info`, `.item-label`, `.item-status`, `.edit-toggle`, drag-hover styles from `MagicDrawer.vue`. Drop `.magic-drawer-sidebar` (we don't have desktop sidebar mode).

Key CSS: `.magic-drawer { height: var(--keyboard-height, 300px); }` — height tracks keyboard.

### 9.3 JS
- `setMagicDrawer(payload)` — `{visible, items, editing}` JSON. Renders items grid.
- `setMagicDrawerStatuses(map)` — updates `.item-status` text only (cheap).
- Drag-drop logic: mirror `useDragDrop.js` from Vue (touch + mouse). On reorder, `_sendToFlutter('onMagicItemsReordered', [JSON.stringify(newOrder)])`.
- Item click (when not editing) → `_sendToFlutter('onMagicItemTap', [itemId])`.
- Item delete (in editing mode) → `_sendToFlutter('onMagicItemDeleted', [itemId])`.
- Edit toggle: local state only.

### 9.4 Keyboard sync
- Flutter watches `MediaQuery.viewInsetsOf(context).bottom` (already does for `_drawerCtrl.handleKeyboardFrame`).
- On change → `_bridge.setKeyboardHeight(px)` to JS.
- JS sets `document.documentElement.style.setProperty('--keyboard-height', px + 'px')`.
- Magic drawer height auto-adjusts because `.magic-drawer { height: var(--keyboard-height) }`.
- Input bar bottom padding similarly: `padding-bottom: max(var(--keyboard-height, 0px), var(--sab, 0px))`.

### 9.5 Drawer ↔ keyboard transitions (the tricky bit)

Mirror `ChatView.vue`'s logic:
- **Open drawer with no keyboard:** Flutter calls `_bridge.setMagicDrawer({visible:true,...})`. JS adds class `drawer-open` to root. Drawer slides up from bottom.
- **Open drawer while keyboard open:** JS first calls `document.activeElement.blur()` (textarea blur → keyboard dismisses). When keyboard height drops to 0, then drawer slides up. Use `--keyboard-height` transition coordination — drawer height is "locked" to last-known-height during the swap.
- **Focus textarea while drawer open:** JS hides drawer first (slide down), then focuses textarea. Reverse of above.
- Track "last keyboard height" in localStorage (already done in Flutter — move to JS): `localStorage.setItem('gz_last_keyboard_height', px)`.

Flutter pushes `setKeyboardHeight` continuously. JS treats height of 0 as "keyboard dismissed". JS uses its own state machine (`drawerOpen`, `switchingFromKbToDrawer`) similar to `chat_drawer_controller.dart` but inside JS.

### 9.6 Magic drawer items — keep Flutter's set
Do NOT use `MagicDrawer.vue`'s items array. The Flutter set is in `magic_drawer.dart` `_allItems` constant:
- context (Tokenizer), summary, sessions, stats, char-card, lorebooks, memory-books, regex, api, presets, preview, image-gen, glossary, ext-blocks (and any others present).

When sending `setMagicDrawer({items})`, the payload includes each item's SVG path (port from `_iconForId()` helper) + status text (token count, etc.) computed by `MagicDrawerStatsService`.

### 9.7 Item actions stay in Flutter
On `onMagicItemTap(itemId)`, Flutter's `MagicDrawerActions` (renamed from `_handleItemTap` in `magic_drawer.dart`) opens the appropriate sheet:
- 'context' → `tokenizer_sheet.dart`
- 'summary' → `summary_sheet.dart`
- 'sessions' → existing sessions UI
- 'char-card' → push character_detail_screen route
- 'lorebooks' → `lorebook_quick_sheet.dart`
- 'memory-books' → `memory_books_sheet.dart`
- 'regex' → `regex_sheet.dart`
- 'api' → push `api_settings_screen.dart`
- 'presets' → push `preset_list_screen.dart`
- 'preview' → push `prompt_preview_screen.dart`
- 'image-gen' → `image_gen_sheet.dart`
- 'glossary' → `glossary_sheet.dart`
- 'stats' → `chat_stats_sheet.dart`
- 'ext-blocks' → `ext_blocks_settings_sheet.dart`

These are all existing Flutter widgets — no porting needed, just wire callbacks.

### 9.8 Stats refresh
`MagicDrawerStatsService` already computes token counts asynchronously. When stats change, call `setMagicDrawerStatuses({itemId: '15 tokens', ...})` to avoid re-rendering items.

---

## 10. After all phases — `chat_screen.dart` shape

```dart
class ChatScreen extends ConsumerStatefulWidget { ... }

class _ChatScreenState extends ConsumerState<ChatScreen> {
  // Slimmer drawer controller — only persists last keyboard height.
  late final ChatKeyboardMemory _kbMemory;
  late final ChatSearchDelegate _search;
  late final MagicDrawerActions _drawerActions;

  @override
  Widget build(BuildContext context) {
    // Push safe areas + keyboard height to WebView on every build.
    final mq = MediaQuery.of(context);
    final keyboardHeight = mq.viewInsets.bottom;
    final safeTop = mq.padding.top;
    final safeBottom = mq.padding.bottom;

    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: false,
      body: SessionLifecycleTracker(
        charId: widget.charId,
        child: PopScope(
          canPop: false,  // JS decides via onHeaderBack
          onPopInvokedWithResult: (_, __) => _onSystemBack(),
          child: ChatWebViewWidget(
            charId: widget.charId,
            // ... all the existing props ...
            keyboardHeight: keyboardHeight,
            safeTop: safeTop,
            safeBottom: safeBottom,
            headerPayload: _buildHeaderPayload(),
            inputPayload: _buildInputPayload(),
            magicDrawerPayload: _buildMagicDrawerPayload(),
            callbacks: WebViewCallbacks(
              onHeaderBack: () => context.go('/'),
              onHeaderSearchToggle: _onSearchToggle,
              onSearchQueryChanged: _onSearchQuery,
              onSendMessage: _onSend,
              onPickImage: _onPickImage,
              onMagicToggle: _onMagicToggle,
              onMagicItemTap: _drawerActions.handle,
              // ... etc.
            ),
          ),
        ),
      ),
    );
  }
}
```

`extendBodyBehindHeader`, `_isHeaderHidden`, the InfoBlockDrawerWidget wrapper, the magic drawer overlay — all gone.

---

## 11. Files matrix

### Added
- `assets/chat_webview/chat_header.css` (optional split)
- `assets/chat_webview/chat_input.css` (optional split)
- `assets/chat_webview/magic_drawer.css` (optional split)
- `assets/chat_webview/input_handler.js` (textarea logic, mode rendering)
- `assets/chat_webview/header_handler.js`
- `assets/chat_webview/magic_drawer_handler.js`
- `lib/features/chat/bridge/bridge_header_commands.dart`
- `lib/features/chat/bridge/bridge_input_commands.dart`
- `lib/features/chat/bridge/bridge_magic_drawer_commands.dart`
- `lib/features/chat/services/magic_drawer_actions.dart` (extracted from `magic_drawer.dart`)
- `lib/features/chat/state/webview_callbacks.dart` (new typed callback set, complementing existing `webview_callbacks.dart`)

### Modified
- `assets/chat_webview/index.html` (new DOM nodes)
- `assets/chat_webview/styles.css` (significantly expanded)
- `assets/chat_webview/bridge.js` (many new methods + setBackgroundImage rewrite)
- `lib/features/chat/bridge/bridge_handlers.dart`
- `lib/features/chat/bridge/chat_bridge_controller.dart`
- `lib/features/chat/bridge/bridge_layout_commands.dart` (remove Phase 0 stubs)
- `lib/features/chat/bridge/bridge_theme_commands.dart` (bg-image rewrite + setBgDim)
- `lib/features/chat/widgets/chat_webview_widget.dart` (many new props/calls, bg removal)
- `lib/features/chat/chat_screen.dart` (major rewrite per §10)
- `lib/features/chat/chat_drawer_controller.dart` (heavily slimmed)
- `lib/features/chat/widgets/magic_drawer.dart` → split: actions to service, widget removed
- `lib/features/settings/theme_preview.dart` (replace ChatHeader/ChatInputBar with mock pills)

### Deleted
- `lib/features/chat/widgets/chat_header.dart`
- `lib/features/chat/widgets/chat_input_bar.dart`
- `lib/features/chat/widgets/magic_drawer_widgets.dart` (the rendering bits — may keep helpers)

---

## 12. Known gotchas and decisions to make

| # | Decision | Recommendation |
|---|---|---|
| 1 | Avatar bytes vs file:// | Use `file://` path (already supported by `setIdentity`); fall back to data URI only when no path. |
| 2 | Image preview after attach | After `file_picker` in Flutter, send as `data:image/...;base64,...`. Same already done in current `_pickImage`. |
| 3 | Auto-resize textarea | Mirror `ChatInput.vue` — listen to `input` event, set `style.height = 'auto'` then `style.height = scrollHeight + 'px'`, max 5 lines worth (~120px). |
| 4 | Editing message lock | When Flutter is editing a message inline, input must be readonly (`textarea.readOnly = true`) — already a pattern in current Flutter input. |
| 5 | Battery-saver disables animations | Mirror existing `.battery-saver` class on `<html>` to disable transitions / backdrop-filters where appropriate. |
| 6 | InfoBlockDrawerWidget | Currently wraps the chat screen for ext-block info display. Decide: drop, port to WebView overlay, or keep as full-screen Flutter overlay outside the WebView. **Recommended:** keep as Flutter overlay above the WebView (it's a transient sheet). |
| 7 | Pop scope / back button | Android system back: must close drawer → close search → pop route. Implement in Flutter `PopScope.onPopInvoked` calling JS `onSystemBack` first, which returns true if it consumed the back; otherwise Flutter pops. |
| 8 | Glaze logo / GlazeBackground | The WebView already has bg + chat. The chat screen no longer needs `GlazeBackground`. Use a plain `Scaffold(backgroundColor: cs.surface)`. |
| 9 | `theme_preview.dart` | Don't try to use the new WebView header/input pills in the preview. Build a simple Flutter mock (~50 LOC). |
| 10 | i18n strings | Vue uses `translations[currentLang.value]`. Flutter uses `easy_localization`. Hardcode English in WebView for now; add a `setI18n(map)` bridge call later if needed. |
| 11 | Theme variables sync | The bg-image color/opacity/dim and `--element-blur` etc. already flow via `applyTheme`. Need to ensure header/input use the same vars so the theme editor live-update keeps working. |
| 12 | Tests | The Flutter widget tests for `ChatHeader` / `ChatInputBar` need to be deleted. WebView UI is not unit-testable from Flutter — accept that and rely on manual testing. |
| 13 | Hot restart vs reload | `assets/chat_webview/` changes need hot **restart** (R), not reload. Mention in commit messages. |

---

## 13. Suggested commit order

Each phase is a separate PR/branch off master:
1. `chore/revert-blur-strips` (Phase 0)
2. `feat/webview-bg-image` (Phase 1)
3. `feat/webview-chat-header` (Phase 2)
4. `feat/webview-chat-input` (Phase 3)
5. `feat/webview-magic-drawer` (Phase 4)

Each PR can be tested independently. Phase 1 is the only one that user-visibly fixes the bg-blur issue without full migration; Phases 2+ also fix the chrome-blur by virtue of unifying compositing.

---

## 14. Out of scope for this plan

- Desktop sidebar mode (Vue's `magic-drawer-sidebar` variant). GlazeFlutter is mobile-first.
- Tooltip on magic items (Vue uses `<Tooltip>`). Skip.
- Notifications badge in header (Vue's `notif-btn`). Skip unless required.
- Lorebook banner (`.app-header-banner`). Skip.
- `header-wrap` / Generation tabs. Not used on chat screen.

---

## 15. Pre-flight sanity check before starting

Before writing any code, read these to confirm current state (some of this plan assumes context that may have shifted):

- `lib/features/chat/chat_screen.dart` — current build tree
- `lib/features/chat/widgets/chat_webview_widget.dart` — current props
- `lib/features/chat/widgets/magic_drawer.dart` — current item set + actions
- `lib/features/chat/chat_drawer_controller.dart` — current animation logic
- `assets/chat_webview/bridge.js` — current JS method list
- `assets/chat_webview/index.html`, `styles.css` — current DOM/CSS
- `lib/features/settings/theme_preview.dart` — preview's current dependencies

If anything diverges materially from what this plan describes, update the plan first, then code.
