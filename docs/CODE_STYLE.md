# Code Style

Rules for code organization and decomposition.

## No God Objects — Parallel Decomposition

Every class/file must have a **single responsibility**. When a class grows beyond ~200-250 lines or takes on more than one logical role, consider splitting.

### Rules

1. **One class = one job.** If the class name needs "and" to describe it (`CharacterImportAndNormalization`), it's two classes.
2. **Thin orchestrator, fat specialists.** The top-level class (e.g. `PromptBuilder`) only calls other classes in order — it contains zero business logic itself. All logic lives in focused components below.
3. **Split when it hurts.** When adding a new feature to an existing file, check: does it belong there, or does it need its own file? If the file is already >250 lines **and** the new logic is clearly separable, extract. Don't split just to hit an arbitrary line count.
4. **No circular dependencies.** Lower layers never import from higher layers. Direction: `UI → Providers → Services/Repos → Models/DB`. Data flows down, events flow up.
5. **Extract during implementation, not after.** If while writing a method you realize "this chunk could be its own class," extract it immediately. Don't leave a TODO to refactor later.
6. **Constructor injection only.** Dependencies are passed in, not looked up. This keeps classes testable and boundaries visible.

### Architecture Layers (Dependency Direction ↓)

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

Key patterns to follow when editing:

- **Generation:** always use a `genId` (or `CancelToken`) to guard against stale completions writing to state after abort/regen. Check that the active generation ID still matches before applying any async result to state.
- **Race conditions:** verify state identity before async operations complete, especially after user actions that invalidate pending work.
- **Database:** go through Drift repos; never write raw SQL outside of repo classes.
- **Riverpod:** prefer `ref.watch` in build, `ref.read` in callbacks; never call `ref.read` at provider build time for side effects.
