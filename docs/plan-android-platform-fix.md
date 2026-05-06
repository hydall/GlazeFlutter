# План: Поддержка Android/iOS — исправление "Platform not supported yet"

## Что случилось

Собрали APK, запустили на Android — на **каждом экране** ошибка:
`Error: Unsupported operation: Platform not supported yet`

## Почему

В проекте есть **два места**, где функция `_getAppDataDir()` определяет путь к данным через `dart:io` `Platform` — и содержит ветки только для Windows, Linux, macOS. **Android и iOS не обработаны**, поэтому бросается `UnsupportedError`.

### Место 1: `lib/core/db/app_db.dart:70-82`

```dart
String _getAppDataDir() {
  if (Platform.isWindows) { ... }
  else if (Platform.isLinux) { ... }
  else if (Platform.isMacOS) { ... }
  throw UnsupportedError('Platform not supported yet');  // ← Android падает сюда
}
```

Эта функция вызывается при создании `AppDatabase` → `LazyDatabase`. `AppDatabase` — корневой провайдер (`appDbProvider`), от которого зависят ВСЕ репозитории и сервисы. **Краш БД = краш всего приложения на всех экранах.**

### Место 2: `lib/core/services/image_storage_service.dart:86-99`

Та же функция с теми же ветками. `ImageStorageService.create()` вызывает её синхронно. Но это вторичная проблема — приложение уже мёртвое от места 1.

## Корневая проблема

`_getAppDataDir()` — **синхронная** (`String`), а `path_provider` (который уже есть в `pubspec.yaml`: `path_provider: 2.1.5`) даёт пути через **асинхронные** вызовы (`Future<Directory>`). Для Android/iOS без `path_provider` не обойтись.

## Решение: общая утилита + async

Создать одну функцию `getAppDataDir()` в `lib/core/utils/platform_paths.dart`, убрать дублирование, сделать её async для совместимости с `path_provider`.

---

## Шаги реализации

### Шаг 1: Создать `lib/core/utils/platform_paths.dart`

Новая утилита — единое место для путей к данным.

```dart
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

Future<String> getAppDataDir() async {
  if (Platform.isAndroid || Platform.isIOS) {
    final dir = await getApplicationDocumentsDirectory();
    return p.join(dir.path, 'Glaze');
  }
  return _desktopDataDir();
}

String _desktopDataDir() {
  if (Platform.isWindows) {
    final appData = Platform.environment['APPDATA']!;
    return p.join(appData, 'Glaze');
  } else if (Platform.isLinux) {
    final xdg = Platform.environment['XDG_DATA_HOME'] ??
        p.join(Platform.environment['HOME']!, '.local', 'share');
    return p.join(xdg, 'Glaze');
  } else if (Platform.isMacOS) {
    return p.join(Platform.environment['HOME']!, 'Library',
        'Application Support', 'Glaze');
  }
  throw UnsupportedError('Platform not supported yet');
}
```

**Почему async:** `getApplicationDocumentsDirectory()` возвращает `Future`. Десктопные пути доступны синхронно через env-переменные, но сигнатура должна быть единая. `LazyDatabase` и так принимает async-колбэк, так что это не проблема для БД.

---

### Шаг 2: Обновить `lib/core/db/app_db.dart`

Заменить локальный `_getAppDataDir()` на импорт из `platform_paths.dart`.

**Было:**
```dart
String _getAppDataDir() { ... }  // локальная синхронная функция

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = _getAppDataDir();  // синхронный вызов
    ...
  });
}
```

**Стало:**
```dart
import '../utils/platform_paths.dart';

// Удалить локальный _getAppDataDir()

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getAppDataDir();  // async вызов
    final dir = Directory(dbFolder);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final file = File(p.join(dbFolder, 'glaze.db'));
    return NativeDatabase.createInBackground(file);
  });
}
```

**Обратить внимание:** убрать `import 'dart:io'` если он больше не нужен напрямую (но он нужен для `File`, `Directory` — значит оставить).

---

### Шаг 3: Обновить `lib/core/services/image_storage_service.dart`

Заменить локальный `_getAppDataDir()`, сделать `create()` async.

**Было:**
```dart
static ImageStorageService create() {
  final baseDir = _getAppDataDir();
  return ImageStorageService(baseDir);
}
```

**Стало:**
```dart
import '../utils/platform_paths.dart';

static Future<ImageStorageService> create() async {
  final baseDir = await getAppDataDir();
  return ImageStorageService(baseDir);
}
```

Удалить локальный `_getAppDataDir()`.

---

### Шаг 4: Обновить `lib/core/state/db_provider.dart` — async-каскад

`ImageStorageService.create()` теперь `Future`, значит провайдер должен быть `FutureProvider`.

**Было:**
```dart
final imageStorageProvider = Provider<ImageStorageService>((ref) {
  return ImageStorageService.create();
});

final characterImporterProvider = Provider<CharacterImporter>((ref) {
  return CharacterImporter(ref.watch(imageStorageProvider));
});

final migrationServiceProvider = Provider<MigrationService>((ref) {
  return MigrationService(
    ...
    imageStorage: ref.watch(imageStorageProvider),
  );
});
```

**Стало:**
```dart
final imageStorageProvider = FutureProvider<ImageStorageService>((ref) async {
  return await ImageStorageService.create();
});

final characterImporterProvider = FutureProvider<CharacterImporter>((ref) async {
  final imageStorage = await ref.watch(imageStorageProvider.future);
  return CharacterImporter(imageStorage);
});

final migrationServiceProvider = FutureProvider<MigrationService>((ref) async {
  final imageStorage = await ref.watch(imageStorageProvider.future);
  return MigrationService(
    charRepo: ref.watch(characterRepoProvider),
    chatRepo: ref.watch(chatRepoProvider),
    personaRepo: ref.watch(personaRepoProvider),
    presetRepo: ref.watch(presetRepoProvider),
    apiRepo: ref.watch(apiConfigRepoProvider),
    imageStorage: imageStorage,
  );
});
```

---

### Шаг 5: Обновить потребителей `imageStorageProvider`

Это места, где используется `ref.read(imageStorageProvider)`. Теперь провайдер возвращает `AsyncValue<ImageStorageService>`, нужен `.future` или `.value`.

**Файл: `lib/features/character_list/character_editor_screen.dart:275`**
```dart
// Было:
final storage = ref.read(imageStorageProvider);

// Стало:
final storage = await ref.read(imageStorageProvider.future);
```
(Метод `_pickAvatar` уже async, так что `await` ок.)

**Файл: `lib/features/character_list/character_list_screen.dart:130`**
```dart
// Было:
final importer = ref.read(characterImporterProvider);

// Стало:
final importer = await ref.read(characterImporterProvider.future);
```
(Метод уже async.)

**Файл: `lib/features/personas/persona_list_screen.dart:168`**
```dart
// Было:
final imageStorage = ref.read(imageStorageProvider);

// Стало:
final imageStorage = await ref.read(imageStorageProvider.future);
```
(Метод уже async.)

---

### Шаг 6: Проверить `migrationServiceProvider` потребителей

Сейчас `migrationServiceProvider` не используется в UI напрямую (grep показал только объявление в `db_provider.dart`). Если будет использоваться — тоже через `.future`.

---

### Шаг 7: `flutter analyze && flutter build windows`

По правилам из AGENTS.md — прогнать перед коммитом.

---

## Итоговая карта изменений

| Файл | Изменение |
|------|-----------|
| `lib/core/utils/platform_paths.dart` | **Новый** — общая async-функция `getAppDataDir()` |
| `lib/core/db/app_db.dart` | Удалить `_getAppDataDir()`, использовать `getAppDataDir()` с `await` |
| `lib/core/services/image_storage_service.dart` | Удалить `_getAppDataDir()`, `create()` → `Future`, использовать `getAppDataDir()` |
| `lib/core/state/db_provider.dart` | `imageStorageProvider`, `characterImporterProvider`, `migrationServiceProvider` → `FutureProvider` |
| `lib/features/character_list/character_editor_screen.dart` | `ref.read(imageStorageProvider)` → `await ref.read(imageStorageProvider.future)` |
| `lib/features/character_list/character_list_screen.dart` | `ref.read(characterImporterProvider)` → `await ref.read(characterImporterProvider.future)` |
| `lib/features/personas/persona_list_screen.dart` | `ref.read(imageStorageProvider)` → `await ref.read(imageStorageProvider.future)` |

## Риски и заметки

1. **`path_provider_foundation: 2.4.2`** — pin из AGENTS.md (workaround для Windows build). Он не мешает Android, это только macOS/iOS нативная часть. На Android используется `path_provider` → `path_provider_android`, который работает нормально.

2. **Десктопный путь не сломается** — `_desktopDataDir()` дублирует текущую логику один-в-один, просто вынесена в отдельную функцию.

3. **`getApplicationDocumentsDirectory()` на Android** возвращает контекстный `filesDir` (`/data/data/<pkg>/files/`) — стандартное место для данных приложения. Подпапка `Glaze` сохранится.

4. **Можно рассмотреть `getApplicationSupportDirectory()`** вместо `getApplicationDocumentsDirectory()` — на Android это тот же путь, на iOS — `Library/Application Support/` (более правильно для данных, не видимых пользователю). Но для совместимости с текущей структурой и простоты `getApplicationDocumentsDirectory()` достаточно.
