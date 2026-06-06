# glaze_flutter

Glaze is a native LLM frontend for AI roleplay. This repository is the
Flutter rewrite of [Glaze](https://github.com/hydall/Glaze).

**Stack:** Flutter 3.41 + Riverpod 2 + Drift (SQLite) + GoRouter. **Language:** Dart only. **License:** AGPL-3.0.

> Architecture, invariants, generation rules, and DB rules: `docs/ARCHITECTURE.md`, `docs/INVARIANTS.md`, `docs/rules/`.
>
> Project workflow (git / PRs / Trello): `docs/WORKFLOW.md`.
>
> JS extension SDK final state: `docs/ARCHITECTURE.md` § 9 and `docs/refactor_plan.md`.

## Getting Started

Prerequisites: Flutter 3.44+ (Dart 3.12+). The Flutter SDK is at
`Z:\Glaze project\flutter` on the project lead's machine; the agent's
shell may not have `flutter` on PATH — fall back to the full path
(`& "Z:\Glaze project\flutter\bin\flutter.bat" <subcommand>`) when
the bare command fails with "not recognized".

### Common commands

```powershell
# Preferred — try PATH first
flutter analyze
flutter test
flutter build windows

# Fallback if `flutter` is not on PATH
& "Z:\Glaze project\flutter\bin\flutter.bat" analyze
& "Z:\Glaze project\flutter\bin\flutter.bat" test
& "Z:\Glaze project\flutter\bin\flutter.bat" build windows

# After editing freezed / drift / json_serializable models
dart run build_runner build --delete-conflicting-outputs
```

See `docs/BUILD_NOTES.md` for the `path_provider_foundation` override
required for Windows builds.

## Project layout

```
lib/
  app.dart                          # GlazeApp — router + boot-time init
  main.dart                         # entry point
  core/                             # models, services, providers, llm pipeline, navigation
  features/
    chat/                           # chat UI + WebView bridge + generation pipeline
    extensions/                     # post-gen blocks + JS bridge SDK (glaze.*)
    settings/                       # API / app / theme settings
    lorebooks/                      # lorebook UI
    presets/                        # prompt preset editor
    character_list/                 # character CRUD + editor
    image_gen/                      # image generation UI + services
    cloud_sync/                     # Dropbox / GDrive sync
    ...
  shared/                           # shell, theme, widgets
docs/                               # architecture + invariants + rules + plans
assets/chat_webview/                # WebView HTML/JS/CSS (chat + headless engine + glaze SDK)
test/                               # 17 extension test files + characterization + webview asset guards
```

## Features

* **AI roleplay chat** — multi-character, multi-session, lorebooks,
  memory books, image generation, prompt presets, SillyTavern
  character card V2 import.
* **Extensions / post-generation blocks** — `infoblock` (LLM agent),
  `imageGen` (image generation pipeline), `jsRunner` (sandboxed JS),
  `interactive` (HTML panel islands under the assistant message).
  Blocks trigger `afterAssistant` (default), `afterUser`, or
  `periodic` (timer).
* **JS extension SDK** — `window.glaze.*` API exposed to sandboxed
  iframes and the headless JS engine. Variables (`chat` / `character` /
  `global` / `message` scopes), `generateText`, `triggerGeneration`,
  `injectPrompt`, `playAudio`, `executeCommand`, `showToast`. Every
  call is gated by a per-preset capability permission (default-deny).
* **Cloud sync** — Dropbox + Google Drive, OAuth PKCE.
* **Themes** — Material 3, custom presets, Google Fonts.

## License

AGPL-3.0. See `LICENSE` (project root).
