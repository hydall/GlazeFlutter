# GlazeFlutter

Native LLM frontend for AI roleplay. Flutter rewrite of [Glaze](https://github.com/hydall/Glaze).
**Stack:** Flutter 3.41 + Riverpod 2 + Drift (SQLite) + GoRouter. **Language:** Dart only. **License:** AGPL-3.0.

Architecture: `docs/ARCHITECTURE.md`. Workflow (git, PRs, Trello): `docs/WORKFLOW.md`.

## Commands

```bash
flutter run -d windows          # Dev run (Windows)
flutter run -d chrome           # Dev run (Web)
flutter build windows           # Production build
flutter analyze                 # Lint + typecheck
dart run build_runner build     # Regenerate after editing freezed/drift models
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
- **Sub-screens need an explicit back button** — `leading: BackButton(onPressed: () => context.go('/parent'))` — GoRouter `go()` replaces the stack and won't add one automatically

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
| Characters | Drift `Characters` table | Repository |
| Chat sessions | Drift `ChatSessions` table | Repository |
| Presets | Drift `Presets` table | Repository |
| API config | Drift `ApiConfigs` table | Repository |
| Personas | Drift `Personas` table | Repository |
| Images | File system (`dart:io` Platform) | Image storage service |

## Architecture Layers

```
UI (screens/widgets)
  → Riverpod providers (state + business logic)
    → Repositories (DB abstraction)
      → Drift / SQLite (persistence)
    → Services (LLM, prompt builder, macro engine)
      → Dio (HTTP/SSE)
```

## Context-Sensitive Rules

When editing files matching a pattern below, READ the corresponding rule file FIRST:

| When editing... | Read this |
|----------------|-----------|
| Generation, transport, streaming, abort | `docs/rules/generation.md` |
| Any async boundary, DB writes | `docs/rules/race-conditions.md` |
| Drift reads/writes, repositories | `docs/rules/database.md` |
| Architecture details, full flow | `docs/ARCHITECTURE.md` |
| Formal invariants with code references | `docs/INVARIANTS.md` |
| Custom `==...==` markdown markers, message rendering | `docs/markdown-markers.md` |
| Windows/build failures, dependency overrides | `docs/BUILD_NOTES.md` |

## Workflow

- Branch (`feat/xxx`) off `master`, push to `origin`, open a PR — see `docs/WORKFLOW.md` for branching, Trello, and cleanup checklists.
- Run `dart run build_runner build` after changing any freezed/drift model.
- Single responsibility: split a class before it grows past ~150 lines (thin orchestrators, fat specialists, constructor injection). Details: `docs/ARCHITECTURE.md`.

## Do NOT

- Add Provider/BLoC/GetX — Riverpod only
- Use WebSocket for LLM streaming (SSE only)
- Break SillyTavern V2 format compatibility for character cards
- Store API keys in plain text in Drift
- Mutate state directly — use immutable patterns with freezed
- Forget `ref.watch` select for streaming UI (causes full rebuild per chunk)
- Commit directly to `master` — always use a feature branch
- Use the `gh` CLI — GitHub operations go through GitHub MCP tools
