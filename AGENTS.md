# AGENTS.md — Workflow Rules

## Repository Structure

- **`origin`** = `danvitv/GlazeFlutter` — development, feature branches pushed here
- **`upstream`** = `hydall/GlazeFlutter` — PRs merged here

## Branching Strategy

Each feature = branch from current working base, push to origin, PR to upstream/master.

While catching up to Glaze JS, features stack — new branches branch off the previous unmerged branch.

```bash
# First feature
git checkout -b feat/first
# ... work ...
git push -u origin feat/first
gh pr create --repo hydall/GlazeFlutter --base master --head danvitv:feat/first

# Next feature — stacks on previous unmerged branch
git checkout -b feat/second feat/first
# ... work ...
git push -u origin feat/second
gh pr create --repo hydall/GlazeFlutter --base master --head danvitv:feat/second
```

### Rules

- **No direct commits to `master`** — always use feature branches for anything that will be pushed or PR'd
- **Small/local changes** — you may edit directly in the current branch without creating a new one (typos, one-liners, experiments, quick debugging)
- **Stack while catching up** — branch off the latest unmerged branch if needed for larger features
- **Run `dart run build_runner build`** after changing freezed/drift models
- **Every sub-screen must have a back button** — use `leading: BackButton(onPressed: () => context.go('/parent'))` in AppBar since GoRouter `go()` replaces the stack and doesn't auto-provide one

## Known Issue: `path_provider_foundation` + `objective_c` on Windows

**Bug:** Flutter compiles native asset hooks for ALL platforms when building for one. `path_provider_foundation >=2.4.3` depends on `objective_c >=9.0.0`, whose `hook/build.dart` uses macOS-only API (`OS.iOS`, `OS.macOS`) that fails to compile on Windows.

**Bug report:** [dart-lang/native#2480](https://github.com/dart-lang/native/issues/2480) — "[hooks] Exclude a platform from being built by dependency's build hook". Open, milestone: Native Assets v1.x.

**Workaround (current):** `pubspec.yaml` pins `path_provider_foundation: 2.4.2` via `dependency_overrides`. This version uses MethodChannel instead of FFI and doesn't depend on `objective_c`.

**Action:** Periodically (every few weeks) check if the fix has landed:
1. Remove the `dependency_overrides` block from `pubspec.yaml`
2. `flutter pub get`
3. `flutter build windows`
4. If it passes — remove this section from AGENTS.md
5. If it fails — keep the override, check again later

## Before Starting Work (recommended for significant changes)

For **new features** or **larger refactors**, follow this ritual to stay in sync:

1. `git branch --show-current` — make sure you're on the right branch
2. Sync with latest: `git checkout master && git pull upstream master`
3. `git checkout -b feat/xxx` — create feature branch
4. `flutter analyze` — verify before committing

For **small fixes**, **typos**, **one-file tweaks** or **quick experiments** — you may work directly in the current branch. Just run `flutter analyze` before asking the user to commit.

## Running Interactive Commands

**`flutter run` and `flutter test --watch` are permanently unavailable to the agent.**

Reason: both commands are **long-running / blocking**. `flutter run` starts a persistent dev server and keeps the terminal occupied until the app is manually closed. The agent session would freeze indefinitely, unable to continue any work, issue further commands, or report results.

Only run one-shot, non-interactive commands:
- `flutter analyze` (with optional file path argument)
- `flutter test` (non-watch, one-shot)
- `dart run build_runner build` when required

If you need to verify runtime behavior or hot-reload changes, ask the user to run `flutter run -d <platform>` (or `flutter run -d chrome`) in a separate terminal and report back. The agent cannot drive or observe a live Flutter session.

**Hot restart after JS asset changes:**
When files in `assets/chat_webview/` are modified, the user must **hot restart** (press `R`). Hot reload (`r`) doesn't rebuild the asset bundle.

## No God Objects — Parallel Decomposition

Every class/file must have a **single responsibility**. When a class grows beyond ~200-250 lines or takes on more than one logical role, consider splitting.

### Rules

1. **One class = one job.** If the class name needs "and" to describe it (`CharacterImportAndNormalization`), it's two classes.
2. **Thin orchestrator, fat specialists.** The top-level class (e.g. `PromptBuilder`) only calls other classes in order — it contains zero business logic itself. All logic lives in focused components below.
3. **Split when it hurts.** When adding a new feature to an existing file, check: does it belong there, or does it need its own file? If the file is already >250 lines **and** the new logic is clearly separable, extract. Don't split just to hit an arbitrary line count.
4. **No circular dependencies.** Lower layers never import from higher layers. Direction: `UI → Providers → Services/Repos → Models/DB`. Data flows down, events flow up.
5. **Extract during implementation, not after.** If while writing a method you realize "this chunk could be its own class," extract it immediately. Don't leave a TODO to refactor later.
6. **Constructor injection only.** Dependencies are passed in, not looked up. This keeps classes testable and boundaries visible.

### Architecture layers (dependency direction ↓)

```
UI (screens/widgets)
  → Providers (Riverpod state + actions)
    → Services (orchestrators: PromptBuilder, CharacterImporter)
      → Components (specialists: MacroEngine, TokenEstimator, HistoryAssembler)
        → Models (Freezed data classes)
        → Repos (Drift abstraction)
```

A component may only import from layers at its level or below. Never upward.

## UI Files — Only Extract Logic

Large UI files are acceptable. A 800-line screen with private widgets (`_HeroSection`, `_TabsRow`, etc.) is fine — these widgets share context and are read as a whole.

**What to extract from UI files:**
- Business logic (LLM calls, repo access, file I/O, data transformation) → move to a service or provider
- State that belongs in a provider (computed stats, persisted preferences) → move to a Riverpod provider

**When splitting UI into separate files IS justified:**
- The widget is reused across multiple screens → move to `shared/widgets/`
- The section is a distinct sub-screen with its own state and navigation (e.g. a complex dialog or sheet)

**What NOT to extract:**
- Private helper widgets — they belong with their screen
- Layout helpers, color constants, text styles — these are UI concerns
- Callback handlers that only call `ref.read(someProvider.notifier).action()` — these are already thin

Rule of thumb: if removing the business logic leaves a file with only `build()` methods and `Widget` returns, it's done. Don't split further.

## Code Rules

There are no separate doc files in this repo. All rules live here in `AGENTS.md`.

Key patterns to follow when editing:
- **Generation:** always use a `genId` (or `CancelToken`) to guard against stale completions writing to state after abort/regen
- **Race conditions:** check that the active generation ID still matches before applying any async result to state
- **Database:** go through Drift repos; never write raw SQL outside of repo classes
- **Riverpod:** prefer `ref.watch` in build, `ref.read` in callbacks; never call `ref.read` at provider build time for side effects

## Custom Markdown Markers

The app extends GptMarkdown with custom `==...==` inline markers. When adding new ones, both the converter (`html_to_markdown.dart`) and the renderer (`message.dart`) must be updated in sync.

### Registered markers

| Marker | Example | Renders as |
|---|---|---|
| `==hc:#hex==text==` | `==hc:#ff33ff==pink==` | Colored text (HtmlColorMd) |
| `==glow:#hex,blur==text==` | `==glow:#ffffff,4==echo==` | Text with glow shadow (GlowTextMd) |
| `==cg:#textHex,#glowHex,blur==text==` | `==cg:#ffb6c1,#ff6eb4,4==rosa==` | Colored text + glow shadow (ColorGlowTextMd) |
| `==grad:#hex1,#hex2==text==` | `==grad:#ff33ff,#ff1493==text==` | Gradient text via ShaderMask (GradientTextMd) |
| `==bg:#hex==text==` | `==bg:#333333==highlighted==` | Text with background color (BackgroundTextMd) |
| `==mark==text==` | `==mark=="dialogue"==` | Quote-highlighted text (MarkMd) |
| `==active==text==` | `==active==search hit==` | Active search match (ActiveMarkMd) |

### Guard: `_styledSegmentRegex`

`_highlightPhrases()` in `message.dart` splits text on styled segments before wrapping quotes in `==mark==`. This prevents `==mark==` from being injected inside other markers (e.g. `"..."` inside `==grad:...==`). When adding a new marker, add it to `_styledSegmentRegex` so quotes inside it are left alone.

Also protect markdown formatting patterns (`**bold**`, `*italic*`, `__bold__`, `_italic_`, `~~strike~~`) from quote highlighting — they are already included in `_styledSegmentRegex`. Single quotes (`'...'`) are NOT protected so that nested quotes like `"...'...'..."` work — the outer quote regex captures the entire span and the inner single quotes inherit the color from the outer `==mark==` region.

## Trello Board

- **Board URL:** https://trello.com/b/jRUaax0b/glazeflutter
- **Board ID:** `6a08b1a3055cd731743d9c2b`
- **API credentials** are in `.trello` (gitignored, not shipped in builds) — read with `source .trello` or parse manually
- Use Trello REST API (`https://api.trello.com/1/...?key=...&token=...`) to read/update cards

### Lists

| Name | ID |
|---|---|
| features | `6a08b1a3055cd731743d9c1c` |
| Known Bugs | `6a08b1a3055cd731743d9c29` |
| In Progress | `6a0991fb6005f1f92f73cf44` |
| Done, not tested | `6a08b1a3055cd731743d9c2a` |
| Fixed | `6a08b6a98f657e17b6c33a23` |
| later | `6a08b1a3055cd731743d9c23` |
| ios | `6a08b1a3055cd731743d9c24` |
| chat modes | `6a08b1a3055cd731743d9c20` |
| CD-ROM | `6a08b1a3055cd731743d9c21` |

### Workflow

1. **Before starting any fix/feat** — search the Trello board for an existing card. If found, move it to **In Progress**. If not found, create a card in **In Progress** with a clear description.
2. **After implementation** — move the card to **Done, not tested**.
3. **After user tests immediately** — move the card to **Fixed**.
4. New features with no card yet → create in **features** first, then move to **In Progress** when starting work.

**Note:** Trello tracking is recommended for visibility but not strictly required for every small change.

## Cleanup Checklist After Merge

- [ ] Delete local branch: `git branch -D feat/xxx`
- [ ] Delete remote branch: `git push origin --delete feat/xxx`
- [ ] Sync master: `git checkout master && git pull upstream master`