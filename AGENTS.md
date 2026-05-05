# AGENTS.md — Workflow Rules

## Repository Structure

- **`origin`** = `danvitv/GlazeFlutter` — Flutter development
- **`upstream`** = `hydall/GlazeFlutter` (when created) — PRs merged here
- Until upstream exists, all work happens on `origin/main` with feature branches

## Branching Strategy

### Feature Branches

Each feature = isolated branch from `main`.

```bash
git checkout -b feat/my-feature
git push -u origin feat/my-feature
# PR to main
gh pr create --base main ...
```

### Hotfixes

Urgent fixes branch from `main`, merge back to `main`.

## Rules

- **No direct commits to `main`** — always use feature branches
- **Delete merged branches** — both local and remote
- **Run `flutter analyze && flutter build windows`** before committing
- **Run `dart run build_runner build`** after changing freezed/drift models

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

**Impact of override:** `path_provider_foundation 2.4.2` works fine on macOS/iOS (MethodChannel-based). No functional difference for end users. The only risk is falling behind on updates to that package.

## Before Starting Work

1. `git branch --show-current` — make sure you're on the right branch
2. `git pull origin main` — sync
3. `git checkout -b feat/xxx` — create feature branch
4. `flutter analyze` — verify before committing

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

## Cleanup Checklist After Merge

- [ ] Delete local branch: `git branch -D feat/xxx`
- [ ] Delete remote branch: `git push origin --delete feat/xxx`
- [ ] Sync main: `git pull origin main`
