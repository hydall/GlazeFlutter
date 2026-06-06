# Plan: Ext Blocks Redesign — DONE

> Local-only file — gitignored. **All phases completed in branch
> `js-extension-bridge-sdk` (commits `b2718e7` … `9923b95`).**
>
> The redesigned ext-blocks feature is described in:
>
> * `docs/ARCHITECTURE.md` § 9 (Extensions + JS Bridge SDK)
> * `docs/INVARIANTS.md` INV-EG1–INV-EG8 and INV-JS1–INV-JS6
> * `docs/js_extensions_implementation_plan.md` (live plan / final state)

---

## Статус

| Фаза | Описание | Статус |
|------|----------|--------|
| 1 | Модели и DB (schema v22) | ✓ |
| 2 | Логика выполнения (цепочка, cancel, rerun) | ✓ |
| 3 | Провайдер статуса | ✓ |
| 4 | WebView: badge + inline-раскрытие | ✓ |
| 5 | UI: PresetEditorScreen + Magic Drawer | ✓ |
| 6 | Чистка | ✓ |
| 7 | Документация | ✓ |
| 8 | Bridge callbacks (подключить обработчики) | ✓ |
| 9 | Context Builder (contextMessageCount + contextSystemPrompt) | ✓ |
| 10 | JS Runner (iframe sandbox) | ✓ |
| 11 | Capability permissions (`PresetPermissions`, 19 toggles) | ✓ |
| 12 | Headless JS engine (`JsEngineService` + `headless.html`) | ✓ |
| 13 | Interactive HTML panels (`PanelHostService`, `sandbox="allow-scripts"`) | ✓ |
| 14 | JS Bridge SDK (`window.glaze`) + `JsBridgeService` | ✓ |
| 15 | `triggerGeneration` через `ChatNotifier` (`GenerationDispatcher`) | ✓ |
| 16 | Periodic + afterUser триггеры (`PeriodicTriggerScheduler`) | ✓ |
| 17 | Global / message variable scopes (`GlobalVariablesRepo`, `MessageVariablesNotifier`) | ✓ |
| 18 | `audioplayers`-backed audio (`AudioBridgeService`) | ✓ |
| 19 | `executeCommand` wired registry (`/trigger` / `/getvar` / `/setvar` / `/inject` / `/toast`) | ✓ |
| 20 | Connection profiles (big/medium/small → `ApiConfig`) | ✓ |

См. `docs/js_extensions_implementation_plan.md` для текущего состояния
bridge surface.

---

## Концепция (исходная)

- Блоки **привязаны к сообщению** (messageId уже есть в DB)
- **Badge** рядом с memory-badge в WebView → клик → **inline-раскрытие** под сообщением
- Управление пресетами: Magic Drawer → Ext Blocks → шит выбора пресета → Edit → `PresetEditorScreen`
- Порядок выполнения: `order` + флаг `dependsOnPrevious`, параллельно где можно
- Картинки: тот же формат `[IMG:RESULT:<filepath>]`, файл через `ImageStorageService`, путь в `InfoBlock.content`

---

## Фаза 1–7 ✓ (выполнено в коммите 73e9afa)

Детали в git history.

---

## Фаза 8 — Bridge callbacks ⏳

> **Критично**: без этого пользователь не может взаимодействовать с ext-blocks панелью в WebView.
> Три handler-а объявлены и зарегистрированы в `bridge_handlers.dart`, но нигде не назначены.

### 8.1 Найти место назначения callbacks

В `ChatWebViewWidget` (или там где назначаются `onMemoryClick`, `onImgRegen` и т.д.) назначить:

```dart
bridgeController.onExtBlocksClick = (messageId) async {
  final blocks = ref.read(infoBlocksProvider(sessionId))
      .getByMessageId(messageId);
  final json = blocks.map((b) => b.toMap()).toList();
  await bridgeController.showExtBlocksPanel(messageId, json);
};

bridgeController.onExtBlockStop = (blockId, messageId) {
  ref.read(extensionPostGenServiceProvider).cancelBlocks();
};

bridgeController.onExtBlockRegen = (blockId, messageId) async {
  await ref.read(extensionPostGenServiceProvider)
      .rerunBlock(blockId, messageId, sessionId);
};
```

### 8.2 `InfoBlock.toMap()` для bridge

Добавить метод `toMap()` → `Map<String, dynamic>` с полями:
`id`, `blockId`, `name` (из BlockConfig), `status`, `content`, `order`, `type`.

Имя (`name`) и тип (`type`) берутся из пресета по `blockId` — нужно передавать их при вызове или
хранить денормализованно в `InfoBlock`.

**Решение:** денормализовать `blockName: String` и `blockType: String` в `InfoBlock` при создании —
не нужно каждый раз читать пресет из провайдера в bridge callback.

### 8.3 `showExtBlocksPanel` — формат блоков для JS

```json
[
  { "id": "...", "blockId": "...", "name": "Сцена", "type": "infoblock",
    "status": "done", "content": "...", "order": 0 },
  { "id": "...", "blockId": "...", "name": "Картинка", "type": "imageGen",
    "status": "running", "content": "", "order": 1 }
]
```

Для `imageGen` с `status=done` — content содержит `[IMG:RESULT:<path>]`,
JS парсит путь и рендерит `<img src="...">`.

### 8.4 Файлы

| Файл | Изменение |
|------|-----------|
| `models/info_block.dart` | +`blockName`, +`blockType` (денормализация) |
| `models/info_block.freezed.dart` | регенерировать |
| `providers/info_blocks_provider.dart` | `toMap()` или extension метод |
| `chat/widgets/chat_webview_widget.dart` | назначить 3 callback-а |
| `chat/bridge/chat_bridge_controller.dart` | убедиться что `showExtBlocksPanel` корректен |

---

## Фаза 9 — Context Builder (минимальный) ⏳

> Самая полезная пользовательская фича. Без неё imageGen-блок получает 10 последних сообщений
> — слишком много, нерелевантно. Пользователь не может настроить контекст второй модели.

Не делаем полный drag-n-drop Context Builder как в ExtBlocks.
Добавляем **два поля** в `BlockConfig` — это закрывает 90% use-cases.

### 9.1 `BlockConfig` — два новых поля

```dart
@Default(10) int contextMessageCount,  // сколько последних сообщений видит блок
@Default('') String contextSystemPrompt, // произвольный system-текст (описание персонажей, стиль и т.д.)
```

`contextMessageCount`:
- `0` = только системный промпт + карточка персонажа, без истории сообщений
- `n` = последние n сообщений (user + assistant чередуются)
- `-1` = весь контекст

`contextSystemPrompt`:
- Вставляется как system-сообщение перед историей
- Поддерживает макросы: `{{char}}`, `{{user}}`, `{{description}}`, `{{personality}}`
- Для imageGen: здесь описываем внешность персонажей, стиль изображений

### 9.2 `InfoBlockService` — использовать `contextMessageCount`

Заменить хардкод `_buildContextMessages(messages, 10)` на `_buildContextMessages(messages, blockConfig.contextMessageCount)`.

### 9.3 `InfoBlockService` — вставить `contextSystemPrompt`

После подстановки макросов добавить как первое system-сообщение в список для LLM.

### 9.4 UI — `_BlockEditDialog` в `PresetEditorScreen`

Добавить два поля в диалог редактирования блока:

```
[Числовое поле] "Сообщений контекста"
  helper: "0 — только карточка персонажа, -1 — весь чат"

[Многострочный TextField] "Системный контекст"
  hint: "Описание персонажей, стиль, дополнительные инструкции..."
  maxLines: 5
```

Показывать оба поля для типов `infoblock` и `imageGen`.

### 9.5 DB — schema v23

```dart
// tables.dart — InfoBlocks: без изменений (contextMessageCount и contextSystemPrompt хранятся в ExtensionPreset.blocks JSON)
// Нет изменений в DB — оба поля в BlockConfig (freezed JSON в Drift ExtensionPresets.blocksJson)
```

Миграция DB **не нужна** — `BlockConfig` сериализуется как JSON в `extension_presets.blocks_json`,
новые поля с default-значениями подхватятся автоматически при десериализации.

### 9.6 Файлы

| Файл | Изменение |
|------|-----------|
| `models/block_config.dart` | +`contextMessageCount`, +`contextSystemPrompt` |
| `models/block_config.freezed.dart` | регенерировать |
| `services/info_block_service.dart` | использовать `contextMessageCount`, вставлять `contextSystemPrompt` |
| `screens/preset_editor_screen.dart` | два новых поля в `_BlockEditDialog` |
| `docs/ARCHITECTURE.md` | обновить таблицу полей BlockConfig |

---

## Фаза 10 — JS Runner ⏳

### Решение по безопасности: iframe sandbox в Chat WebView

**Почему не QuickJS (`flutter_js`):** нет новых зависимостей; пользовательский скрипт
может делать `fetch` — это намеренно разрешено (полезно для интеграций).

**Почему не тот же WebView напрямую:** скрипт получил бы доступ к `window.bridge`,
`window.flutter_inappwebview` и мог бы вызвать любой bridge-handler.

**Почему не Shadow DOM:** Shadow DOM изолирует CSS/DOM-дерево, но не JS-execution context.
Скрипт в Shadow DOM всё равно имеет полный доступ к `window`.

**Выбор — `<iframe sandbox="allow-scripts">`:**
- Выполняется в том же Chat WebView через `callAsyncJavaScript()`
- `sandbox="allow-scripts"` без `allow-same-origin` → iframe получает null origin
- Нет доступа к `window.parent` (cross-origin barrier)
- Нет доступа к `window.flutter_inappwebview` (он в parent)
- API keys физически недостижимы — они в Drift (нативная сторона), в JS их нет
- `fetch` разрешён — пользователь может вызвать внешние API намеренно
- Данные (messages, character) передаются через `postMessage` — только то что мы решим передать

**Аналог:** JS-Slash-Runner (831 stars) использует тот же паттерн: `<iframe srcdoc>` +
`postMessage` для изоляции пользовательских скриптов. Они честно предупреждают что
абсолютной защиты нет — но ключи не в JS-контексте у нас по архитектуре.

### 10.1 `BlockConfig` — поле `script`

```dart
@Default('') String script,  // JS-код для jsRunner блока
```

### 10.2 `ExtensionPostGenService._runJsRunner()`

```dart
Future<InfoBlock?> _runJsRunner({
  required InfoBlock placeholder,
  required BlockConfig blockConfig,
  required List<ChatMessage> messages,
  required Character? character,
  required String? previousOutput,
}) async {
  final controller = _ref.read(chatBridgeControllerProvider(charId));
  final result = await controller.runJsBlock(
    script: blockConfig.script,
    messages: messages,
    character: character,
    previousOutput: previousOutput,
    cancelToken: _blocksCancelToken,
  );
  // result — строка из postMessage или null при отмене/ошибке
  ...
}
```

### 10.3 `ChatBridgeController.runJsBlock()`

Новый метод. Алгоритм:

```
1. Сериализовать контекст в JSON (messages последние N, character fields без id/avatarPath)
2. Вызвать callAsyncJavaScript(functionBody: _runSandboxedScript(script, contextJson))
3. Ждать результата (таймаут 60s)
4. Вернуть строку результата или бросить исключение
```

### 10.4 `bridge.js` / `sandbox_runner` — функция `_runSandboxedScript`

```javascript
async function _runSandboxedScript(script, contextJson) {
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => {
      iframe.remove();
      reject(new Error('JS runner timeout'));
    }, 55000);

    const sandboxHtml = `
      <!DOCTYPE html><html><body><script>
        const context = ${contextJson};
        window.addEventListener('message', () => {});
        // пользовательский скрипт оборачивается в async IIFE
        (async () => { ${script} })()
          .then(r => parent.postMessage({ok: true, result: String(r ?? '')}, '*'))
          .catch(e => parent.postMessage({ok: false, error: e.message}, '*'));
      <\/script></body></html>`;

    const iframe = document.createElement('iframe');
    iframe.sandbox = 'allow-scripts';  // БЕЗ allow-same-origin
    iframe.style.display = 'none';
    iframe.srcdoc = sandboxHtml;

    window.addEventListener('message', function handler(e) {
      if (e.source !== iframe.contentWindow) return;
      clearTimeout(timeout);
      iframe.remove();
      window.removeEventListener('message', handler);
      if (e.data.ok) resolve(e.data.result);
      else reject(new Error(e.data.error));
    });

    document.body.appendChild(iframe);
  });
}
```

**Ключевые моменты безопасности:**
- `sandbox="allow-scripts"` без `allow-same-origin` → null origin → нет доступа к parent
- `e.source !== iframe.contentWindow` — проверяем источник postMessage
- Таймаут 55s (чуть меньше Dart-таймаута 60s)
- iframe удаляется сразу после ответа
- В `contextJson` не передаём: `apiConfigId`, `id` персонажа, пути к файлам, другие сессии

### 10.5 Контекст, доступный скрипту

```js
const context = {
  messages: [
    { role: 'user'|'assistant', text: '...' },
    ...  // последние contextMessageCount сообщений
  ],
  character: {
    name: '...',
    description: '...',
    personality: '...',
    scenario: '...',
  },
  previousOutput: '...' | null,  // вывод предыдущего блока в цепочке
};
```

Скрипт должен вернуть строку — она станет `InfoBlock.content`.

**Пример скрипта:**
```js
// Подсчитать количество реплик персонажа
const count = context.messages.filter(m => m.role === 'assistant').length;
return `Реплик персонажа: ${count}`;
```

### 10.6 Редактор блока — `jsRunner` тип в UI

Когда выбран `jsRunner`:
- Скрыть `prompt`, `apiConfigId`, `model`, `inject`, `injectLastN`
- Показать `TextField` для `script` — моноширинный шрифт (`fontFamily: 'monospace'`), много строк (`maxLines: 20, minLines: 8`)
- Подпись: "JavaScript", helper: "Скрипт получает `context` и должен вернуть строку"

### 10.7 `BlockType.jsRunner` в сегментированной кнопке

Добавить третий сегмент:
```dart
ButtonSegment(
  value: BlockType.jsRunner,
  label: Text('JS'),
  icon: Icon(Icons.code),
),
```

### 10.8 Файлы

| Файл | Изменение |
|------|-----------|
| `models/block_config.dart` | +`script: String` |
| `models/block_config.freezed.dart` | регенерировать |
| `services/extension_post_gen_service.dart` | `_runJsRunner()` |
| `chat/bridge/chat_bridge_controller.dart` | `runJsBlock()` |
| `assets/chat_webview/bridge.js` | `_runSandboxedScript()` |
| `screens/preset_editor_screen.dart` | jsRunner сегмент + code editor field |
| `docs/ARCHITECTURE.md` | JS Runner секция |
| `docs/INVARIANTS.md` | INV-EG8: sandbox isolation |

### 10.9 INV-EG8 (добавить в INVARIANTS.md)

**INV-EG8: JS Runner выполняется в изолированном iframe-sandbox без доступа к bridge**

`ChatBridgeController.runJsBlock()` создаёт `<iframe sandbox="allow-scripts">` (без
`allow-same-origin`) через `callAsyncJavaScript`. Null origin блокирует доступ к
`window.parent` и `window.flutter_inappwebview`. Контекст передаётся только через
`postMessage` и содержит исключительно текстовые данные чата (без API keys, без путей,
без id других сессий). Таймаут 60s — после него iframe удаляется и блок помечается `error`.

---

## Итоговый порядок реализации

```
Фаза 8  — Bridge callbacks    [критично, ~1-2ч]
Фаза 9  — Context Builder     [высокий приоритет, ~2-3ч]
Фаза 10 — JS Runner           [средний приоритет, ~4-6ч]
```

---

## Карта файлов (фазы 8–10)

| Файл | Фаза | Действие |
|------|------|----------|
| `models/info_block.dart` | 8 | +`blockName`, +`blockType` |
| `chat/widgets/chat_webview_widget.dart` | 8 | назначить 3 callback-а |
| `models/block_config.dart` | 9, 10 | +`contextMessageCount`, +`contextSystemPrompt`, +`script` |
| `services/info_block_service.dart` | 9 | использовать `contextMessageCount` + `contextSystemPrompt` |
| `screens/preset_editor_screen.dart` | 9, 10 | новые поля в диалоге + jsRunner UI |
| `services/extension_post_gen_service.dart` | 10 | `_runJsRunner()` |
| `chat/bridge/chat_bridge_controller.dart` | 8, 10 | callbacks + `runJsBlock()` |
| `assets/chat_webview/bridge.js` | 10 | `_runSandboxedScript()` |
| `docs/ARCHITECTURE.md` | 10 | JS Runner секция |
| `docs/INVARIANTS.md` | 10 | INV-EG8 |
