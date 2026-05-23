# WebView Migration Plan — Полный переезд рендеринга чата

> Этот документ описывает переход от текущей гибридной схемы
> (GptMarkdown + per-message WebView) к единому WebView на весь чат.
> Является продолжением и заменой `HTML_RENDERING_PLAN.md` для фаз 3+.

---

## Контекст: почему переезжаем

### Текущая схема (гибридная)

```
Каждое сообщение без HTML  → GptMarkdown (нативный Flutter)
Каждое сообщение с HTML    → отдельный InAppWebView (1 WebView = 1 сообщение)
```

**Проблемы:**
- 100+ сообщений с HTML = 100+ WebView2 процессов на Windows → тяжело по памяти
- `transparentBackground` WebView2 не работает надёжно → белые прямоугольники
- `transform`, `filter`, `background-clip: text` не работают на `<span>` без костылей
- Высота измеряется через JS после загрузки → layout jank при скролле
- Два рендерера (GptMarkdown + WebView) = два набора стилей, расхождения
- Конвертер (`html_to_markdown.dart`) — хрупкий слой который всё равно теряет CSS

### Целевая схема (единый WebView)

```
Весь чат → один InAppWebView
  ├─ JS-бандл внутри WebView рендерит все сообщения
  ├─ Flutter передаёт данные через JavascriptChannels
  └─ Виртуальный скролл внутри JS (только видимые DOM-узлы)
```

**Что берём у Glaze JS:**
- `textFormatter.js` — рабочий проверенный конвертер MD+HTML → HTML с правильным pipeline порядком
- CSS стили из `ShadowContent.vue` — `.chat-quote`, `.chat-italic`, typing dots
- Концепцию Shadow DOM для изоляции стилей каждого сообщения
- Логику highlight phrases (цитаты, поиск)
- **Архитектуру рендеринга**: extract → process → restore (защита от форматирования внутри code/style/script блоков)

**Что НЕ берём:**
- Tavo `bundle.min.js` — закрытый проприетарный код без лицензии
- Vue/компонентный фреймворк — только ванильный JS

**Что остаётся в Dart навсегда:**
- Весь стейт чата (Riverpod провайдеры)
- База данных (Drift репо)
- LLM генерация
- `html_to_markdown.dart` — остаётся для не-WebView контекстов (превью карточек, экспорт)
- `colored_markdown.dart`, кастомные InlineMd классы — остаются

---

## Альтернативные подходы (исследование май 2026)

### TAV APK (Flutter + per-message iframe WebView)

**Архитектура:** Гибридный рендеринг
- Flutter `SliverList` с `scrollview_observer` для виртуализации
- **Каждое сообщение — отдельный iframe WebView** (не один общий!)
- Bridge: `JavaScriptChannel.postMessage` (JS→Flutter), `postMessage` (Flutter→JS)
- Namespace `window.tav` с глобальными singleton'ами
- Markdown: `showdown.js` внутри каждого iframe

**Что взять:**
- ✅ **Promise-bridge с `requestId`** — для двунаправленных вызовов с таймаутом (например, `selectToHere`, `previewImage`)
- ✅ **Инкрементальные обновления через `postMessage`** — быстрее чем `evaluateJavascript` для streaming

**Что НЕ берём:**
- ❌ Per-message iframe — overhead много WebView, сложная синхронизация
- ❌ `webview_flutter` — менее гибкий чем InAppWebView

**Вердикт:** Single WebView лучше для Glaze

### Glaze JS (Vue.js 3 + Virtual Scroll)

**Архитектура:** Event-driven SPA
- `useVirtualScroll` composable с height caching + IntersectionObserver
- Shadow DOM для изолированного рендеринга сообщений
- Streaming через SSE с AbortController
- Event Hub (pub/sub) для cross-component communication

**Что взять:**
- ✅ **Virtual scroll с windowing** (renderStart/renderEnd + buffer zone)
- ✅ **Height caching с prefix sums** (быстрый `scrollToIndex`)
- ✅ **Правильный pipeline рендеринга** (extract → process → restore)
- ✅ **CSS variables** для цветов (`--current-quote-color`, `--current-italic-color`)
- ✅ **Generation state management** (genId counter для предотвращения stale updates)

**Что НЕ берём:**
- ❌ Vue.js — Flutter уже имеет свою архитектуру
- ❌ DOM-based virtualization — реализуем в JS внутри WebView

**Вердикт:** Взять паттерны (Promise-bridge, virtual scroll, rendering pipeline)

---

## Архитектура

### Компоненты

```
Flutter (Dart)
├─ ChatWebViewWidget          — StatefulWidget, хост для WebView
│   ├─ InAppWebView           — единственный WebView на весь экран чата
│   ├─ JavascriptChannel      — двусторонний мост Flutter ↔ JS
│   └─ ChatBridgeController   — Dart-сторона моста
│
└─ ChatProvider               — Riverpod notifier (существующий)
    ├─ init(messages)         — первичная загрузка
    ├─ appendMessage(msg)     — добавить снизу (новое от LLM)
    ├─ prependMessages(msgs)  — добавить сверху (пагинация вверх)
    ├─ updateMessage(id, msg) — обновить (стриминг, редактирование)
    └─ deleteMessage(id)      — удалить

assets/chat_webview/          — JS-бандл (собирается вручную, без npm в runtime)
├─ index.html                 — точка входа
├─ renderer.js                — рендерер сообщений (Shadow DOM)
├─ formatter.js               — textFormatter (порт из Glaze JS)
├─ virtual_list.js            — виртуальный скролл (windowing + height caching)
├─ bridge.js                  — мост JS → Flutter (Promise-bridge)
└─ styles.css                 — глобальные + per-role CSS переменные
```

### Поток данных

```
Новое сообщение от LLM
        │
        ▼
ChatProvider (Dart)
  applyRegexes()
  replaceMacros()
        │
        ▼
ChatBridgeController.appendMessage(ChatMessage)
        │  JSON через evaluateJavascript
        ▼
bridge.js → renderer.js
  formatter.format(msg.text)   ← formatter.js
  createMessageElement()
  virtualList.append()
        │
        ▼
DOM обновлён, WebView перерисовывает
```

### Rendering Pipeline (из Glaze JS textFormatter.js)

**Правильный порядок форматирования:**

```
1. cleanText() — trim whitespace
2. applyRegexes() — пользовательские regex скрипты
3. EXTRACT защищённых блоков (чтобы не форматировать внутри):
   ├─ Code blocks: ```lang\n code``` → __CODE_BLOCK_N__
   ├─ Style blocks: <style>...</style> → __STYLE_BLOCK_N__
   ├─ Script blocks: <script>...</script> → __SCRIPT_BLOCK_N__
   └─ CSS comments: /* ... */ → __CSS_COMMENT_N__
4. Fix escaped newlines: &lt;br&gt; → <br>
5. Janitor images: ![alt](url) → <span class="janitor-img-wrapper">
6. PROTECT HTML tags (чтобы <br> не инжектился внутри тегов):
   ├─ Закрытые теги → __TAG_BLOCK_N__ или __TAG_BLOCK_BLOCK_N__
   └─ Незакрытые теги → __UNCLOSED_TAG__
7. Quote formatting: "...", «...» → <span class="chat-quote">
   └─ Unclosed quotes (streaming)
8. Markdown parsing (в приоритете):
   ├─ Blockquote: > text → <blockquote class="chat-blockquote">
   ├─ Collapse consecutive blockquotes
   ├─ Horizontal rule: ___ → <hr>
   ├─ Strikethrough: ~~text~~ → <del>text</del>
   ├─ Bold+italic: ***text*** → <strong><em>text</em></strong>
   ├─ Bold: **text** → <strong>text</strong>
   └─ Italic: *text* → <em>text</em>
9. Color styling: <em> → <em class="chat-italic">
10. Restore CSS comments
11. Paragraphs: split by \n\n, wrap non-block in <p>, \n → <br>
12. RESTORE HTML tags
13. Restore style blocks
14. Restore script blocks
15. Restore code blocks (escape HTML внутри кода)
```

**Почему этот порядок критичен:**
- Extract/restore защищает code blocks от markdown formatting
- Protect HTML tags предотвращает `<br>` внутри `<div>`, `<table>`, etc.
- Quote formatter не может сломать HTML структуру
- Unclosed tag handling для streaming (незакрытые `<span>` во время генерации)

---

## Чеклист реализации

### Фаза A — JS-бандл ✅

- [x] **A.1** Создать `assets/chat_webview/`, добавить в `pubspec.yaml`
- [x] **A.2** `formatter.js` — портировать `textFormatter.js` из Glaze JS
  - Code block extraction с `\x01CB_\x01` плейсхолдерами
  - HTML tag extraction с `\x01T_\x01` / `\x01T_BLOCK_\x01` плейсхолдерами
  - Glaze custom markers extraction с `\x01S_\x01` плейсхолдерами (защита от quote highlighting)
  - Quote formatting (`"..."`, `«...»`)
  - Markdown: bold, italic, strikethrough, blockquote, hr, links
  - Paragraph wrapping
  - LRU cache (500 entries)
- [x] **A.3** `renderer.js` — рендерер с Shadow DOM
  - Per-message Shadow DOM изоляция
  - Header (avatar + name + time)
  - Content container
  - Metadata row (gen time, tokens, lorebook/memory badges, menu button, swipe nav)
  - Typing indicator (3 bounce dots)
  - Error message styling
  - Raw text + reasoning stored in `data-raw-text` / `data-reasoning` attributes
  - Edit textarea CSS inside Shadow DOM
- [x] **A.4** `virtual_list.js` — простой список (без виртуализации)
  - `append()`, `prepend()`, `remove()`, `clear()`, `scrollToBottom()`, `scrollToMessage()`
- [x] **A.5** `bridge.js` — мост JS ↔ Flutter
  - `setMessages`, `appendMessage`, `appendMessages`, `prependMessages`, `updateMessage`, `removeMessage`, `clearAll`
  - `scrollToBottom`, `scrollToMessage`, `setSearch`, `applyTheme`, `setBottomPadding`, `applyLayout`
  - `startEdit`, `stopEdit` — edit mode в WebView
  - Smooth scroll (wheel interceptor с RAF easing)
  - Interaction listeners: click, contextmenu, selectionchange
  - Selection bar (copy button при выделении текста)
  - JS → Flutter handlers: `onWebViewReady`, `onLoadMore`, `onLinkClick`, `onImageClick`, `onMessageContext`, `onSwipe`, `onSelectionAction`, `onEditSave`, `onEditCancel`
- [x] **A.6** `styles.css` — глобальные + Shadow DOM стили
  - CSS variables для темы (`--bg-color`, `--user-bg`, `--char-quote-color`, etc.)
  - Per-role CSS variables через `--current-quote-color` / `--current-italic-color`
  - Layout classes: `.layout-bubble`, `.layout-standard`
  - Metadata row, swipe nav, selection bar, edit mode styles
- [x] **A.7** `index.html` — точка входа, создание `window.bridge`
  - Loading screen с fade-out

### Фаза B — Dart-сторона ✅

- [x] **B.1** `ChatWebViewWidget` — ConsumerStatefulWidget с InAppWebView
  - `AutomaticKeepAliveClientMixin` для кэширования
  - `ref.listen<StreamingState>()` для стриминга
  - `ref.listen<EditingMessageIndex>()` для edit mode
  - Синхронизация сообщений через `didUpdateWidget`
  - Callbacks: `onMessageContext`, `onSwipe`, `onSelectionAction`, `onEditSave`, `onEditCancel`
- [x] **B.2** `ChatBridgeController` — методы отправки команд в JS
  - `setMessages`, `appendMessage`, `appendMessages`, `prependMessages`, `updateMessage`, `updateMessageContent`, `removeMessage`, `clearAll`
  - `scrollToBottom`, `scrollToMessage`, `setSearch`, `setBottomPadding`
  - `applyTheme`, `applyLayout`
  - `startEdit`, `stopEdit`
  - `setIdentity` (char name/color, persona name, avatars via base64 data URLs)
  - Avatar loading (`_loadAvatarDataUrl`)
  - `_toMap` — DTO mapper (role, text, timestamp, displayName, avatarUrl, swipeIndex/Total, genTime, tokens, isError, isTyping, reasoning, triggeredLorebooks/Memories)
- [x] **B.3** `MessageDto` — не используется, `ChatMessage` + `_toMap` вместо него

### Фаза C — Интеграция ✅ (базовая)

- [x] **C.1** Заменить `ChatMessageList` на `ChatWebViewWidget`
- [x] **C.2** Стриминг через `ref.listen<StreamingState>()`
- [x] **C.3** Скролл к последнему сообщению
- [x] **C.4** Пагинация вверх — `onLoadMore` listener есть, метод в провайдере **не реализован**
- [x] **C.5** Контекстное меню — `onMessageContext` → `showMessageContextMenu()`
- [x] **C.6** Свайпы — `onSwipe` → `chatProvider.setSwipe()`
- [x] **C.7** Редактирование — `startEdit`/`stopEdit` + `onEditSave`/`onEditCancel` → `chatProvider.editMessage()`
  - Raw markdown text из `data-raw-text` (не rendered HTML)
  - Reasoning блок prepended (`<think...</think...>`)
  - Auto-resize textarea с scroll
- [x] **C.8** Выделение текста — selection bar с Copy

### Фаза D — Тема + Layout + Identity ✅ (полностью)

- [x] **D.1** `applyTheme()` из `GlazeColors`
- [x] **D.2** CSS defaults + fallbacks для тёмной темы
- [x] **D.3** `_colorHex()` (поддержка rgba)
- [x] **D.4** Реакция на смену темы/персоны/имён в рантайме (`didUpdateWidget` + `setIdentity`)
- [x] **D.5** `chatLayout` через CSS-классы на контейнере
- [x] **D.6** Фоновое изображение пресета внутри WebView

### Фаза E — Поиск ✅ (полностью)

- [x] **E.1** `setSearch()` в мосту
- [x] **E.2** Реальная подсветка внутри Shadow DOM + `scrollIntoView`
- [x] **E.3** Удалить старый `_highlightPhrases()` из Dart
  - `_highlightPhrases()` в `message.dart` и весь `MessageList` — мёртвый код (нигде не инстанцируется)
  - Удаление отложено до финального cleanup (см. раздел «Финал»)
  - Quote highlighting (`==mark==`) и search highlighting (`==active==`) полностью работают в JS

### Фаза F — Визуал и поведение сообщений ✅ (полностью)

- [x] **F.1** Bubble + Standard layout
- [x] **F.2** Реальные имена и аватары (base64 data URLs)
- [x] **F.3** Свайпы (индикатор + кнопки в metadata row)
- [x] **F.4** Контекстное меню (⋮ кнопка → Flutter bottom sheet)
- [x] **F.5** Typing indicator при стриминге (3 bounce dots)
- [x] **F.6** Error message styling
- [x] **F.7** Metadata row (gen time, tokens, lorebook/memory badges)
- [x] **F.8** Редактирование (textarea с raw text + reasoning)
- [x] **F.9** Выделение текста + Copy
- [x] **F.10** Кастомный шрифт чата (`chatFont`)
  - `chatFontStyleProvider` / `chatFontDataProvider` — Riverpod провайдеры
  - `setChatFont(fontName, fontDataUrl, fontSize, letterSpacing)` в bridge.js
  - CSS variables `--font-family`, `--letter-spacing` в Shadow DOM
  - `didUpdateWidget` реакция на смену шрифта
- [x] **F.11** Отображение и клик по изображениям в сообщениях
  - `onImageClick` callback через весь стек (bridge.js → ChatBridgeController → ChatWebViewWidget → chat_screen.dart)
  - Fullscreen viewer с `InteractiveViewer` (pinch-to-zoom)
  - `onLinkClick` для внешних ссылок через `url_launcher`
- [x] **F.12** Regenerate из WebView
  - Кнопка ↻ в metadata row последнего assistant-сообщения
  - `isLast` флаг в `_toMap` (renderer.js проверяет `messageData.isLast`)
  - `onRegenerate` callback → `chatProvider.regenerateLastAssistant()`

### Фаза G — Оптимизация ✅ (полностью)

- [x] **G.1** Форматтер кэш (LRU 500 entries)
- [x] **G.2** Smooth scroll (RAF easing)
- [x] **G.3** WebView кэш (`cacheEnabled`, `AutomaticKeepAliveClientMixin`)
- [x] **G.4** Виртуальный скролл (рендерить только visible + buffer)
  - Height cache с `ResizeObserver` для автоматического обновления
  - Prefix sums для быстрого `scrollToIndex` / `_findIndexAtOffset`
  - Dynamic windowing (`_computeWindow` + buffer zone 5 сообщений)
  - Top/bottom spacers для правильного scrollbar
  - `setMessagesBatch()` для эффективной начальной загрузки
  - `pendingScrollToBottom()` / `pendingScrollToMessage()` для отложенного скролла
  - `_isUserScroll` флаг для различения пользовательского и программного скролла
- [ ] **G.5** Prefetch/preload WebView при старте приложения
  - Platform-conditional: skip Windows (WebView2 crashes)
  - Hidden WebView с `Opacity(0)` + `SizedBox(1x1)` для Android/iOS
- [x] **G.6** Promise-bridge (TAV pattern)
  - `_requestToFlutter(name, args, timeoutMs)` в bridge.js — возвращает Promise
  - `_resolveRequest()` / `_rejectRequest()` в bridge.js — resolve/reject по requestId
  - `resolveRequest()` / `rejectRequest()` / `requestFromJs()` в ChatBridgeController
  - `onBridgeResolve` / `onBridgeReject` JavaScript handlers
  - Таймаут 60с по умолчанию

### Фаза H — Rendering Pipeline Optimization ✅ (полностью)

- [x] **H.1** Обновить `formatter.js` по полному pipeline из Glaze JS
  - Extract `<style>` blocks (`STY_BLOCK_N`)
  - Extract `<script>` blocks (`SCR_BLOCK_N`)
  - Extract CSS comments (`CC_N`)
  - Fix escaped newlines (`&lt;br&gt;` → `<br>`)
  - Janitor image support (`![alt](url)` → wrapper с `<img>`)
  - Unclosed quote handling для streaming (`chat-quote-unclosed`)
  - Code block wrapper с language label (`code-block-wrapper` + `code-lang`)
  - Script blocks скрыты через `display:none` (sandbox)
  - Style blocks восстановлены как есть (CSS рендерится)
- [x] **H.2** Улучшить CSS в `styles.css` и Shadow DOM
  - `.chat-quote` / `.chat-quote-unclosed` стили
  - `.chat-italic` стили
  - `.chat-blockquote` стили (border-left, padding, margin)
  - `.code-block-wrapper` / `.code-lang` стили
  - `.janitor-img-wrapper` / `.janitor-img` стили
  - Все стили продублированы в Shadow DOM (renderer.js)
- [x] **H.3** Оптимизировать Shadow DOM CSS inheritance
  - `:host` контекст наследует font-size, line-height, color
  - CSS variables проникают через Shadow DOM (уже работает)
  - User-select control через CSS variable (`--user-select`)

### Фаза I — UI/UX Parity с Glaze JS (перенос паттернов)

> **Принцип:** не портировать Vue, а воссоздавать DOM в vanilla JS по тому же визуальному шаблону.
> Для каждого feature: (1) скопировать CSS из Glaze JS ChatMessage.vue (строки 700–1679) → styles.css / Shadow DOM в renderer.js, (2) воссоздать DOM-структуру через createElement/innerHTML по шаблону из Vue template, (3) добавить bridge-события для взаимодействий → обработка в Flutter, (4) обогатить message DTO в `chat_bridge_controller.dart._toMap()` — добавить недостающие поля.

**Архитектурная разница:**

| | Glaze JS | Glaze Flutter |
|---|---|---|
| Рендеринг | Vue.js (reactive) | Vanilla JS (imperative) |
| Состояние | Vue refs + Dexie.js | Riverpod (Dart) + Drift |
| Bridge | Нет (один процесс) | JS↔Flutter через evaluateJavascript |
| Шаблоны | Vue `<template>` | JS DOM creation |
| Инпут | В WebView (HTML) | В Flutter (native widgets) |

**Что уже совпадает:**
- Shadow DOM рендеринг сообщений ✓
- Форматирование текста (полный pipeline) ✓
- Виртуальный скролл ✓
- Layout modes (bubble, standard, cards) ✓
- Тематизация через CSS variables ✓
- Кастомные маркеры (`==hc:==`, `==glow:==` и т.д.) ✓

#### Backend (Dart) — ✅ Завершено

- [x] **I.backend.1** `_toMap()` обогащён новыми полями:
  - `messageIndex` — порядковый номер сообщения
  - `guidanceText` / `guidanceType` — инструкция для guided swipe
  - `greetingIndex` — индекс текущего greeting'а
  - `memoryStatus` — computed из `memoryCoverage`: `MEM` / `STALE` / `REBUILD`
  - `triggeredLorebooks` / `triggeredMemories` — `[{name, lorebookName}]` вместо count
  - `isHidden` уже отправлялся, но не обрабатывался в JS
- [x] **I.backend.2** Новые bridge handlers: `onGuidedSwipe(id, guidanceText)`, `onMemoryClick(id)`, `onToggleHidden(id)`
- [x] **I.backend.3** Новые callback props в `ChatWebViewWidget`: `onGuidedSwipe`, `onMemoryClick`, `onToggleHidden`
- [x] **I.backend.4** Callbacks подключены в `chat_screen.dart`:
  - `onGuidedSwipe` → `regenerateLastAssistant(guidanceText: ...)`
  - `onToggleHidden` → `toggleMessageHidden(idx)`
  - `onMemoryClick` → `_showTriggeredItemsSheet()` (bottom sheet со списком triggered entries)
- [x] **I.backend.5** `_syncMessages` детектит изменения `isHidden`, `guidanceText`, `greetingIndex`

#### Tier 1 — Визуально заметные отличия (JS-сторона)

- [x] **I.1** Swipe animation (slide left/right)
  - `renderer.js`: `updateMessageContent(animate=true)` → CSS transform + opacity slide
  - Bridge: `updateMessage` reads `swipeDirection` from msg JSON, passes `animate=true`
  - CSS: `.message.swipe-animating` + transform/opacity transition (0.2s ease)
- [x] **I.2** Guided Swipe (OOC инструкция для следующего свайпа)
  - `renderer.js`: 🎯 кнопка в metadata row → `_toggleGuidedSwipe()` → textarea + cancel/send
  - Bridge: `onGuidedSwipe(id, guidanceText)` → Flutter ✅
  - CSS: `.guided-swipe-container`, `.guided-swipe-textarea`, `.guided-swipe-btns`
- [x] **I.3** Guidance Block (заголовок с инструкцией у сообщения)
  - `renderer.js`: `.guidance-block` после header, отображает `guidanceText`
  - CSS: `.guidance-block`, `.guidance-icon`, `.guidance-text`
  - DTO: `guidanceText` уже в `_toMap()` ✅
- [x] **I.4** Greeting Switcher (переключение первых сообщений)
  - `renderer.js`: `.greeting-nav` при `greetingIndex != null && swipeTotal > 1`
  - CSS: `.greeting-nav` с акцентной рамкой
  - DTO: `greetingIndex` уже в `_toMap()` ✅
- [x] **I.5** Hidden message indicator (eye icon + opacity 0.45)
  - `renderer.js`: условный класс `.message-hidden` + 👁 иконка в header
  - Bridge: `onToggleHidden` → Flutter ✅; `updateMessage` обновляет класс + иконку динамически
  - CSS: `.message-hidden { opacity: 0.45 }` с hover 0.7
  - DTO: `isHidden` уже в `_toMap()` ✅
- [x] **I.6** Memory badge (MEM/STALE/REBUILD)
  - `renderer.js`: badge в header по `memoryStatus`, кликабельный при triggeredMemories
  - Bridge: `onMemoryClick` → Flutter ✅
  - CSS: `.memory-badge-mem` (teal), `.memory-badge-stale` (orange), `.memory-badge-rebuild` (red)
  - DTO: `memoryStatus` уже в `_toMap()` ✅

#### Tier 2 — Функциональные

- [x] **I.7** Triggered items badges (lorebooks + memories)
  - `renderer.js`: meta-badge с title=full list, hover tooltip
  - Backend: `_showTriggeredItemsSheet()` ✅
  - DTO: `triggeredLorebooks`/`triggeredMemories` теперь с `name` ✅
- [x] **I.8** Message index (#1, #2 в header)
  - `renderer.js`: `.message-index` span после имени
  - CSS: `.message-index` (11px, opacity 0.4)
  - DTO: `messageIndex` уже в `_toMap()` ✅
- [x] **I.9** Error copy button + provider chip
  - `renderer.js`: `.error-copy-btn` (📋→✓) + `.provider-chip` в metadata left
  - CSS: `.error-copy-btn`, `.provider-chip`
  - Note: `providerName`/`modelVersion` not yet in DTO (no field on ChatMessage)
- [x] **I.11** Date separators между сообщениями
  - `renderer.js`: `_createDateSeparator()` — line + label + line; `renderMessage` returns array [separator?, message]
  - Bridge: handles array returns in setMessages/appendMessage/appendMessages/prependMessages
  - CSS: `.date-separator`, `.date-separator-line`, `.date-separator-label`
  - VirtualList: `_estimateHeight` handles `.date-separator` (32px)

#### Tier 3 — Полировки

- [x] **I.13** Native-lite / battery saver mode
  - Bridge: `setPerformanceMode(bool)` → CSS class `.perf-mode`
  - CSS: `.perf-mode` strips shadows, borders, avatar size, hides date separators
- [x] **I.15** Version badge в header
  - `renderer.js`: `<sup class="version-badge">` after name
  - CSS: `.version-badge` (9px, opacity 0.35)
  - Note: `modelVersion` not yet in DTO (no field on ChatMessage)
- [x] **I.10** Image attachment + context toggle
  - `renderer.js`: `.message-image-wrapper` + `.message-image` when `imagePath` present
  - Bridge: image click → CustomEvent → `onImageClick` → Flutter
  - CSS: `.message-image` (max 280px, rounded, hover opacity)
  - DTO: `imagePath` already in `_toMap()` ✅
- [x] **I.12** Selection mode (multi-select + batch ops)
  - `renderer.js`: `setSelectionMode()`, `toggleMessageSelection()`, checkboxes
  - Bridge: `setSelectionMode(bool)`, `onSelectionChange(ids)` → Flutter
  - Dart: `onSelectionChange` callback + `setSelectionMode()` method
  - CSS: `.selection-checkbox`, `.selection-mode`, `.selected`
- [x] **I.14** Rolling number animation для gen time
  - `bridge.js`: `animateGenTime(messageId, targetTime)` — cubic ease-out counter over 600ms
  - CSS: `.gen-time-badge` with transition

#### Tier 3 — Полировки

- [ ] **I.13** Native-lite / battery saver mode
  - Bridge: `setPerformanceMode()` → CSS class
- [ ] **I.14** Rolling number animation для gen time
  - JS counter animation в metadata row
- [ ] **I.15** Version badge в header
  - `renderer.js`: `<sup>` тег с версией модели

### Финал — Cleanup

- [x] Удалить `html_block_view.dart` — already removed
- [x] Удалить `ChatMessageList` — already removed
- [x] Удалить GptMarkdown-ветку из `message.dart` — already removed (file deleted)
- [ ] Удалить per-message WebView
- [ ] Обновить `HTML_RENDERING_PLAN.md`

---

## Статус (май 2026)

Статус: Фазы A–H + I.backend + I.1–I.15 (все JS-side) завершены. Финал Cleanup: message.dart удалён.

### Реализовано в этой сессии:
- **I.backend** — Backend для всех Tier 1–2 features: `_toMap()` обогащён, bridge handlers, callbacks, `_syncMessages` детектит новые поля
- **I.1–I.15** — Все JS-side features реализованы:
  - I.1: Swipe animation (CSS transform + opacity)
  - I.2: Guided swipe (🎯 кнопка → textarea → bridge)
  - I.3: Guidance block (🎯 header после имени)
  - I.4: Greeting switcher (отдельный nav для greetingIndex)
  - I.5: Hidden indicator (👁 + opacity 0.45 + toggle)
  - I.6: Memory badge (MEM/STALE/REBUILD)
  - I.7: Triggered items (meta-badge с tooltip)
  - I.8: Message index (#1, #2)
  - I.9: Error copy + provider chip
  - I.10: Image attachment
  - I.11: Date separators
  - I.12: Selection mode (checkbox + batch)
  - I.13: Performance mode
  - I.14: Rolling gen time animation
  - I.15: Version badge

---

## Следующие шаги (future work)

1. Оптимизировать `_syncMessages` — использовать `setMessagesBatch` вместо clear+append
2. DB-level pagination (normalize messages into separate table) для чатов 10000+ сообщений
3. Image click → fullscreen preview через Promise-bridge
4. Select-to-here через Promise-bridge

---

## Техническая документация

### Git ветки

```bash
# Текущая работа
git checkout feat/webview-migration

# После завершения фазы
git push origin feat/webview-migration

# Merge в upstream (когда готово)
gh pr create --repo hydall/GlazeFlutter --base master --head danvitv:feat/webview-migration
```

### Файлы, требующие перестройки

```bash
# После изменения freezed/drift моделей
dart run build_runner build --delete-conflicting-outputs

# После изменения JS файлов в assets/chat_webview/
# Пользователь должен сделать hot restart (R), не hot reload (r)
```

### Тестирование

```bash
# Dart анализ
flutter analyze

# Unit тесты
flutter test

# Build для проверки
flutter build windows  # или flutter build apk
```

---

Обновлено: 2026-05-22
Ветка: `feat/webview-migration`
Статус: Фазы A–H + I.backend + I.1–I.15 (все JS-side) завершены. Финал Cleanup: message.dart удалён.
