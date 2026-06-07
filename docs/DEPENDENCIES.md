# Dependency Upgrade Plan

Актуально для ветки `feat/freezed-3x-migration` после восстановления Robocopy-corruption и `dart pub cache repair`.
Flutter SDK: `Z:\GlazeProject\flutter`. Dart/Flutter версии см. в локальном SDK и `pubspec.lock`.

## Текущий baseline

Перед дальнейшими dependency upgrades baseline должен оставаться зелёным:

```powershell
& "Z:\GlazeProject\flutter\bin\flutter.bat" pub get
& "Z:\GlazeProject\flutter\bin\dart.bat" run build_runner build
& "Z:\GlazeProject\flutter\bin\flutter.bat" analyze
& "Z:\GlazeProject\flutter\bin\flutter.bat" test
```

Последняя проверка после `dart pub cache repair`:

| Проверка | Статус | Примечание |
|---|---:|---|
| `flutter pub get` | pass | override `path_provider_foundation` сохранён |
| `dart run build_runner build` | pass | build_runner не зависает, генерация проходит |
| `flutter analyze` | pass with warnings | errors нет, остаются существующие warnings/info |
| `flutter test` | pass | 712 tests passed |

Если снова появляются странные ошибки пакетов или codegen, сначала восстановить Pub cache:

```powershell
& "Z:\GlazeProject\flutter\bin\dart.bat" pub cache repair
& "Z:\GlazeProject\flutter\bin\flutter.bat" pub get
```

Жёсткий вариант только при повторной corruption cache:

```powershell
Remove-Item -LiteralPath "Z:\Pub\Cache\hosted" -Recurse -Force
& "Z:\GlazeProject\flutter\bin\flutter.bat" pub get
```

## Текущие ключевые версии

Полный список всегда проверять по `pubspec.lock`. Ниже только пакеты, важные для миграции.

| Пакет | Текущая версия | Статус |
|---|---:|---|
| `build_runner` | 2.15.0 | done |
| `freezed` | 3.2.5 | done |
| `freezed_annotation` | 3.1.0 | done |
| `drift` / `drift_dev` | 2.33.0 | latest stable на момент проверки |
| `flutter_riverpod` / `riverpod` | 2.6.1 | next major migration candidate |
| `go_router` | 17.3.0 | done |
| `gpt_markdown` | 1.1.7 | patched, `imageBuilder` API changed |
| `path_provider` | 2.1.5 | overridden |
| `path_provider_foundation` | 2.4.2 | overridden, do not unpin yet |

## Active Override

В `pubspec.yaml` intentionally pinned exact versions:

```yaml
dependency_overrides:
  path_provider: 2.1.5
  path_provider_foundation: 2.4.2
```

Причина: `path_provider_foundation >=2.5.0` тянет `objective_c`, чей native hook ломает Windows builds из-за `dart-lang/native#2480`.
Caret (`^2.4.2`) нельзя: pub резолвит более новую версию и снова подтягивает `objective_c`.

Override снимается только после отдельной проверки:

```powershell
# временно удалить dependency_overrides из pubspec.yaml
& "Z:\GlazeProject\flutter\bin\flutter.bat" pub get
& "Z:\GlazeProject\flutter\bin\flutter.bat" build windows
```

Если Windows build падает на native hooks или `objective_c`, override вернуть и снова выполнить `flutter pub get`.

## Working Migration Order

Не делать один большой `flutter pub upgrade --major-versions`. Обновлять маленькими партиями и после каждой партии прогонять baseline checks.

### 0. Stabilization Gate

Статус: done в текущей ветке.

Цель этапа:

| Задача | Статус |
|---|---:|
| Восстановить Pub cache | done |
| Подтвердить `build_runner build` | done |
| Починить текущие analyze errors | done |
| Починить WebView/navigation smoke failures | done |
| Подтвердить полный `flutter test` | done |

Новые dependency upgrades начинаются только от этого состояния.

### 1. Safe Minor/Patch Batch

Цель: обновить низкорисковые пакеты без архитектурных миграций.

Кандидаты из `flutter pub outdated` после cache repair:

| Пакет | Current | Resolvable/Latest | Риск |
|---|---:|---:|---|
| `image` | 4.8.0 | 4.9.1 | low |
| `test_api` | 0.7.11 | 0.7.12 | low, обычно транзитивно |
| `meta` | 1.18.0 | 1.18.3 | low, транзитивно |
| `matcher` | 0.12.19 | 0.12.20 | low, транзитивно |

Команда-кандидат:

```powershell
& "Z:\GlazeProject\flutter\bin\flutter.bat" pub upgrade image
```

Не форсировать транзитивные test/analyzer пакеты вручную без причины.

### 2. `go_router` 14.8.1 -> 17.x

Status: done. Upgraded to `17.3.0`; `flutter analyze`, `test/navigation_smoke_test.dart`, and full `flutter test` pass.

Приоритет: medium. Делать до Riverpod, потому что router scope меньше и navigation tests уже покрывают критичный путь.

Перед правками читать:

| Файл | Причина |
|---|---|
| `docs/ARCHITECTURE.md` | navigation architecture and sub-screen back button invariant |
| `lib/core/navigation/router.dart` | single source of GoRouter setup |
| `test/navigation_smoke_test.dart` | regression coverage |

Проверить changelog `go_router` для 15.x, 16.x, 17.x. Особое внимание:

| Зона | Что проверить |
|---|---|
| `StatefulShellRoute` | API and branch behavior |
| `GoRouter.onException` | signature and redirect behavior |
| `GoRouterState.uri` | API compatibility |
| `context.go` / `context.push` | behavior with shell and standalone routes |
| `routerProvider` tests | fresh `GlobalKey<NavigatorState>` per test |

Verification for this batch:

```powershell
& "Z:\GlazeProject\flutter\bin\flutter.bat" analyze
& "Z:\GlazeProject\flutter\bin\flutter.bat" test test/navigation_smoke_test.dart
& "Z:\GlazeProject\flutter\bin\flutter.bat" test
```

### 3. `flutter_riverpod` 2.6.1 -> 3.x

Приоритет: medium/high только после зелёного `go_router` batch.

Важно: не смешивать upgrade to Riverpod 3 с переходом на `@riverpod` code generation. Сначала сохранить ручные providers, если API позволяет.

Основные зоны риска:

| Зона | Примеры |
|---|---|
| `AsyncNotifierProvider` | DB-backed lists, chat state |
| `StateNotifierProvider` | theme/settings/catalog/extensions state |
| `StateProvider.family` | streaming state and UI state |
| `ProviderContainer` tests | overrides and disposal behavior |
| `ref.listen` side effects | chat/webview/build listeners |

Поиск перед миграцией:

```powershell
rg "AsyncNotifierProvider|StateNotifierProvider|StateProvider|FutureProvider|ProviderContainer|ref\.listen|\.notifier" lib test
```

Verification for this batch:

```powershell
& "Z:\GlazeProject\flutter\bin\flutter.bat" analyze
& "Z:\GlazeProject\flutter\bin\flutter.bat" test test/navigation_smoke_test.dart
& "Z:\GlazeProject\flutter\bin\flutter.bat" test test/trigger_generation_test.dart
& "Z:\GlazeProject\flutter\bin\flutter.bat" test
```

### 4. Platform/Runtime Major Packages

Делать только после router/Riverpod или в отдельных ветках, если нужны срочно.

| Пакет | Current | Latest | Notes |
|---|---:|---:|---|
| `app_links` | 6.4.1 | 7.1.1 | проверить OAuth/deep-link flow |
| `flutter_dotenv` | 5.2.1 | 6.0.1 | проверить `.env` asset loading |
| `flutter_foreground_task` | 8.17.0 | 9.2.2 | Android foreground-service risk |
| `flutter_local_notifications` | 18.0.1 | 22.0.0 | platform setup risk |
| `share_plus` | 10.1.4 | 13.1.0 | export/share flow risk |
| `sqlite3_flutter_libs` | 0.5.42 | 0.6.0+eol | native package risk, verify DB tests |

Do not batch all of these together. One package or one tightly related group per commit.

### 5. Deferred/Blocked

| Item | Status | Rule |
|---|---|---|
| `path_provider_foundation` override removal | blocked | wait for `dart-lang/native#2480` or verified Windows build |
| `drift` 3.x | unavailable | revisit when stable release exists |
| Riverpod code generation migration | deferred | separate refactor after Riverpod 3 works manually |

## Commit Strategy

Use small commits with one purpose each:

| Commit | Contents |
|---|---|
| stabilization | analyze/test fixes, WebView guard restoration |
| safe dependency batch | low-risk package updates only |
| go_router migration | router code and tests |
| riverpod migration | provider compatibility updates |
| platform package migration | one platform package group |
| docs | update this file and build notes as needed |

Never commit generated `.freezed.dart` / `.g.dart` files if they are gitignored. Still run `build_runner build` after changing freezed/drift/json models.

## PR Checklist

Before opening or updating the PR:

```powershell
git status --short --branch
& "Z:\GlazeProject\flutter\bin\flutter.bat" pub get
& "Z:\GlazeProject\flutter\bin\dart.bat" run build_runner build
& "Z:\GlazeProject\flutter\bin\flutter.bat" analyze
& "Z:\GlazeProject\flutter\bin\flutter.bat" test
& "Z:\GlazeProject\flutter\bin\flutter.bat" pub outdated
```

Windows build is currently environment-blocked unless NuGet CLI is installed and available on `PATH`:

```powershell
& "Z:\GlazeProject\flutter\bin\flutter.bat" build windows
```

If it fails with `Nuget is not installed`, document it as an environment blocker, not a dependency migration failure.
