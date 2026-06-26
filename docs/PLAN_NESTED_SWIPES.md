# PLAN: Nested Swipes — агентский под-слой свайпов

Статус: **DRAFT / RFC**. Ждёт решения владельца перед реализацией.

## 1. Проблема

Сейчас свайпы плоские: `swipes[]` — один массив, куда падают и полные
регены, и клинер, и реген финалки. Это создаёт путаницу:

- Клинер добавляет свайп рядом с регеном — визуально неразличимо, что есть что.
- Нет способа посмотреть «какой был сырой ответ до клинера» для конкретного
  регена финалки.
- Пользователь не понимает, свайпает он по «вариантам сцены» или по
  «клинер vs сырой».

## 2. Предлагаемая модель

Два уровня свайпов:

```
Основной свайп (зелёная иконка) — полный реген (все агенты + финал)
  │
  ├── синий 0: финалка (сырой ответ)
  ├── синий 1: клинер от синего 0
  ├── синий 2: реген финалки (новый сырой ответ)
  ├── синий 3: клинер от синего 2
  └── ...

Основной свайп 1 (полный реген)
  ├── синий 0: финалка
  ├── синий 1: клинер
  └── ...
```

**Синие свайпы — линейная последовательность** внутри зелёного.
Финал и клинер чередуются: `финал → клинер → реген-финала → клинер → ...`

Пользователь свайпает синие — перебирает «финал/клинер/реген-финала/клинер»
внутри одного полного прогона. Свайпает зелёные — перебирает полные прогоны
(всё с нуля, включая промежуточных агентов).

## 3. Модель данных

### Вариант A: новое поле `agentSwipes` (рекомендуется)

Добавить в `ChatMessage`:

```dart
@Default([]) List<AgentSwipe> agentSwipes,   // синий под-слой
@Default(0) int agentSwipeId,                 // активный синий индекс
```

Где `AgentSwipe`:

```dart
class AgentSwipe {
  final String content;        // текст ответа
  final String kind;           // 'final' | 'cleaned'
  final String? reasoning;     // reasoning финалки
  final String? genTime;
  final int? tokens;
  final List<Map<String,dynamic>> studioOutputs;  // briefs агентов
  final int? parentSwipeId;    // для 'cleaned' — какой 'final' породил
}
```

Старое поле `swipes[]` остаётся **только для зелёных** (полные регены).
`swipesMeta[]` привязан к зелёным. `agentSwipes[]` — к синим.

**Миграция старых данных:**
- Если у сообщения есть swipes, но нет agentSwipes → создаём один agentSwipe
  `{content: swipes[swipeId], kind: 'final'}` на каждый существующий swipe.
- Это no-op для юзера — он видит прежний ответ + один синий свайп под ним.

**Плюсы:** не ломает существующую логику зелёных свайпов. Чистое разделение.
**Минусы:** +2 поля в модели, +1 класс, миграция.

### Вариант B: плоский массив с тегом `kind`

Оставить один `swipes[]`, но каждое значение тегировать:

```dart
// swipesMeta[i] = {..., 'kind': 'final'|'cleaned', 'parentSwipeId': int?}
```

UI сам разделяет на «зелёные группы» по `parentSwipeId`.

**Плюсы:** минимум изменений модели.
**Минусы:** UI-логика усложняется (группировка на лету), конфликтует с
существующей логикой changeSwipe (которая считает свайпы линейными).

### Решение: Вариант A

## 4. UX

### Иконки свайпов

| Иконка | Цвет | Что |
|---|---|---|
| Зелёная | primary | Основной свайп (полный реген) |
| Синяя | tertiary | Агентский под-свайп (финал/клинер/реген-финала) |

**Расположение:** синяя иконка слева от зелёной, обе внизу сообщения.

### Поведение

- **Свайп синей →** перебор внутри текущего зелёного: финал → клинер →
  реген-финала → клинер → ...
- **Свайп синей вправо за край →** автоматически свайпает зелёную (следующий
  полный прогон).
- **Свайп зелёной →** меняет полный прогон. Синяя сбрасывается на 0
  (финалка нового прогона).
- **Реген финалки (кнопка)** → добавляет новый синий свайп `kind: 'final'`
  в текущий зелёный.
- **Клинер (автоматический)** → добавляет синий свайп `kind: 'cleaned'`
  после последнего `'final'`.
- **Полный реген (кнопка)** → добавляет новый зелёный свайп.

### Границы

- Если синих свайпов 1 (только финал, без клинера) — синяя иконка скрыта.
- Если зелёных свайпов 1 — зелёная иконка скрыта (как сейчас).

## 5. Pipeline изменения

### POST-cleaner (generation_pipeline.dart)

Сейчас: `appendSwipeToMessage` добавляет в `swipes[]`.

Стало: добавляет в `agentSwipes[]` нового `AgentSwipe(kind: 'cleaned')`.
Не трогает `swipes[]`.

### Реген финалки (studioFinalOnly)

Сейчас: добавляет в `swipes[]`.

Стало: добавляет в `agentSwipes[]` нового `AgentSwipe(kind: 'final')`.
`swipeId` переключается на новый синий.

### Полный реген

Без изменений — добавляет в `swipes[]` (зелёный).
При этом `agentSwipes` сбрасывается: `[AgentSwipe(kind: 'final', content: новый ответ)]`.

## 6. Изменяемые файлы

| Файл | Что |
|---|---|
| `lib/core/models/chat_message.dart` | +`AgentSwipe` класс, +`agentSwipes`, +`agentSwipeId` поля |
| `lib/core/models/chat_message.freezed.dart` | регенерация |
| `lib/core/models/chat_message.g.dart` | регенерация |
| `lib/core/db/repositories/chat_repo.dart` | `appendSwipeToMessage` → `appendAgentSwipe` |
| `lib/features/chat/chat_message_service.dart` | `changeSwipe` — разделить на `changeMainSwipe` / `changeAgentSwipe` |
| `lib/features/chat/controllers/chat_swipe_controller.dart` | два метода свайпа |
| `lib/features/chat/chat_provider.dart` | expose `changeAgentSwipe`, `regenerateFinalOnly` |
| `lib/features/chat/services/generation_pipeline.dart` | POST-cleaner → agentSwipes; реген финалки → agentSwipes |
| `lib/features/chat/bridge/chat_message_mapper.dart` | маппинг agentSwipes в webview |
| `lib/features/chat/services/chat_import_export.dart` | экспорт/импорт agentSwipes |
| `lib/core/services/migration_service.dart` | миграция старых сообщений |
| `lib/features/chat/services/saved_message_writer.dart` | сохранение с agentSwipes |
| `lib/features/chat/widgets/chat_message_sync.dart` | дифф-логика |
| `assets/chat_webview/` (JS) | рендер двух иконок свайпов + анимация |
| Тесты | swipe controller, migration, pipeline |

## 7. Миграция

При первом запуске с новым кодом:

1. Для каждого assistant-сообщения с `swipes.length > 0`:
   - Создать `agentSwipes = swipes.map((s) => AgentSwipe(content: s, kind: 'final')).toList()`.
   - `agentSwipeId = swipeId`.
   - `swipes` оставить как есть (совместимость).
2. Если `swipes.length == 0` и `content` непустой — один agentSwipe.
3. Запись в `messages_json` — через обычную сериализацию (freezed/json).

**Не требуется** миграция БД (schema version) — `messages_json` хранится
как JSON-текст, новые поля просто появятся при следующей записи.

## 8. Риски

| Риск | Митигация |
|---|---|
| Sync (cloud) ломается при новых полях | Поля optional с дефолтами — старые клиенты игнорируют |
| JS webview не рендерит вторую иконку | Добавить фолбэк: если agentSwipes пуст, поведение как сейчас |
| Импорт из SillyTavern теряет agentSwipes | Это нормально — ST не знает про агентные свайпы |
| Двойной свайп = двойная сложность UX | Синяя скрыта, если 1 свайп; зелёная скрыта, если 1 прогон |
| Реген финалки + клинер гонка | Клинер ждёт завершения финалки (уже так через genId guard) |

## 9. Этапы

1. **Модель данных** — `AgentSwipe` класс + поля в `ChatMessage` + миграция.
2. **Pipeline** — POST-cleaner → `agentSwipes`; реген финалки → `agentSwipes`.
3. **Swipe controller** — `changeAgentSwipe` + `changeMainSwipe`.
4. **UI (Dart)** — expose двух свайп-методов в provider.
5. **UI (JS webview)** — две иконки, анимация, границы.
6. **Тесты** — controller, migration, pipeline, sync.

Каждый этап — отдельный коммит на `feat/agentic-dev`.
