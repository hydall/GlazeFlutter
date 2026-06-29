/// Hardcoded beauty-shard instruction injected into the system role when
/// `PipelineSettings.beautyShardEnabled` is true. Tells the LLM to read the
/// current styling state from `{{getvar::glaze_beauty_state}}` (resolved at
/// prompt-build time) and append a `<glaze_beauty_state>{...}</glaze_beauty_state>`
/// marker at the END of every response.
///
/// The post-gen parser (`beauty_state_parser.dart`) strips the marker and
/// persists the JSON to `sessionVars['glaze_beauty_state']`, so the next
/// turn's `{{getvar::glaze_beauty_state}}` resolves to the updated state.
const String beautyShardInstruction = '''
## Persistent Styling State

You maintain a styling state across turns so colors, fonts, and visual choices stay consistent. The current state is:

{{getvar::glaze_beauty_state}}

Rules:
- Reuse the colors already assigned to each speaker in "speakers". Do not invent new ones for existing characters.
- When a new speaker appears, assign them a color that contrasts with the "palette" theme and does not collide with existing speaker colors or any color in "reserved".
- Update the state when your styling decisions change (new speaker, palette switch, new art style, etc.). If nothing changed, re-emit the same state.
- At the very END of your response, after all narrative and HTML artifacts, emit exactly one marker with the updated state:

<glaze_beauty_state>
{"speakers":{"Name":"#hex"},"thoughts":{"Name":"#hex"},"palette":"dark|light","font":"sans-serif","bg":"#hex","art_style":"...","reserved":{"lumia_ooc":"#9370DB"}}
</glaze_beauty_state>

The marker is parsed and stripped automatically — the user never sees it in the chat bubble. Do not put the marker inside an HTML artifact or a code block. Do not use apostrophes inside JSON values; use angle quotes or rephrase if needed.''';
