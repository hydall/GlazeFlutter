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

- **No direct commits to `master`** — always use feature branches
- **Stack while catching up** — branch off the latest unmerged branch if needed
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

## Before Starting Work

1. `git branch --show-current` — make sure you're on the right branch
2. Sync with latest: `git checkout master && git pull upstream master`
3. `git checkout -b feat/xxx` — create feature branch
4. `flutter analyze` — verify before committing

## No God Objects — Parallel Decomposition

Every class/file must have a **single responsibility**. When a class grows beyond ~150 lines or takes on more than one logical role, split it before continuing.

### Rules

1. **One class = one job.** If the class name needs "and" to describe it (`CharacterImportAndNormalization`), it's two classes.
2. **Thin orchestrator, fat specialists.** The top-level class (e.g. `PromptBuilder`) only calls other classes in order — it contains zero business logic itself. All logic lives in focused components below.
3. **Split before extend.** When adding a new feature to an existing file, check: does it belong there, or does it need its own file? If the file is already >150 lines, the answer is almost always "new file."
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

## Code Rules (lazy-loaded)

Detailed rules are split into topic files. When in doubt, read all that apply before editing:

| Topic | File |
|-------|------|
| Generation lifecycle, abort, genId, streaming | `docs/rules/generation.md` |
| Race conditions, async boundaries, ownership | `docs/rules/race-conditions.md` |
| Database, Drift, write transactions | `docs/rules/database.md` |
| Formal invariants with code references | `docs/INVARIANTS.md` |
| Architecture, directory structure, full flow | `docs/ARCHITECTURE.md` |
| Flutter/Riverpod specifics | `CLAUDE.md` |
| **All screens, buttons, navigation, port status** | **`docs/UI_REFERENCE.md`** |

**Before building or modifying any UI screen**, read the relevant section in `docs/UI_REFERENCE.md`. It maps every Glaze JS view to its Flutter route, lists every button/action, and tracks port status.

## Cleanup Checklist After Merge

- [ ] Delete local branch: `git branch -D feat/xxx`
- [ ] Delete remote branch: `git push origin --delete feat/xxx`
- [ ] Sync master: `git checkout master && git pull upstream master`