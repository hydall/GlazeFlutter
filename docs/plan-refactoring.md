# План рефакторинга

## P0 — Архитектурные нарушения ✅

| # | Что | Почему | Статус |
|---|-----|--------|--------|
| 1 | Перенести `SyncDeletionTracker` из `features/` в `core/utils/` | `core/state/` импортирует `features/` — нарушение зависимостей | ✅ |
| 2 | Создать `generateId()` в `core/utils/id_generator.dart` | 16 дубликатов | ✅ |
| 3 | Создать `currentTimestampSeconds()` в `core/utils/time_helpers.dart` | 37 дубликатов | ✅ |

## P1 — God-объекты и бизнес-логика в UI

| # | Что | Строк | Результат |
|---|-----|-------|-----------|
| 4 | `ChatNotifier` → `ChatSessionNotifier` + `ChatMessageEditor` + делегирование генерации | 542 | Каждый <150 строк, одна ответственность |
| 5 | Вынести бизнес-логику из `MagicDrawerPanel` в services/providers (stats, summary) | 894 | Статы через Riverpod provider, а не императивно в виджете |
| 6 | `BackupService` → `BackupExporter` + `JsonlChatExporter/Importer` + `PngCharacterExporter` + `SillyTavernExporter` | 1399 | Каждый формат — свой класс |
| 8 | Вынести бизнес-логику из `chat_screen.dart` в `ChatActionsService` | 604 | `_generateSummary`, `_exportChat`, `_importChat` не должны быть в UI |
| 9 | Перенести провайдеры из экранов в отдельные файлы | — | `PersonaListNotifier`, `ApiListNotifier`, `ChatHistoryNotifier` |

## P2 — Устранение обхода provider-слоя

| # | Что | Масштаб |
|---|-----|---------|
| 10 | UI напрямую вызывает `repo.put()` — создать provider-facade | 13 экранов, ~40 вызовов |
| 11 | UI напрямую импортирует `core/llm/` сервисы — обернуть в providers | 13 виджетов |
| 12 | `GlazeTextField` — использовать везде вместо 66 дубликатов `InputDecoration` | 66 мест |
| 13 | `ImageGenSettings` → Freezed модель (убрать 75 строк ручной сериализации) | `image_gen_provider.dart` |
| 14 | `ActiveSelectionProvider` → нормальный AsyncNotifier (убрать дублирование WidgetRef/Ref) | `active_selection_provider.dart` |
