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
- **Run `dart run build_runner build`** after changing freezed/isar models

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
| Database, Isar, write transactions | `docs/rules/database.md` |
| Formal invariants with code references | `docs/INVARIANTS.md` |
| Architecture, directory structure, full flow | `docs/ARCHITECTURE.md` |
| Flutter/Riverpod specifics | `CLAUDE.md` |

## Cleanup Checklist After Merge

- [ ] Delete local branch: `git branch -D feat/xxx`
- [ ] Delete remote branch: `git push origin --delete feat/xxx`
- [ ] Sync main: `git pull origin main`
