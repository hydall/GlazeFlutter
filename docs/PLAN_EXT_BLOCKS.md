# Plan: Ext Blocks Redesign — ВЫПОЛНЕНО ✓

> Local-only file — gitignored. Do not commit.

**Статус:** все фазы завершены (1–7). Документация обновлена.
**Схема:** v22. Тесты: 490/490.

---

## Концепция

- Блоки **привязаны к сообщению** (messageId уже есть в DB)
- **Badge** рядом с memory-badge в WebView → клик → **inline-раскрытие** под сообщением
- `ExtBlocksSettingsSheet` и `InfoBlockDrawerWidget` — **удалить полностью**
- Управление пресетами: Magic Drawer → Ext Blocks → шит выбора пресета → Edit → `PresetEditorScreen`
- Порядок выполнения: `order` + флаг `dependsOnPrevious`, параллельно где можно
- Картинки: тот же формат `[IMG:RESULT:<filepath>]`, файл через `ImageStorageService`, путь в `InfoBlock.content`

---

## Фаза 1 — Модели и DB (schema v22) ✓

### 1.1 Новый enum
`lib/features/extensions/models/block_run_status.dart`
```dart
enum BlockRunStatus { pending, running, done, error, stopped }
```

### 1.2 `BlockConfig` (freezed)
- **Убрать:** `contextMessageCount`, `contextBlockCount`
- **Переименовать:** `injectDepth` → `injectLastN: int` (к скольким последним assistant-сообщениям инжектировать)
- **Добавить:** `order: int` (default 0), `dependsOnPrevious: bool` (default false)

### 1.3 `InfoBlock` (freezed)
- **Добавить:** `status: BlockRunStatus` (default `done` — обратная совместимость), `order: int` (default 0)

### 1.4 Migration v22 — `lib/core/db/app_db.dart`
```dart
if (from < 22) {
  await m.addColumn(infoBlocks, infoBlocks.order_);   // INTEGER DEFAULT 0
  await m.addColumn(infoBlocks, infoBlocks.status);   // TEXT DEFAULT 'done'
}
// schemaVersion => 22
```
`lib/core/db/tables.dart` — добавить `IntColumn get order_` и `TextColumn get status` в `InfoBlocks`.

### 1.5 `InfoBlocksRepository` — новые методы
- `getByMessageId(sessionId, messageId)` → `List<InfoBlock>` ordered by `order` asc
- `updateStatus(id, BlockRunStatus)` — атомарный update одного поля
- Обновить `getRecentBlocks` — сортировать по `order` asc внутри группы

### 1.6 Регенерация
```
dart run build_runner build
```

---

## Фаза 2 — Логика выполнения ✓

> Читать перед правками: `docs/rules/generation.md`, `docs/rules/race-conditions.md`

### 2.1 `ExtensionPostGenService` — переписать
```
blocks = preset.blocks.where(enabled).sortBy(order)
prevOutput = null
for block in blocks:
  if block.dependsOnPrevious: await последовательно
  else: Future без await (параллельно с предыдущим)

  repo.updateStatus(block.id, running)
  result = await _runBlock(block, prevOutput)
  repo.updateStatus(block.id, done/error)
  prevOutput = result.content
```

### 2.2 `_runBlock` — диспетчер по типу блока
- `BlockType.infoblock` → `InfoBlockService._generateSingleBlock(block, prevOutput)`
- `BlockType.imageGen` → inline логика (см. 2.3)
- `BlockType.jsRunner` → заглушка (тип зарегистрирован, выполнение placeholder)

### 2.3 `BlockType.imageGen` в цепочке (убрать `ImageBlockService`)
- Получает `previousBlockOutput` (вывод infoblock)
- Ищет `[img gen:...]` в ответе ассистента ИЛИ в `previousBlockOutput`
- Генерирует через `ImageGenService.generateImage()`
- Сохраняет через `ImageStorageService`
- Записывает в `InfoBlock.content` → `[IMG:RESULT:<filepath>]`

### 2.4 `injectLastN` в `InfoBlockService._buildInfoblockPrompt`
- При сборке промпта: берём историю, находим последние `injectLastN` assistant-сообщений
- Для каждого — `getByMessageId()` → вставляем как system-блок перед тем сообщением

### 2.5 Стоп блоков
- Отдельный `extensionBlocksCancelToken` — проверяем в каждом `await` внутри `_runBlock`
- При отмене → `updateStatus(id, stopped)` для всех `running`
- Guard: если основная генерация прервана до финала → блоки не запускаются

### 2.6 Ре-генерация одного блока
Новый метод `ExtensionPostGenService.rerunBlock(blockId, messageId, sessionId)`.

---

## Фаза 3 — Провайдер статуса ✓

### 3.1 Новый провайдер
`extensionBlockRunProvider(sessionId)` — `StateNotifierProvider` с `Map<messageId, List<InfoBlock>>`.
Загружается по требованию + получает live-обновления через `updateStatus`.

### 3.2 Bridge-обновление при смене статуса
При смене статуса блока → `ChatBridgeController.updateBlockStatus(messageId, aggregatedStatus)` → `callJs('updateMessage', ...)`.

---

## Фаза 4 — WebView: badge + inline-раскрытие ✓

### 4.1 `ChatMessageMapper.toMap()` — добавить `blockStatus: String?`
- `'running'` если хоть один блок running
- `'done'` если все done
- `'error'` если есть error
- `null` если нет блоков
- Данные из `ChatMessageMapperContext.blockStatusByMessageId`

### 4.2 `ChatBridgeController`
- Добавить `Map<String, String> blockStatusByMessageId`
- Новый метод `updateBlockStatus(messageId, status)` → `callJs('updateMessage', ...)`

### 4.3 `renderer.js` — ext-blocks badge в `_createHeader()` (после memory badge, line ~361)
```javascript
if (m.blockStatus) {
  const badge = document.createElement('button');
  badge.type = 'button';
  badge.className = `msg-ext-badge ${m.blockStatus}`;
  badge.dataset.action = 'ext-blocks-click';
  badge.dataset.messageId = m.id;
  badge.textContent = '⬡';
  nameEl.appendChild(badge);
}
```

### 4.4 `updateMessageMeta()` (line ~1033) — обновлять ext-blocks badge аналогично memory badge

### 4.5 `styles.css` — новые классы
```css
.msg-ext-badge { /* аналог .msg-memory-badge */ }
.msg-ext-badge.running { color: #ffd700; animation: pending-pulse 2s ease-in-out infinite; }
.msg-ext-badge.done    { color: #4caf50; }
.msg-ext-badge.error   { color: #ff7b7b; }
/* В .native-lite: .msg-ext-badge.running { animation: none; } */
```

### 4.6 `bridge.js` — handler `ext-blocks-click`
```javascript
case 'ext-blocks-click':
  this._sendToFlutter('onExtBlocksClick', [el.dataset.messageId]);
  break;
```

### 4.7 `bridge.js` — новый метод `showExtBlocksPanel(messageId, blocksJson)`
- Вставляет/убирает `<div class="ext-blocks-panel">` внутри секции сообщения
- Содержимое: список блоков (имя, статус, контент; для imageGen — `<img>` по `file://...` пути)
- Кнопки: "Стоп" → `_sendToFlutter('onExtBlockStop', [messageId, blockId])`
- Кнопки: "Регенерировать" → `_sendToFlutter('onExtBlockRegen', [messageId, blockId])`

### 4.8 `ChatBridgeController` — слушать handlers
- `onExtBlocksClick(messageId)` → загрузить блоки из провайдера → `callJs('showExtBlocksPanel', ...)`
- `onExtBlockStop(messageId, blockId)` → отменить через `extensionBlocksCancelToken`
- `onExtBlockRegen(messageId, blockId)` → `ExtensionPostGenService.rerunBlock(...)`

### 4.9 `bridge.js` — новый метод `updateExtBlocksPanel(messageId, blocksJson)`
Вызывается при обновлении статуса, обновляет открытую панель если она видима.

---

## Фаза 5 — UI: PresetEditorScreen + Magic Drawer ✓

### 5.1 `PresetEditorScreen` (`_BlockEditDialog`)
- Убрать поля: `contextMessageCount`, `contextBlockCount`
- Переименовать: `injectDepth` → `injectLastN`, подпись: "К скольким посл. сообщениям ассистента"
- Добавить: toggle `dependsOnPrevious` ("Ждать завершения предыдущего блока")
- Список блоков: `ReorderableListView` → drag-to-reorder → обновляет `order` у всех блоков

### 5.2 Удалить
- `lib/features/extensions/widgets/ext_blocks_settings_sheet.dart`
- `lib/features/extensions/widgets/info_block_drawer_widget.dart`

### 5.3 Magic Drawer (`magic_drawer.dart`)
Тап по "Ext Blocks" → новый упрощённый шит: выбор активного пресета + кнопка Edit → `PresetEditorScreen`.

---

## Фаза 6 — Чистка ✓

- Удалить `ImageBlockService` и `imageBlockServiceProvider`
- Удалить `contextMessageCount` / `contextBlockCount` из всего кода
- Убрать `InfoBlockDrawerWidget` из `chat_screen.dart`
- `flutter analyze` → исправить все ошибки

---

## Фаза 7 — Документация ✓

### 7.1 `docs/ARCHITECTURE.md`
- DB tables: schema v22, новые колонки `info_blocks.order`, `info_blocks.status`
- Extensions: обновить диаграмму цепочки блоков
- Generation pipeline шаг 6: новая логика
- Удалить упоминания `InfoBlockDrawerWidget`, `ImageBlockService`

### 7.2 `docs/INVARIANTS.md`
Обновить INV-EG1–3. Добавить:
- **INV-EG4**: Блоки не запускаются если основная генерация прервана до финала
- **INV-EG5**: Стоп блоков (`extensionBlocksCancelToken`) не прерывает основную генерацию
- **INV-EG6**: `dependsOnPrevious=true` — блок не стартует пока предыдущий не завершился (done или error)
- **INV-EG7**: img-gen блок сохраняет результат через `ImageStorageService`; `InfoBlock.content` хранит `[IMG:RESULT:<path>]`

### 7.3 `docs/rules/database.md`
- Добавить schema v22 в историю миграций
- Упомянуть `updateStatus` как пример атомарного single-column update

---

## Карта изменений по файлам

| Файл | Действие |
|------|----------|
| `models/block_run_status.dart` | Создать |
| `models/block_config.dart` | Изменить |
| `models/info_block.dart` | Изменить |
| `core/db/tables.dart` | +2 колонки в InfoBlocks |
| `core/db/app_db.dart` | Migration v22, schemaVersion→22 |
| `core/db/repositories/info_blocks_repository.dart` | Новые методы |
| `services/extension_post_gen_service.dart` | Переписать |
| `services/info_block_service.dart` | Добавить injectLastN |
| `services/image_block_service.dart` | **Удалить** |
| `screens/preset_editor_screen.dart` | Изменить |
| `widgets/ext_blocks_settings_sheet.dart` | **Удалить** |
| `widgets/info_block_drawer_widget.dart` | **Удалить** |
| `chat/widgets/magic_drawer.dart` | Новый шит Ext Blocks |
| `chat/bridge/chat_message_mapper.dart` | +`blockStatus` |
| `chat/bridge/chat_bridge_controller.dart` | +`blockStatusByMessageId`, +`updateBlockStatus` |
| `assets/chat_webview/renderer.js` | Badge + inline panel |
| `assets/chat_webview/bridge.js` | Handlers + `showExtBlocksPanel` |
| `assets/chat_webview/styles.css` | `.msg-ext-badge` стили |
| `docs/ARCHITECTURE.md` | Обновить |
| `docs/INVARIANTS.md` | Обновить |
| `docs/rules/database.md` | Обновить |
