# GlazeFlutter

Native LLM frontend for AI roleplay. Flutter rewrite of [Glaze](https://github.com/hydall/Glaze).
**Stack:** Flutter 3.41 + Riverpod 2 + Isar 3 + GoRouter. **Language:** Dart only. **License:** AGPL-3.0.

Architecture: `docs/ARCHITECTURE.md`. Migration plan: `docs/FLUTTER_MIGRATION_MVP.md`.

## Commands

```bash
flutter run -d windows          # Dev run (Windows)
flutter run -d chrome           # Dev run (Web)
flutter build windows           # Production build
flutter analyze                 # Lint + typecheck
dart run build_runner build     # Generate freezed/isar code
flutter test                    # Run tests
```

## Code Conventions

### Flutter Widgets
- **ConsumerWidget / ConsumerStatefulWidget** for anything that reads Riverpod
- **StatelessWidget / StatefulWidget** for pure UI with no state
- Keep widgets small — extract sub-widgets when > 200 lines
- Use `const` constructors everywhere possible

### State Management
- **Riverpod** only — no Provider, no BLoC, no GetX
- **AsyncNotifierProvider** for data from DB
- **StateProvider / NotifierProvider** for UI state
- **ref.watch** for rebuild, **ref.listen** for side effects, **ref.read** for callbacks
- Use `ref.watch(provider.select(...))` for granular rebuilds during streaming

### Navigation
- **GoRouter** for route definitions
- Named routes: `/`, `/chat/:charId`, `/settings/api`

### File Naming
| Type | Convention | Example |
|------|-----------|---------|
| Screens | snake_case + `_screen.dart` | `character_list_screen.dart` |
| Widgets | snake_case | `chat_bubble.dart` |
| Models | snake_case | `character.dart`, `chat_message.dart` |
| Providers | snake_case + `_provider.dart` | `character_provider.dart` |
| Repositories | snake_case + `_repo.dart` | `character_repo.dart` |
| Services | snake_case + `_service.dart` | `prompt_builder_service.dart` |

### Theme
- Material 3 with `colorSchemeSeed`
- Dark theme only for MVP
- Colors in `lib/shared/theme/app_colors.dart`
- Theme in `lib/shared/theme/app_theme.dart`

## Storage

| Data | Backend | Pattern |
|------|---------|---------|
| Characters | Isar `CharacterCollection` | Repository |
| Chat sessions | Isar `ChatSessionCollection` | Repository |
| Presets | Isar `PresetCollection` | Repository |
| API config | Isar `ApiConfigCollection` | Repository |
| Personas | Isar `PersonaCollection` | Repository |
| Images | File system (`path_provider`) | Image storage service |

## Architecture Layers

```
UI (screens/widgets)
  → Riverpod providers (state + business logic)
    → Repositories (DB abstraction)
      → Isar (persistence)
    → Services (LLM, prompt builder, macro engine)
      → Dio (HTTP/SSE)
```

## Context-Sensitive Rules

When editing files matching a pattern below, READ the corresponding rule file FIRST:

| When editing... | Read this |
|----------------|-----------|
| Generation, transport, streaming, abort | `docs/rules/generation.md` |
| Any async boundary, DB writes | `docs/rules/race-conditions.md` |
| Isar reads/writes, repositories | `docs/rules/database.md` |
| Architecture details, full flow | `docs/ARCHITECTURE.md` |
| Formal invariants with code references | `docs/INVARIANTS.md` |

## Do NOT

- Add Provider/BLoC/GetX — Riverpod only
- Use WebSocket for LLM streaming (SSE only)
- Break SillyTavern V2 format compatibility for character cards
- Store API keys in plain text in Isar
- Mutate state directly — use immutable patterns with freezed
- Forget `ref.watch` select for streaming UI (causes full rebuild per chunk)
