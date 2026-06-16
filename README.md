<p align="center">
  <img src="assets/logos/glaze.svg" width="256" alt="Glaze Logo">
</p>

# Glaze Flutter

[![Discord](https://img.shields.io/discord/1355184294868484196?color=5865F2&logo=discord&logoColor=white)](https://discord.gg/jnGhd7p6Ht)
[![Buy Me A Coffee](https://img.shields.io/badge/Buy%20Me%20A%20Coffee-FFDD00?style=flat&logo=buy-me-a-coffee&logoColor=black)](https://buymeacoffee.com/hydall)

Glaze Flutter is a native rewrite of [Glaze](https://github.com/hydall/Glaze): a local, novice-friendly AI roleplay chat client that works with any OpenAI-compatible Chat Completions provider.

This repository contains the Flutter version of the app. The goal is to keep the approachability and SillyTavern compatibility of the original JS/Vue client while moving the core experience to a native cross-platform stack with local SQLite storage, stronger desktop support, and a cleaner extension runtime.

> [!WARNING]
> Glaze Flutter is still under heavy development. The app is not yet stable and may contain bugs.
>
> This is the in-progress Flutter rewrite, not the original Vue/Capacitor app.

## Key Features

- **Native AI roleplay chat** - Chat with characters using OpenAI-compatible LLM APIs, manage multiple chats and sessions, and keep data locally on your device.
- **Character cards** - Import and export SillyTavern V2 character cards, including JSON and PNG card formats.
- **Prompt presets** - Create and edit generation presets, configure model parameters, and reuse prompt structures across chats.
- **Lorebooks and memory** - Attach lorebooks, memory books, author's notes, personas, and contextual data to improve long-running roleplay sessions.
- **Reasoning-aware rendering** - Reasoning/thinking output can be parsed into separate blocks so it is readable in the UI without being blindly fed back into the model.
- **Image generation** - Generate images from the app and connect image output to roleplay flows and extension blocks.
- **Cloud sync** - Dropbox and Google Drive sync support for moving local data between devices.
- **Theming** - Material 3 UI with custom theme presets, color controls, Google Fonts, and desktop/mobile layouts.
- **Local-first storage** - Drift/SQLite persistence for characters, sessions, presets, API configuration, personas, lorebooks, and extension data.

## SillyTavern Compatibility

- **Character Card V2** - Import/export support for SillyTavern V2 JSON and PNG cards.
- **Presets** - JSON preset compatibility is a core target, with built-in editors for prompt and generation settings.
- **Lorebooks / World Info** - Lorebook support is built into the chat context pipeline.
- **Macros** - Macro expansion is handled by the prompt builder and macro engine, including character/user substitutions and contextual variables.
- **Regex and formatting rules** - The renderer and prompt pipeline include support for custom formatting behavior used by roleplay presets.

## Extensions

Glaze Flutter includes a sandboxed extension system for post-generation automation and interactive UI blocks.

- **Post-generation blocks** - Run `infoblock`, `imageGen`, `jsRunner`, and `interactive` blocks after assistant messages, after user messages, or on periodic timers.
- **Interactive panels** - Render extension-owned HTML panels under assistant messages without giving scripts same-origin access to the app.
- **JS extension SDK** - Sandboxed scripts can use `window.glaze.*` APIs for variables, text generation, prompt injection, audio, command execution, toasts, and more.
- **Capability permissions** - Every bridge method is gated by explicit per-preset capabilities. The default is deny.
- **Scoped variables** - Extensions can use `chat`, `character`, `global`, and `message` variable scopes through dedicated storage APIs.

See `docs/ARCHITECTURE.md` section 9 and `docs/INVARIANTS.md` for the bridge architecture and security invariants.

## Installation

Download the latest build from the [Releases](../../releases) page when available.

- **Windows** - Download the Windows build or installer and run it directly.
- **Android** - Install the APK directly on your device.
- **iOS/macOS/Linux** - Not published as Flutter builds yet; platform support depends on Flutter build availability, packaging, and signing setup.

## Development

Glaze Flutter is built with Flutter, Riverpod, Drift, SQLite, Dio, GoRouter, and a WebView-based chat/extension renderer.

### Prerequisites

- [Flutter](https://docs.flutter.dev/get-started/install) 3.44+ or newer compatible with Dart 3.12+
- A desktop/mobile toolchain for the platform you want to build
- Git

### Setup

```bash
git clone https://github.com/hydall/GlazeFlutter.git
cd GlazeFlutter
flutter pub get
```

### Common Commands

```bash
flutter analyze
flutter test
flutter build windows
```

After editing generated Drift, Freezed, or JSON-serializable models, regenerate code:

```bash
dart run build_runner build
```

See `docs/BUILD_NOTES.md` for Windows build notes and dependency override context.

## Project Layout

```text
lib/
  app.dart                          # GlazeApp: router and boot-time initialization
  main.dart                         # Entry point
  core/                             # Models, services, providers, LLM pipeline, navigation
  features/
    chat/                           # Chat UI, WebView bridge, generation flow
    extensions/                     # Post-generation blocks and JS bridge SDK
    settings/                       # API, app, and theme settings
    lorebooks/                      # Lorebook UI and management
    presets/                        # Prompt preset editor
    character_list/                 # Character CRUD and editor
    image_gen/                      # Image generation UI and services
    cloud_sync/                     # Dropbox / Google Drive sync
  shared/                           # Shell, theme, shared widgets
assets/chat_webview/                # WebView HTML/JS/CSS renderer and bridge assets
assets/translations/                # Localization files
docs/                               # Architecture, invariants, rules, workflow, build notes
test/                               # Unit, characterization, extension, and asset-guard tests
```

## Architecture Notes

- **State management** - Riverpod providers and notifiers.
- **Persistence** - Drift over SQLite, accessed through repositories.
- **Generation** - HTTP/SSE-based LLM transport through Dio; WebSocket transport is not used for LLM streaming.
- **Navigation** - GoRouter route definitions for desktop and mobile layouts.
- **Rendering** - Chat messages are rendered through WebView assets with a Flutter bridge for state, actions, and extension panels.
- **Security model** - Extension scripts run in sandboxed contexts and must pass capability checks before calling bridge APIs.

Primary technical references:

- `docs/ARCHITECTURE.md`
- `docs/INVARIANTS.md`
- `docs/rules/`
- `docs/WORKFLOW.md`

## License

This project is licensed under the [GNU Affero General Public License v3.0](LICENSE).
