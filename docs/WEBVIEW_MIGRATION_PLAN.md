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
  ├─ Flutter передаёт данные через JavascriptChannel
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
│   └─ _BridgeController      — Dart-сторона моста
│
└─ ChatWebViewNotifier        — Riverpod notifier
    ├─ init(messages)         — первичная загрузка
    ├─ appendMessage(msg)     — добавить снизу (новое от LLM)
    ├─ prependMessages(msgs)  — добавить сверху (пагинация вверх)
    ├─ updateMessage(id, msg) — обновить (стриминг, редактирование)
    └─ deleteMessage(id)      — удалить

assets/chat_webview/          — JS-бандл (собирается вручную, без npm в runtime)
├─ index.html                 — точка входа
├─ renderer.js                — рендерер сообщений
├─ formatter.js               — textFormatter (порт из Glaze JS)
├─ virtual_list.js            — виртуальный скролл
└─ bridge.js                  — мост JS → Flutter
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
_BridgeController.appendMessage(MessageDto)
        │  JSON через JavascriptChannel
        ▼
bridge.js → renderer.js
  formatText(msg.text)      ← formatter.js
  createMessageElement()
  virtualList.append()
        │
        ▼
DOM обновлён, WebView перерисовывает
```

---

## Фаза A: JS-бандл

### A.1 Структура файлов

Создать `assets/chat_webview/` — все файлы копируются в Flutter assets.

```
assets/
  chat_webview/
    index.html
    formatter.js
    renderer.js
    virtual_list.js
    bridge.js
    styles.css
```

В `pubspec.yaml`:
```yaml
flutter:
  assets:
    - assets/chat_webview/
```

### A.2 `formatter.js` — порт textFormatter.js

Взять `Z:\Glaze project\glaze\src\utils\textFormatter.js` как основу.
Убрать Vue-зависимости (`import`, `applyRegexes` — регексы применяются на Dart-стороне до передачи).
Адаптировать под ванильный JS-модуль:

```js
// formatter.js
const FORMAT_CACHE_MAX = 500;
const _formatCache = new Map();

window.GlazeFormatter = {
  format(text, isUser = false) {
    if (!text) return '';
    const key = `${isUser ? 1 : 0}|${text}`;
    if (_formatCache.has(key)) return _formatCache.get(key);

    let html = text;

    // Извлечь code blocks
    const codeBlocks = [];
    html = html.replace(/```(\w*)\n?([\s\S]*?)(?:```|$)/g, (m, lang, code) => {
      const id = `__CODE_${codeBlocks.length}__`;
      codeBlocks.push({ lang, code, closed: m.endsWith('```') });
      return id;
    });

    // style/script blocks
    // ... (порт из textFormatter.js)

    // Цитаты → .chat-quote
    // Italic *text* → .chat-italic
    // Bold **text** → <strong>
    // Blockquote > → .chat-blockquote
    // Horizontal rule → <hr>
    // Strikethrough ~~text~~ → <del>

    // Параграфы через \n\n

    // Restore code blocks
    // ...

    if (_formatCache.size >= FORMAT_CACHE_MAX) {
      _formatCache.delete(_formatCache.keys().next().value);
    }
    _formatCache.set(key, html);
    return html;
  }
};
```

**Ключевые правила форматтера** (из Glaze JS `textFormatter.js`):
- Сначала извлечь `code`, `style`, `script` блоки в плейсхолдеры — не трогать их содержимое
- Защитить HTML-теги от вставки `<br>` внутрь
- Цитаты: `"..."`, `"..."`, `«...»` → `<span class="chat-quote">`
- Незакрытые цитаты при стриминге — тоже красить
- `*text*` → `<em class="chat-italic">`, `**text**` → `<strong>`
- `\n\n` → параграфы `<p>`, одиночный `\n` → `<br>`
- Вернуть плейсхолдеры

### A.3 `renderer.js` — рендерер сообщений

```js
// renderer.js
window.GlazeRenderer = {
  // Создаёт DOM-элемент сообщения
  createMessage(msg) {
    const el = document.createElement('div');
    el.className = `glaze-message role-${msg.role}`;
    el.dataset.id = msg.id;

    // Хедер (аватар, имя, время)
    el.appendChild(this._buildHeader(msg));

    // Тело — Shadow DOM для изоляции CSS
    const body = document.createElement('div');
    body.className = 'glaze-msg-body';
    const shadow = body.attachShadow({ mode: 'open' });
    shadow.innerHTML = this._buildShadowContent(msg);
    el.appendChild(body);

    // Футер (свайпы, кнопки)
    el.appendChild(this._buildFooter(msg));

    return el;
  },

  _buildShadowContent(msg) {
    const html = window.GlazeFormatter.format(msg.text, msg.role === 'user');
    return `
      <style>${window.GlazeStyles.message}</style>
      <div class="content">${html}</div>
    `;
  },

  // Обновить текст существующего сообщения (стриминг)
  updateMessage(id, text) {
    const el = document.querySelector(`[data-id="${id}"]`);
    if (!el) return;
    const shadow = el.querySelector('.glaze-msg-body')?.shadowRoot;
    if (!shadow) return;
    const content = shadow.querySelector('.content');
    if (content) {
      content.innerHTML = window.GlazeFormatter.format(text, false);
    }
  },

  deleteMessage(id) {
    document.querySelector(`[data-id="${id}"]`)?.remove();
  }
};
```

**Shadow DOM для каждого сообщения** — ключевое решение:
- CSS из LLM HTML (`<style>` теги в тексте) не утекает на другие сообщения
- CSS переменные темы (`--current-quote-color`, `--char-bubble`) прокидываются через `:host`
- Полная изоляция как в ShadowContent.vue из Glaze JS

### A.4 `virtual_list.js` — виртуальный скролл

Минималистичный виртуальный список — только то что нужно:

```js
// virtual_list.js
// Рендерит только сообщения в viewport + N буферных выше/ниже.
// Остальные заменяются пустышками фиксированной высоты.

window.GlazeVirtualList = {
  BUFFER: 5,          // сообщений сверху/снизу от viewport
  _items: [],         // { id, height, el | null }
  _container: null,

  init(container) {
    this._container = container;
    window.addEventListener('scroll', () => this._onScroll(), { passive: true });
  },

  setItems(msgs) {
    this._items = msgs.map(m => ({ id: m.id, data: m, height: 80, el: null }));
    this._render();
  },

  append(msg) {
    this._items.push({ id: msg.id, data: msg, height: 80, el: null });
    this._render();
    this._scrollToBottom();
  },

  prepend(msgs) {
    const before = this._container.scrollHeight - this._container.scrollTop;
    msgs.reverse().forEach(m =>
      this._items.unshift({ id: m.id, data: m, height: 80, el: null })
    );
    this._render();
    // Восстановить позицию скролла
    this._container.scrollTop = this._container.scrollHeight - before;
  },

  _onScroll() {
    // debounce 16ms
    clearTimeout(this._scrollTimer);
    this._scrollTimer = setTimeout(() => this._render(), 16);
  },

  _render() {
    // Определить visible range
    // Создать/удалить DOM-элементы
    // Добавить spacer div сверху и снизу
  },

  _scrollToBottom() {
    this._container.scrollTop = this._container.scrollHeight;
  }
};
```

> **Заметка:** на первой итерации можно обойтись **без виртуализации** —
> рендерить все сообщения в DOM. Добавить виртуализацию как оптимизацию
> когда чаты вырастут до 500+ сообщений. Приоритет: сначала работает, потом оптимально.

### A.5 `bridge.js` — мост JS → Flutter

```js
// bridge.js
window.GlazeBridge = {
  // JS → Flutter
  send(type, payload) {
    if (window.FlutterBridge) {
      window.FlutterBridge.postMessage(JSON.stringify({ type, payload }));
    }
  },

  // Flutter → JS (вызывается через evaluateJavascript)
  receive(json) {
    const { type, payload } = JSON.parse(json);
    switch (type) {
      case 'init':
        window.GlazeVirtualList.setItems(payload.messages);
        window.GlazeRenderer.applyTheme(payload.theme);
        break;
      case 'append':
        window.GlazeVirtualList.append(payload);
        break;
      case 'prepend':
        window.GlazeVirtualList.prepend(payload.messages);
        break;
      case 'update':
        window.GlazeRenderer.updateMessage(payload.id, payload.text);
        break;
      case 'delete':
        window.GlazeRenderer.deleteMessage(payload.id);
        break;
      case 'theme':
        window.GlazeRenderer.applyTheme(payload);
        break;
      case 'search':
        window.GlazeRenderer.highlightSearch(payload.query, payload.activeIndex);
        break;
      case 'scrollToBottom':
        window.GlazeVirtualList.scrollToBottom();
        break;
      case 'scrollToMessage':
        window.GlazeVirtualList.scrollToId(payload.id);
        break;
    }
  }
};

// Действия пользователя → Flutter
document.addEventListener('click', (e) => {
  const btn = e.target.closest('[data-action]');
  if (!btn) return;
  window.GlazeBridge.send(btn.dataset.action, { id: btn.closest('[data-id]')?.dataset.id });
});
```

### A.6 `styles.css` — глобальные стили чата

```css
/* styles.css */
* { box-sizing: border-box; margin: 0; padding: 0; }

html, body {
  background: var(--chat-bg, transparent);
  font-family: -apple-system, 'Roboto', sans-serif;
  font-size: var(--chat-font-size, 15px);
  line-height: 1.6;
  color: var(--chat-text, #fff);
  overflow-x: hidden;
  height: 100%;
}

.glaze-message {
  padding: 12px 16px;
  display: flex;
  flex-direction: column;
}

/* Стили тела сообщения — внутри Shadow DOM (из ShadowContent.vue) */
/* Экспортируются как window.GlazeStyles.message */
```

Shadow DOM стили (из `ShadowContent.vue` Glaze JS):
```css
/* Вставляются в каждый Shadow Root */
:host { display: block; font-size: inherit; line-height: inherit; color: inherit; }
.content { width: 100%; word-break: break-word; }
p { margin: 0 0 0.8em; }
p:last-child { margin-bottom: 0; }
em { font-style: italic; }
strong { font-weight: bold; }
.chat-quote { color: var(--quote-color, #007AFF); }
.chat-italic { color: var(--italic-color, #888); font-style: italic; }
.chat-blockquote { border-left: 3px solid var(--italic-color, #888); padding: 2px 8px; margin: 4px 0; }
pre.code-block { background: rgba(255,255,255,0.05); border: 1px solid rgba(255,255,255,0.1); padding: 10px; border-radius: 8px; font-family: monospace; font-size: 0.9em; overflow-x: auto; margin: 10px 0; }
hr { border: none; border-top: 1px solid rgba(128,128,128,0.2); margin: 1.5em 0; }
img { max-width: 100%; height: auto; border-radius: 8px; }
.typing-dots-bounce span { display: inline-block; animation: dotBounce 1.4s infinite ease-in-out both; }
@keyframes dotBounce { 0%,80%,100% { transform: translateY(0); opacity: .5; } 40% { transform: translateY(-5px); opacity: 1; } }
```

### A.7 `index.html`

```html
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <link rel="stylesheet" href="styles.css">
</head>
<body>
  <div id="glaze-chat-list"></div>
  <script src="formatter.js"></script>
  <script src="renderer.js"></script>
  <script src="virtual_list.js"></script>
  <script src="bridge.js"></script>
  <script>
    window.GlazeVirtualList.init(document.getElementById('glaze-chat-list'));
    // Сигнал Flutter что WebView готов
    window.GlazeBridge.send('ready', {});
  </script>
</body>
</html>
```

---

## Фаза B: Dart-сторона

### B.1 `ChatWebViewWidget`

```dart
// lib/features/chat/widgets/chat_webview_widget.dart

class ChatWebViewWidget extends ConsumerStatefulWidget {
  const ChatWebViewWidget({super.key});

  @override
  ConsumerState<ChatWebViewWidget> createState() => _ChatWebViewWidgetState();
}

class _ChatWebViewWidgetState extends ConsumerState<ChatWebViewWidget> {
  InAppWebViewController? _controller;
  bool _ready = false;

  @override
  Widget build(BuildContext context) {
    return InAppWebView(
      initialFile: 'assets/chat_webview/index.html',
      initialSettings: InAppWebViewSettings(
        transparentBackground: true,
        javaScriptEnabled: true,
        supportZoom: false,
        disableVerticalScroll: false,  // скролл внутри WebView!
        allowFileAccessFromFileURLs: true,
      ),
      onWebViewCreated: (controller) {
        _controller = controller;
        controller.addJavaScriptHandler(
          handlerName: 'FlutterBridge',
          callback: _onJsMessage,
        );
      },
      onLoadStop: (controller, _) async {
        _ready = true;
        // Отправить начальные данные
        final notifier = ref.read(chatWebViewProvider.notifier);
        notifier.onWebViewReady(controller);
      },
    );
  }

  dynamic _onJsMessage(List<dynamic> args) {
    if (args.isEmpty) return;
    final msg = jsonDecode(args[0] as String) as Map<String, dynamic>;
    final type = msg['type'] as String;
    final payload = msg['payload'];

    switch (type) {
      case 'ready':
        // WebView загружен — отправить сообщения
        break;
      case 'action:swipe':
        ref.read(chatProvider.notifier).swipe(payload['id'] as String, 1);
        break;
      case 'action:regenerate':
        ref.read(chatProvider.notifier).regenerate(payload['id'] as String);
        break;
      case 'action:edit':
        // ...
        break;
      case 'action:delete':
        // ...
        break;
      case 'action:openActions':
        // ...
        break;
      case 'loadMore':
        // Пользователь доскроллил до верха — подгрузить старые сообщения
        ref.read(chatProvider.notifier).loadMoreMessages();
        break;
    }
  }
}
```

### B.2 `_BridgeController` — отправка команд в JS

```dart
// lib/features/chat/services/chat_bridge_controller.dart

class ChatBridgeController {
  final InAppWebViewController _wv;

  ChatBridgeController(this._wv);

  Future<void> init(List<MessageDto> messages, GlazeColors theme) async {
    await _call('init', {
      'messages': messages.map((m) => m.toJson()).toList(),
      'theme': _themeToJson(theme),
    });
  }

  Future<void> append(MessageDto msg) => _call('append', msg.toJson());

  Future<void> prepend(List<MessageDto> msgs) => _call('prepend', {
    'messages': msgs.map((m) => m.toJson()).toList(),
  });

  Future<void> update(String id, String text, {bool isTyping = false}) =>
      _call('update', {'id': id, 'text': text, 'isTyping': isTyping});

  Future<void> delete(String id) => _call('delete', {'id': id});

  Future<void> applyTheme(GlazeColors theme) => _call('theme', _themeToJson(theme));

  Future<void> search(String query, int activeIndex) =>
      _call('search', {'query': query, 'activeIndex': activeIndex});

  Future<void> scrollToBottom() => _call('scrollToBottom', {});

  Future<void> scrollToMessage(String id) => _call('scrollToMessage', {'id': id});

  Future<void> _call(String type, Object payload) async {
    final json = jsonEncode({'type': type, 'payload': payload});
    await _wv.evaluateJavascript(
      source: 'window.GlazeBridge.receive(${jsonEncode(json)})',
    );
  }

  Map<String, dynamic> _themeToJson(GlazeColors t) => {
    'chatBg':      _css(t.chatBg),
    'charBubble':  _css(t.charBubble),
    'userBubble':  _css(t.userBubble),
    'text':        _css(t.text),
    'accent':      _css(t.accent),
    'quoteColor':  _css(t.quoteColor),
    'italicColor': _css(t.italicColor),
  };

  String _css(Color c) =>
      'rgba(${(c.r*255).round()},${(c.g*255).round()},${(c.b*255).round()},${c.a.toStringAsFixed(2)})';
}
```

### B.3 `MessageDto` — DTO для передачи в JS

```dart
// lib/features/chat/models/message_dto.dart

@freezed
class MessageDto with _$MessageDto {
  const factory MessageDto({
    required String id,
    required String role,        // 'user' | 'char'
    required String text,        // после applyRegexes, replaceMacros
    String? reasoning,
    String? time,
    int? genTimeMs,
    int? tokens,
    String? avatarUrl,
    String? avatarLetter,
    String? avatarColor,
    String? senderName,
    bool? isTyping,
    bool? isError,
    bool? isHidden,
    int? swipeIndex,
    int? swipeTotal,
    int? greetingIndex,
    int? greetingTotal,
    List<String>? triggeredLorebooks,
  }) = _MessageDto;

  factory MessageDto.fromJson(Map<String, dynamic> json) =>
      _$MessageDtoFromJson(json);
}
```

Формирование DTO на Dart-стороне происходит **до передачи в JS**:
- `applyRegexes()` — применить regex-скрипты
- `replaceMacros()` — подставить макросы
- Передать уже готовый текст

JS-форматтер принимает **готовый текст** — только Markdown+HTML, никаких макросов.

### B.4 `ChatWebViewNotifier`

```dart
// lib/features/chat/providers/chat_webview_provider.dart

class ChatWebViewNotifier extends AsyncNotifier<void> {
  ChatBridgeController? _bridge;

  @override
  Future<void> build() async {}

  void onWebViewReady(InAppWebViewController controller) {
    _bridge = ChatBridgeController(controller);
    _sendInitialState();
  }

  Future<void> _sendInitialState() async {
    final msgs = ref.read(messagesProvider);
    final theme = ref.read(glazeColorsProvider);
    final dtos = msgs.map(_toDto).toList();
    await _bridge?.init(dtos, theme);
  }

  Future<void> onNewMessage(ChatMessage msg) async {
    await _bridge?.append(_toDto(msg));
  }

  Future<void> onStreamingUpdate(String id, String text) async {
    await _bridge?.update(id, text, isTyping: true);
  }

  Future<void> onStreamingDone(String id, String finalText) async {
    await _bridge?.update(id, finalText, isTyping: false);
  }

  Future<void> onMessageDeleted(String id) async {
    await _bridge?.delete(id);
  }

  Future<void> onThemeChanged(GlazeColors theme) async {
    await _bridge?.applyTheme(theme);
  }

  MessageDto _toDto(ChatMessage msg) {
    // applyRegexes, replaceMacros, формировать DTO
    // ...
  }
}

final chatWebViewProvider = AsyncNotifierProvider<ChatWebViewNotifier, void>(
  ChatWebViewNotifier.new,
);
```

---

## Фаза C: Интеграция в экран чата

### C.1 Замена `ChatMessageList`

Текущий экран чата использует `ListView.builder` с `ChatMessage` виджетами.
Нужно заменить список на `ChatWebViewWidget` который занимает всё пространство.

```dart
// lib/features/chat/screens/chat_screen.dart

// Было:
Expanded(
  child: ChatMessageList(
    messages: messages,
    // ...
  ),
)

// Станет:
Expanded(
  child: ChatWebViewWidget(),
)
```

Кнопки "скролл вниз", "выделение" — остаются нативными Flutter-оверлеями поверх WebView.
Flutter-оверлей через `Stack` + `Positioned`.

### C.2 Стриминг

Во время генерации:
1. `onStreamingUpdate(id, partialText)` → `bridge.update(id, text, isTyping: true)`
2. JS обновляет Shadow DOM сообщения без перерисовки всего списка
3. По завершении `onStreamingDone(id, finalText)` — убирает typing-cursor

### C.3 Пагинация вверх (история)

JS сигналит `loadMore` когда пользователь доскроллил до самого верха:
```js
// virtual_list.js
if (container.scrollTop < 100) {
  window.GlazeBridge.send('loadMore', {});
}
```

Dart подгружает старые сообщения из БД и вызывает `bridge.prepend(msgs)`.
JS вставляет их в начало списка, восстанавливая позицию скролла.

### C.4 Действия над сообщениями

Кнопки (свайп, регенерация, редактирование, удаление) рендерятся в JS.
Нажатие → `GlazeBridge.send('action:xxx', {id})` → Dart `_onJsMessage`.

Кнопки которые открывают Flutter-экраны (шторка лорбука, шторка действий) —
Dart получает событие и открывает нативный `BottomSheet`/`GoRouter`.

### C.5 Режим выделения сообщений

```dart
// Dart включает режим выделения
bridge._call('selectionMode', {'enabled': true});

// JS добавляет класс .selection-mode на контейнер
// Клик по сообщению → 'action:toggleSelect' → Dart
// Dart отправляет обратно 'updateSelected' с массивом id
```

---

## Фаза D: Тема и CSS-переменные

При инициализации и при каждой смене темы Flutter передаёт объект темы в JS.
JS применяет переменные на `document.documentElement`:

```js
// renderer.js
applyTheme(theme) {
  const root = document.documentElement;
  root.style.setProperty('--chat-bg',      theme.chatBg);
  root.style.setProperty('--chat-text',    theme.text);
  root.style.setProperty('--char-bubble',  theme.charBubble);
  root.style.setProperty('--user-bubble',  theme.userBubble);
  root.style.setProperty('--accent',       theme.accent);
  root.style.setProperty('--quote-color',  theme.quoteColor);
  root.style.setProperty('--italic-color', theme.italicColor);
}
```

Внутри Shadow DOM переменные доступны через `:host`:
```css
:host {
  --current-quote-color: var(--quote-color);
  --current-italic-color: var(--italic-color);
}
```

LLM может использовать в своём HTML:
```css
div { border-color: var(--accent); }
p   { color: var(--chat-text); }
```

---

## Фаза E: Поиск по чату

Текущий поиск работает на Dart-стороне через `activeSearchMatchIndex` и
`_highlightPhrases()`. После переезда:

1. Dart получает поисковый запрос
2. `bridge.search(query, activeIndex)` → JS
3. JS ищет по DOM всех Shadow Root через `shadowRoot.querySelectorAll`
4. Оборачивает совпадения в `<mark class="search-highlight">`, активное — `.active-match`
5. `scrollIntoView()` для активного совпадения

```js
// renderer.js
highlightSearch(query, activeIndex) {
  // Снять предыдущие highlights
  document.querySelectorAll('.glaze-message').forEach(el => {
    const content = el.querySelector('.glaze-msg-body')?.shadowRoot?.querySelector('.content');
    if (content) {
      content.innerHTML = content.innerHTML.replace(/<mark[^>]*>(.*?)<\/mark>/g, '$1');
    }
  });

  if (!query) return;

  let matchCount = 0;
  const escaped = query.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const re = new RegExp(`(${escaped})`, 'gi');

  document.querySelectorAll('.glaze-message').forEach(el => {
    const content = el.querySelector('.glaze-msg-body')?.shadowRoot?.querySelector('.content');
    if (!content) return;
    content.innerHTML = content.innerHTML.replace(re, (m) => {
      const cls = matchCount === activeIndex ? 'search-highlight active-match' : 'search-highlight';
      matchCount++;
      return `<mark class="${cls}">${m}</mark>`;
    });
  });
}
```

---

## Что удаляется после полного переезда

| Файл/компонент | Статус |
|---|---|
| `lib/features/chat/widgets/html_block_view.dart` | Удалить |
| `splitContentSegments()` в `html_to_markdown.dart` | Удалить |
| `hasBlockHtml()` в `html_to_markdown.dart` | Удалить (или оставить для превью) |
| `HtmlBlockView` ветка в `message.dart` | Удалить |
| `ChatMessageList` (ListView.builder) | Удалить |
| `GptMarkdown` в `message.dart` | Удалить |
| `_highlightPhrases()` в `message.dart` | Удалить (перенесено в JS) |
| `flutter_inappwebview` per-message настройки | Остаётся, но 1 instance |

**Остаётся:**
- `html_to_markdown.dart` — для превью карточек, экспорта
- `colored_markdown.dart`, кастомные InlineMd — для не-чатовых контекстов

---

## Итоговая схема рендеринга

```
Входящий текст от LLM (Dart)
        │
        ▼
applyRegexes()              ← пользовательские regex-скрипты
replaceMacros()             ← {{char}}, {{user}}, etc.
        │
        ▼
MessageDto.toJson()
        │  JSON через evaluateJavascript
        ▼
formatter.js: format(text)
  ├─ Извлечь code/style/script блоки
  ├─ Защитить HTML-теги
  ├─ Цитаты → .chat-quote
  ├─ *italic* → .chat-italic
  ├─ **bold** → <strong>
  ├─ Параграфы и переносы
  └─ Вернуть блоки
        │
        ▼
renderer.js: createMessage(msg)
  Shadow DOM (изоляция CSS)
  innerHTML = html
        │
        ▼
virtual_list.js: append/update
  Только видимые элементы в DOM
        │
        ▼
WebView рисует
```

---

## Чеклист реализации

### Фаза A — JS-бандл ✅
- [x] **A.1** Создать `assets/chat_webview/`, добавить в `pubspec.yaml`
- [x] **A.2** `formatter.js` — портировать `textFormatter.js` из Glaze JS
- [x] **A.3** `renderer.js` — рендерер с Shadow DOM
- [x] **A.4** `virtual_list.js` — без виртуализации на первой итерации
- [x] **A.5** `bridge.js` — мост JS ↔ Flutter (класс `Bridge`, методы `setMessages`, `appendMessage`, `prependMessages`, `updateMessage`, `removeMessage`, `clearAll`, `updateStreaming`, `applyTheme`)
- [x] **A.6** `styles.css` — глобальные + Shadow DOM стили из ShadowContent.vue
- [x] **A.7** `index.html` — точка входа, создание `window.bridge`

### Фаза B — Dart-сторона ✅
- [x] **B.1** `ChatWebViewWidget` — ConsumerStatefulWidget с InAppWebView, логика синхронизации в `_syncMessages()`
- [x] **B.2** `ChatBridgeController` — методы отправки команд в JS (`setMessages`, `appendMessage`, `appendMessages`, `prependMessages`, `updateMessage`, `removeMessage`, `clearAll`, `scrollToBottom`, `scrollToMessage`, `setSearch`, `applyTheme`, `updateStreaming`)
- [x] **B.3** `MessageDto` — Freezed DTO + `toJson()` (временно не используется, используется `ChatMessage`)
- [x] **B.4** ~~`ChatWebViewNotifier`~~ — удален, логика перенесена в `ChatWebViewWidget` для упрощения архитектуры

### Фаза C — Интеграция ⏳
- [x] **C.1** Заменить `ChatMessageList` на `ChatWebViewWidget` в экране чата
- [x] **C.2** Подключить стриминг через `ref.listen<StreamingState>()` в виджете
- [ ] **C.3** Пагинация вверх (`loadMore` сигнал из JS) — базовая логика есть, требует тестирования
- [ ] **C.4** Все действия над сообщениями через мост (свайп, регенерация, редактирование)
- [ ] **C.5** Режим выделения сообщений

**Коммит:** `de82c5e` — feat: Phase C — интеграция ChatWebView в экран чата

### Фаза D — Тема (не начата)
- [ ] **D.1** `applyTheme()` в JS — метод есть, нужно передавать CSS-переменные для пузырей сообщений
- [ ] **D.2** CSS-переменные в Shadow DOM через `:host`
- [ ] **D.3** Реагировать на смену темы из Flutter (через `ref.listen` в виджете)

### Фаза E — Поиск (не начата)
- [ ] **E.1** `highlightSearch()` в JS через Shadow DOM — метод `setSearch()` есть в мосту
- [ ] **E.2** `scrollIntoView` для активного совпадения
- [ ] **E.3** Убрать `_highlightPhrases()` из Dart после миграции

### Финал — Cleanup (после всех фаз)
- [ ] Удалить `html_block_view.dart`
- [ ] Удалить `ChatMessageList` (уже удален из chat_screen.dart, но файл остался)
- [ ] Удалить `GptMarkdown`-ветку из `message.dart`
- [ ] Удалить per-message WebView настройки
- [ ] Обновить `HTML_RENDERING_PLAN.md` — пометить фазы 3+ как замененные этим документом
