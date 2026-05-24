# Custom Markdown Markers

The app extends GptMarkdown with custom `==...==` inline markers. When adding a new marker, update **both** the converter (`lib/core/utils/html_to_markdown.dart`) and the renderer (`message.dart`) in sync.

## Registered markers

| Marker | Example | Renders as |
|---|---|---|
| `==hc:#hex==text==` | `==hc:#ff33ff==pink==` | Colored text (HtmlColorMd) |
| `==glow:#hex,blur==text==` | `==glow:#ffffff,4==echo==` | Text with glow shadow (GlowTextMd) |
| `==cg:#textHex,#glowHex,blur==text==` | `==cg:#ffb6c1,#ff6eb4,4==rosa==` | Colored text + glow shadow (ColorGlowTextMd) |
| `==grad:#hex1,#hex2==text==` | `==grad:#ff33ff,#ff1493==text==` | Gradient text via ShaderMask (GradientTextMd) |
| `==bg:#hex==text==` | `==bg:#333333==highlighted==` | Text with background color (BackgroundTextMd) |
| `==mark==text==` | `==mark=="dialogue"==` | Quote-highlighted text (MarkMd) |
| `==active==text==` | `==active==search hit==` | Active search match (ActiveMarkMd) |

## Guard: `_styledSegmentRegex`

`_highlightPhrases()` in `message.dart` splits text on styled segments before wrapping quotes in `==mark==`. This prevents `==mark==` from being injected inside other markers (e.g. a `"..."` inside `==grad:...==`). When adding a new marker, add it to `_styledSegmentRegex` so quotes inside it are left alone.

Also protect markdown formatting patterns (`**bold**`, `*italic*`, `__bold__`, `_italic_`, `~~strike~~`) from quote highlighting — they are already included in `_styledSegmentRegex`. Single quotes (`'...'`) are **not** protected so that nested quotes like `"...'...'..."` work — the outer quote regex captures the entire span and the inner single quotes inherit the color from the outer `==mark==` region.
