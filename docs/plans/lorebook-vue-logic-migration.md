# Lorebook logic migration: Vue → Flutter (1-to-1)

> Status: **done — implemented.** The proposed fields (`minActivations`,
> `maxDepth`, `maxRecursionSteps`, `insertionStrategy`) now exist in
> `lib/core/models/lorebook.dart`. The UX/UI port of `LorebookSheet.vue`
> (list / entries / edit-entry screens) is also done. This document is
> retained for history; see `docs/ARCHITECTURE.md` § 3 for the current
> lorebook system.

## Context / problem

The Flutter `LorebookGlobalSettings` model is a thinner subset of the Vue
`lorebookState.globalSettings`. During the UI port we deliberately wired only the
fields the Dart engine already consumes. These Vue globals have **no Dart
equivalent and are not consumed by the engine**, so exposing them in the UI would be
dead knobs:

- `minActivations`, `maxDepth`, `maxRecursionSteps`
- `insertionStrategy` (`character_first` / `global_first`)
- `includeNames`
- `embeddingTarget` (Dart only has it **per-book**, `lb.settings.embeddingTarget`)
- tri-state / `glaze` **global** `matchWholeWords` (Dart global is a `bool` paired with
  `keySearchMode` = `tavern`/`glaze`); Vue uses one tri-state field `false|true|glaze`.
  Vue also offers `glaze` at the **entry** level; Dart entry is `bool?`.

Goal: bring these to parity with Vue, mirrored in both the live scanner
(`lorebook_scanner.dart`) and the coverage/preview engine (`lorebook_coverage.dart`),
which must stay in sync or the activation badges will lie.

## 1. Model changes — `lib/core/models/lorebook.dart` (then `dart run build_runner build`)

### `LorebookGlobalSettings`
Add (with defaults matching Vue / SillyTavern):

| field | type | default |
|-------|------|---------|
| `minActivations` | `int` | `0` |
| `maxDepth` | `int` | `0` (0 = no cap) |
| `maxRecursionSteps` | `int` | `0` (0 = engine default of 5) |
| `insertionStrategy` | `String` | `'character_first'` |
| `includeNames` | `bool` | `true` |
| `embeddingTarget` | `String` | `'content'` |

Change `matchWholeWords` from `bool` → `String` (`'false' | 'true' | 'glaze'`). Use a
`JsonConverter<String, Object?>` that coerces legacy values: `true→'true'`,
`false→'false'`, existing strings pass through, `null→'false'`. Keep `keySearchMode` for
back-compat (see §4).

### `LorebookEntry`
Change `matchWholeWords` from `bool?` → `String?` (`null | 'true' | 'false' | 'glaze'`)
with the same converter (coerce legacy `bool?`). This makes the entry editor's
match-whole-words selector a true 1-to-1 of Vue (it currently offers only
`global/on/off`).

> All other new global fields have safe defaults, so `json_serializable` round-trips old
> records without migration. Only the two `matchWholeWords` type changes need the
> converter.

## 2. Matching logic — `lib/core/llm/glaze_matcher.dart`

`resolveWholeWords(bool? entryValue, bool globalValue, String keySearchMode)` →
`resolveWholeWords(String? entryValue, String globalValue)`:

- `entryValue == 'glaze'` → `WholeWordMode.glaze`
- `entryValue == 'true'` → `yes`; `'false'` → `no`
- entry null → fall back to global: `'glaze'`→glaze, `'true'`→yes, else `no`

The `glaze` branch in `glazeCheckMatch` already exists and is unchanged.

**Callers to update**:
- `lorebook_scanner.dart:175-181` (`resolveWholeWords(entry.matchWholeWords, …)`).
- `lorebook_coverage.dart:118,136-137` (mirror).

`keySearchMode` no longer feeds `resolveWholeWords`; its `glaze` value is migrated into
the global `matchWholeWords` on load (§4) and the field is retained read-only for
back-compat / sync payloads.

## 3. Scanner + coverage — `lib/core/llm/lorebook_scanner.dart` (mirror in `lorebook_coverage.dart`)

1. **`maxRecursionSteps`** — replace the hardcoded recursion cap at
   `lorebook_scanner.dart:151-155`
   (`maxIterations = recursiveScan ? 5 : 1`) with
   `recursiveScan ? (globalSettings.maxRecursionSteps > 0 ? maxRecursionSteps : 5) : 1`.

2. **`includeNames`** — when building the scanned text the speaker name should be
   prepended to each message. Hook the `messagesToScan` join
   (`lorebook_scanner.dart:198-205`) and the temporal `histSource`
   (`:221-223`): when `globalSettings.includeNames`, format each line as
   `"<name>: <content>"` (user → persona name, assistant → char name). Mirror in
   coverage. Names plumbed from `char` / persona already available to the builder.

3. **`minActivations` + `maxDepth`** — ST-accurate progressive deepening. Wrap the
   keyword scan: run with the base effective scan depth; if the number of **non-constant**
   activated entries `< minActivations`, increase the effective scan depth by one step and
   re-scan, repeating until `minActivations` is met or the depth reaches `maxDepth`
   (`maxDepth == 0` ⇒ no deepening). Implement as an outer loop around the existing
   `while (changed …)` block, raising `effectiveScanDepth` per entry. Mirror in coverage so
   badges reflect the deepened set.

4. **`insertionStrategy`** — the final sort (`lorebook_scanner.dart:286`,
   `allRelevantEntries.sort((a,b) => a.order…)`) gets a tie-break: when `order` is equal,
   order character-scoped vs global entries by strategy
   (`character_first` ⇒ character lorebooks first; `global_first` ⇒ global first). A
   lorebook is "character" when `enabled == false` and it is bound via
   `activations.character` / `activationScope=='character'` / `char.world`. Thread the
   scope onto `ScannedEntry` (add a `scope` field) or compute from `lorebookId`. Mirror in
   `prompt_builder._classifyLorebooks` ordering if needed.

## 4. Persistence / migration — `lib/core/state/lorebook_provider.dart`

`loadLorebookSettings` (`:73`): after decoding, if the stored record has
`keySearchMode == 'glaze'` **and** `matchWholeWords` is falsy, set
`matchWholeWords = 'glaze'`. The `JsonConverter` handles the `bool→String` coercion for
both settings and entries, so old prefs / DB rows load without error.
`saveLorebookSettings` is unchanged (writes via `toJson`).

## 5. Vector embedding target default — `lib/core/llm/lorebook_vector_search.dart:259`

`final target = lb?.settings?.embeddingTarget ?? globalSettings.embeddingTarget ?? 'content';`
Apply the same global fallback at the indexing call-sites
(`lorebook_editor_screen.dart` `_indexEntries/_retryFailed/_clearAndReindex/_indexSingleEntry`
and any other `indexLorebookEntries(..., embeddingTarget:)`), passing
`_settings?.embeddingTarget ?? globalSettings.embeddingTarget ?? 'content'`.

## 6. UI follow-up (after the model exists)

Once §1 lands, expand the already-ported screens to the full Vue field set:

- **Inline Global Settings** (`lorebook_list_screen.dart` `_GlobalSettingsSection`): add
  `minActivations`, `maxDepth`, `maxRecursionSteps`, `insertionStrategy`, `includeNames`,
  `embeddingTarget` rows; switch `matchWholeWords` to a tri-state selector
  (`off/ST/glaze`); add reserve-mode `percent`/`tokens` context-percent handling already
  present.
- **Entry editor** (`lorebook_editor_screen.dart`): change the match-whole-words selector
  to include `glaze` (`null/ST/glaze/off`) now that the entry field is `String?`.

## Do NOT remove (existing Dart-only behaviour to preserve)

- `keySearchMode` (kept for back-compat + sync), `vectorTopK`, per-book
  `maxInjectedEntries` limits (`applyLorebookPerBookLimits`), the hybrid keyword/vector
  merge (`lorebook_merger.dart`) and the coverage/badge system, per-book `LorebookSettings`
  overrides.

## Verification (for the future engine work)

- `dart run build_runner build` clean; `flutter analyze` clean.
- Unit-test the scanner: `minActivations` deepens until met / capped by `maxDepth`;
  `maxRecursionSteps` bounds recursion; `glaze` global resolves for entries with
  `matchWholeWords == null`; `includeNames` makes a name-only key match; `insertionStrategy`
  flips equal-order character vs global ordering.
- Confirm `lorebook_coverage.dart` activation badges match the scanner for the same input.
- Migration: load a pre-change prefs blob with `matchWholeWords:true` /
  `keySearchMode:'glaze'` and assert it resolves to `'glaze'`.
