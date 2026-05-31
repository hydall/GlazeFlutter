# Dependency Upgrade Backlog

Зафиксировано: май 2026. Актуально для Flutter 3.44.0 / Dart 3.12.0.

## Контекст: path_provider_foundation override

В `pubspec.yaml` стоит override `path_provider_foundation: 2.4.2`.

**Причина:** версии 2.5.0+ тянут `objective_c`, чей `hook/build.dart` использует macOS-only API.
На Windows сборка падает с ошибкой компиляции нативного хука.

**Источник проблемы:** баг в `dart-lang/native` (issue #2480) — `hooks_runner` запускает
нативные хуки для всех платформ, даже если пакет нужен только на iOS/macOS.

**Статус:** открыт без milestone-даты. Один основной контрибьютор (`dcharkes`).
Следить: https://github.com/dart-lang/native/issues/2480

**`path_provider` (публичный пакет, 2.1.5) — это последняя версия, он не ограничивает
другие пакеты.** Override касается только внутреннего iOS/macOS плагина.

---

## Minor-обновления (безопасно, без breaking changes)

Можно сделать в любой момент через `flutter pub upgrade`:

| Пакет | Текущая | Доступная | Что даёт |
|---|---|---|---|
| `flutter_svg` | 2.2.4 | 2.3.0 | `imageBuilder` у `SvgPicture` — нам не нужен |
| `gpt_markdown` | 1.1.6 | 1.1.7 | патч |
| `image` | 4.8.0 | 4.9.1 | патч-фиксы |
| `drift` | 2.28.2 | 2.33.0 | `rightOuterJoin`, `isNotNull()` в manager API, перфоманс больших join-ов, DevTools экспорт БД |

**Реальный выигрыш минимален.** Делать только если появится конкретная нужда.

---

## Major-обновления (требуют миграции кода)

### `flutter_riverpod` 2.6.1 → 3.x

**Что меняется:** добавлен `@riverpod` code generation — провайдеры можно писать
как обычные функции с аннотацией вместо классов `AsyncNotifierProvider` и т.д.

```dart
// Сейчас (riverpod 2):
final charactersProvider = AsyncNotifierProvider<CharactersNotifier, List<Character>>(
  CharactersNotifier.new,
);

// В riverpod 3 (с code gen):
@riverpod
Future<List<Character>> characters(Ref ref) async { ... }
// генерирует charactersProvider автоматически
```

**Объём миграции:** все провайдеры в `lib/features/` и `lib/shared/providers/`.
**Приоритет:** низкий — текущий код работает, API riverpod 2 не удалён в v3.

---

### `freezed` 2.5.8 → 3.x + `freezed_annotation` 2.4.4 → 3.x

**Что меняется:** синтаксис классов (`abstract class` → `class`), новый стиль
primary constructors. Нужна перегенерация всех `.freezed.dart` файлов.

**Объём миграции:** все модели с `@freezed` + `dart run build_runner build`.
**Приоритет:** низкий — breaking только в синтаксисе аннотаций, логика не меняется.

---

### `drift` 2.28.2 → 3.x (когда выйдет)

Пока 2.33.0 — последняя стабильная, major-bump ещё не вышел.
При выходе drift 3 — потребует миграции схемы и репозиториев.

---

### `go_router` 14.8.1 → 17.x

**Что меняется:** улучшенная вложенная навигация, новые хелперы.
**Объём миграции:** роутер в `lib/app/router.dart` и все `context.go()` / `context.push()`.
**Приоритет:** низкий — текущий роутер работает стабильно.

---

### `build_runner` 2.5.4 → 2.15.0

`build_resolvers` и `build_runner_core` помечены как discontinued.
В 2.15.0 они заменены новыми пакетами автоматически.
**Можно обновить вместе с freezed 3** — они связаны.

---

## Порядок миграции (когда придёт время)

1. `build_runner` → 2.15.0 (prerequisite для freezed 3)
2. `freezed` + `freezed_annotation` → 3.x + перегенерация
3. `riverpod` → 3.x (самый большой объём)
4. `go_router` → 17.x
5. Снять override `path_provider_foundation` (когда закроют dart-lang/native#2480)
