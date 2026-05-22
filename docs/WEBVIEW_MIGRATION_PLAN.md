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
- `textFormatter.js` — рабочий проверенный конвертер MD+HTML → HTML
- CSS стили из `ShadowContent.vue` — `.chat-quote`, `.chat-italic`, typing dots
- Концепцию Shadow DOM для изоляции стилей каждого сообщения
- Логику highlight phrases (цитаты, поиск)

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
├─ virtual_list.js            — виртуальный скролл (пока без виртуализации)
├─ bridge.js                  — мост JS → Flutter
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
- [ ] **D.6** Фоновое изображение пресета внутри WebView

### Фаза E — Поиск (частично)

- [x] **E.1** `setSearch()` в мосту
- [ ] **E.2** Реальная подсветка внутри Shadow DOM + `scrollIntoView`
- [ ] **E.3** Удалить старый `_highlightPhrases()` из Dart

### Фаза F — Визуал и поведение сообщений

- [x] **F.1** Bubble + Standard layout
- [x] **F.2** Реальные имена и аватары (base64 data URLs)
- [x] **F.3** Свайпы (индикатор + кнопки в metadata row)
- [x] **F.4** Контекстное меню (⋮ кнопка → Flutter bottom sheet)
- [x] **F.5** Typing indicator при стриминге (3 bounce dots)
- [x] **F.6** Error message styling
- [x] **F.7** Metadata row (gen time, tokens, lorebook/memory badges)
- [x] **F.8** Редактирование (textarea с raw text + reasoning)
- [x] **F.9** Выделение текста + Copy
- [ ] **F.10** Кастомный шрифт чата (`chatFont`)
- [ ] **F.11** Отображение и клик по изображениям в сообщениях
- [ ] **F.12** Regenerate из WebView

### Фаза G — Оптимизация

- [x] **G.1** Форматтер кэш (LRU 500 entries)
- [x] **G.2** Smooth scroll (RAF easing)
- [x] **G.3** WebView кэш (`cacheEnabled`, `AutomaticKeepAliveClientMixin`)
- [ ] **G.4** Виртуальный скролл (рендерить только visible + buffer)
- [ ] **G.5** Prefetch/preload WebView при старте приложения
- [ ] **G.6** Instant chat loading (исследование Tav APK)

### Финал — Cleanup

- [ ] Удалить `html_block_view.dart`
- [ ] Удалить `ChatMessageList`
- [ ] Удалить GptMarkdown-ветку из `message.dart`
- [ ] Удалить per-message WebView
- [ ] Обновить `HTML_RENDERING_PLAN.md`

---

## Реальное состояние (май 2026)

**Работает:**
- Сообщения рендерятся через единый WebView
- Стриминг работает (включая reasoning)
- Имена персонажа и персоны, аватары (base64)
- Glaze-маркеры (`==hc:`, `==glow:`, `==cg:`, `==grad:`, `==bg:`, `==mark==`, `==active==`)
- Layout (bubble / standard) через CSS классы
- Тема (все CSS variables, per-role quote/italic colors)
- Контекстное меню (⋮ кнопка → Flutter bottom sheet)
- Свайпы (навигация в metadata row)
- Редактирование (raw markdown + reasoning, auto-resize textarea)
- Выделение текста + Copy
- Metadata row (gen time, tokens, triggered lorebook/memory badges)
- Typing indicator
- Error message styling
- Smooth scroll
- Поиск (мост подключён, реальная подсветка в Shadow DOM не реализована)

**Не подключено:**
- Пагинация вверх (listener есть, provider метод не реализован)
- Поиск: подсветка внутри Shadow DOM
- Виртуальный скролл
- Фоновое изображение пресета внутри WebView
- Кастомный шрифт
- Клик по изображениям в сообщениях
- Regenerate из WebView
- Prefetch WebView
