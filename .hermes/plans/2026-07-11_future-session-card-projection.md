# Future Plan: Rebuildable Session-Card Projection

> **Status:** Deferred design only. Do **not** implement this plan as part of Atomic Character State + Direct/Assisted Studio. It requires a separate explicit decision and implementation pass.

## Purpose

Offer an optional human-facing **session-card projection**: a readable view of how a specific RP branch has developed from an immutable base card and manual lorebook, without ever treating the projection as canonical runtime memory or automatically rewriting author-owned source material.

This future feature exists for review/export/navigation. Studio/Ledger runtime must continue to use:

```text
immutable base card + manual lorebook
+ committed scene ledger
+ append-only scoped atomic character/session facts
+ MemoryBook/raw-message retrieval
+ mandatory current-state packets for focal/present NPCs
```

## Non-goals

- No periodic LLM rewrite of the source card.
- No automatic editing of manual lorebook entries.
- No replacement of raw messages, MemoryBooks, tracker snapshots, or atomic facts.
- No automatic acceptance of generated card text.
- No requirement that Direct or Assisted Studio depends on the projection.
- No physical line-number patches against card prose.

## Why it must be separate

Project Tokyo is a multi-layer world/campaign bible, not a single mutable persona: its card fields and 51-entry lorebook intentionally overlap while carrying different prompt roles, hidden canon, future hooks, and conditional arcs. A session result must not overwrite possibilities in author canon.

A prose replacement such as:

```text
Lucy is cold → Lucy loves Danvi
```

is semantically wrong. The durable change is relationship-scoped, while the baseline remains true elsewhere. Similar failures occur when an NPC learns a secret, a conditional arc resolves on one branch, or an off-screen faction development becomes session-specific.

Marinara-style `oldText → newText` proposals, version history, and review reduce accidental file loss but do not establish the semantic scope of a change or synchronize intentionally duplicated card/lorebook layers.

## Target design

```text
immutable source revision(s)
        +
append-only typed, scoped events/facts
        +
manual locks and review decisions
        ↓
rebuildable materialized session-card projection
        ↓
read-only review / export / optional copy-on-write derivative
```

### 1. Source revisions

Record immutable evidence for:

- base character card revision/hash and exact prompt-relevant payload;
- each manual lorebook revision referenced by the session, including activation reason;
- source-card/lorebook revisions chosen by the user after later edits.

Do not duplicate huge lorebook bodies into every chat by default. Store revision IDs and content hashes, and require an explicit recovery state if a pinned historical revision is unavailable locally.

### 2. Stable semantic targets

Projection patches must refer to stable semantic targets, never physical offsets:

```text
card:personality
card:scenario
card:first_message
lorebook:<id>:entry:<id>
projection:relationship:<entity-a>:<entity-b>
projection:arc:<id>
```

For arbitrary imported prose, field-level targets are safer than pretending every sentence is independently patchable. Fine-grained semantic sections can only be introduced after an explicit importer/editor design.

### 3. Typed events, not freeform replacement

Every accepted projection input must carry:

- stable event ID;
- source fact IDs/message/swipe provenance;
- target semantic ID;
- scope (`relationship`, `epistemic`, `arc`, `scene`, `global` only when justified);
- authority (`manual`, character-belief, objective session consequence);
- operation (`add_bullet`, `replace_projection_bullet`, `mark_arc_resolved`, `retract`, `manual_override`);
- lifecycle and supersession link;
- author/time/review decision.

The projection renderer turns these into readable text. It must never infer that a relationship-scoped fact globally replaces baseline personality.

### 4. Rebuild and conflict model

Projection is disposable:

1. Load selected immutable source revisions.
2. Load active accepted typed events in branch order.
3. Apply deterministic scope/precedence rules.
4. Render sections with fact provenance links.
5. Produce a diff against the previous projection.

When source card/lorebook changes, show a three-way comparison:

```text
old source revision → new source revision
                     + active session events
```

Never silently rebase. Conflicts require a user decision: retain old source, adopt new source, or keep a manually locked projection item.

### 5. Branch and lifecycle semantics

- A branch receives only events whose source anchors exist before the branch point.
- Regenerated/deleted messages retract or hide dependent tentative events.
- Rejected swipes never become accepted projection inputs.
- Session deletion removes its projection/event data through normal deletion and sync tombstones.
- Base card/manual lorebook remain untouched under every lifecycle operation.

### 6. UI and user control

The UI should initially be read-only and clearly label:

- **Base canon** — source card/manual lorebook text;
- **Session development** — accepted facts/events with scope and provenance;
- **Projection** — rebuildable derived display, not source canon.

Require manual review for any operation that creates an editable/copy-on-write derivative. Provide:

- fact/event provenance inspection;
- dry-run diff;
- per-event accept/reject/retract;
- projection rebuild;
- export as a separate file;
- explicit locks;
- rollback to a prior projection build.

Never place an “Apply to base card” action next to normal per-turn generation.

## Suggested implementation sequence (when explicitly approved)

1. Audit actual card/lorebook import, revision, editor, activation, backup, and sync paths.
2. Specify source revision and active-lorebook manifest storage.
3. Define target IDs and typed projection event schema.
4. Build deterministic projection renderer with no LLM dependency.
5. Add event lifecycle/branch/retraction/rebase behavior.
6. Add read-only inspection UI and export.
7. Add review-only LLM suggestions as an optional last layer, never auto-apply.
8. Consider copy-on-write character/lorebook derivatives only after projection correctness is proven.

## Required tests

- Relationship-specific development does not rewrite a global personality field.
- Two NPCs can hold different beliefs about the same secret.
- A conditional future hook remains in the source card after one branch resolves it.
- Project Tokyo card/lorebook overlap remains untouched and does not create conflicting source rewrites.
- Rebuild from the same revisions/events is deterministic.
- Branch excludes post-branch events.
- Deleted/regenerated source messages retract dependent events.
- Source revision change produces a visible conflict/diff, never a silent rebase.
- Missing pinned lorebook revision enters explicit recovery state.
- Projection export/import retains provenance but never changes base card/manual lorebook.

## Exit criteria

This feature may be considered only when it demonstrates all of the following:

- no auto-mutation of base card/manual lorebook;
- projection is fully rebuildable from source revisions plus typed events;
- every visible session change has scope and provenance;
- rollback/rebase/branch behavior is deterministic;
- Project Tokyo can expose session development without flattening author canon, secrets, or future arc potential.
