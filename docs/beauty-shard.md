# Beauty Shard — Persistent Styling State

The Studio pipeline supports a **persistent styling state** that the LLM reads
and updates on every turn. It remembers per-speaker colors, palette mode,
fonts, art styles, and any other styling decision that should survive across
messages — without requiring the user to manually thread `{{setvar::}}` rules
through their preset.

This is opt-in: it only activates when the user adds a **beauty block** to
their preset that reads `{{getvar::glaze_beauty_state}}` and instructs the LLM
to emit a state marker at the end of its response.

> Infoblocks, illustration panels, topbar, image generation, and the
> `extensions/` system are completely separate from the beauty shard. If you
> need those, configure them under the Extensions panel. The beauty shard
> only remembers styling state.

## How it works

1. **Build (this turn):** the beauty block in the preset resolves
   `{{getvar::glaze_beauty_state}}` to the JSON state stored on the previous
   turn. The LLM sees the current styling state in the system role and uses it
   to keep its output visually consistent.
2. **Generate:** the LLM writes its response (narrative, HTML, CSS artifacts,
   whatever the preset asks for) and appends a state marker at the very end:
   ```text
   <glaze_beauty_state>
   {"speakers":{"Alice":"#abc123"},"palette":"dark","font":"sans-serif"}
   </glaze_beauty_state>
   ```
3. **Post-gen parse:** the post-generation parser extracts the LAST
   `<glaze_beauty_state>...</glaze_beauty_state>` marker from the response,
   parses the JSON body (tolerant of trailing commas and `//` comments via
   `repairJson`), strips the marker from the text that reaches the chat
   bubble, and merges the parsed JSON into the pending session variables
   under the key `glaze_beauty_state`. Only well-formed JSON objects persist
   — when the payload fails to parse, the previous state is left untouched
   (state is sticky, never lost to a malformed turn).
4. **Next turn:** step 1 repeats with the updated state.

## State format

The state is a **JSON object** (not an array, not a scalar) wrapped in
`<glaze_beauty_state>...</glaze_beauty_state>` tags. Keys and values are
free-form — the contract is whatever the beauty block instructs the LLM to
emit. The parser only requires:

* The body parses as a JSON object (`{...}`).
* Tag names are case-insensitive (so `<GLAZE_BEAUTY_STATE>` works too, though
  lowercase is canonical).

A reasonable schema (you decide the exact keys — the LLM will mirror what the
beauty block tells it to write):

```json
{
  "speakers": {
    "Alice": "#abc123",
    "Bob": "#44cc88"
  },
  "thoughts": {
    "Alice": "#9988aa"
  },
  "palette": "dark",
  "font": "sans-serif",
  "bg": "#1a1a1a",
  "art_style": "street_art_anime",
  "reserved": {
    "lumia_ooc": "#9370DB"
  }
}
```

## Sample beauty block for your preset

Add a preset block with role `system`, insertion mode `relative`, depth `4`
(adjust depth to where you want styling instructions in the prompt). Use the
following content as a template — tailor it to your preset's needs:

```text
### Persistent Styling State

You maintain a styling state across turns so colors, fonts, and visual
choices stay consistent. The current state is:

{{getvar::glaze_beauty_state}}

Rules:
- Reuse the colors already assigned to each speaker in "speakers" — do not
  invent new ones for existing characters.
- When a new speaker appears, assign them a color that contrasts with the
  "palette" theme and does not collide with existing speaker colors or any
  color in "reserved".
- Update the state when your styling decisions change (new speaker, palette
  switch, new art style, etc.). If nothing changed, re-emit the same state.
- At the very end of your response, after all narrative and HTML artifacts,
  emit exactly one marker with the updated state:

<glaze_beauty_state>
{...your JSON state, same shape as the one above...}
</glaze_beauty_state>

The marker is parsed and stripped automatically — the user never sees it in
the chat bubble. Do not put the marker inside an HTML artifact or a code
block. Do not use apostrophes inside JSON values; use angle quotes « » or
rephrase if needed.
```

## What the user sees

The chat bubble never shows the `<glaze_beauty_state>` marker — it is stripped
before the message is saved. Only the styling decisions the LLM makes based on
the state (e.g. `<font color="#abc123">"Hi,"</font>` dialogue wrapping) reach
the rendered chat.

## Diagnostics

When the marker is found but the JSON payload fails to parse (malformed,
array root, etc.), the parser leaves the previous state intact and still
strips the marker from the response. There is no error surfaced to the user —
state is best-effort.

## Implementation references

| Concern | File | Lines |
|---|---|---|
| Parser (pure, testable) | `lib/core/llm/beauty_state_parser.dart` | — |
| Wired into success path | `lib/features/chat/services/stream_generation_service.dart` | onComplete (non-Studio) + Studio `studioResult.response` |
| Atomic var update (out-of-band) | `lib/core/db/repositories/chat_repo.dart` | `updateSessionVarsJson` |
| Macro resolution of `{{getvar::glaze_beauty_state}}` | `lib/core/llm/macro_engine.dart` | 340-346 |
| Studio chat-time expansion of the beauty block | `lib/core/llm/studio_message_builder.dart` | 410, 435 |
| Parser tests | `test/beauty_state_parser_test.dart` | — |

## Invariants honored

* **INV-C5 (success-only persistence):** the state only persists on the
  generation success path — both `writeAssistant` call sites that consume
  the parsed state are on the success path. Error and abort paths never
  receive `pendingSessionVars` with the updated state.
* **Atomic variable writes:** out-of-band updates use
  `ChatRepo.updateSessionVarsJson` (Drift `transaction()`). The generation
  success path carries the state via `pendingSessionVars` into the full
  session upsert (single write).
* **No read-modify-write of ChatSession:** the parser does not load or
  mutate the session — it merges into the already-computed
  `pendingSessionVars` map that the prompt build produced.
