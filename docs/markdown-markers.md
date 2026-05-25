# Custom Markdown Markers

The app extends GptMarkdown with custom `==...==` inline markers. When adding a new marker, update **all** of the following in sync:

1. **Converter:** `lib/core/utils/html_to_markdown.dart` — produces marker syntax from HTML
2. **JS renderer:** `assets/chat_webview/formatter.js` — `styledRegex` (extraction guard) + `_renderStyledSegment()` (HTML output)
3. **JS CSS:** `assets/chat_webview/renderer.js` — `SHADOW_STYLE` constant (styling for marker classes)
4. **Dart renderer:** `lib/shared/widgets/colored_markdown.dart` — `InlineMd` subclass for Flutter-native rendering

## Registered `==...==` markers

| Marker | Example | Renders as | Dart class | CSS class |
|---|---|---|---|---|
| `==hc:#hex==text==` | `==hc:#ff33ff==pink==` | Colored text | `HtmlColorMd` | `.glaze-hc` |
| `==glow:#hex,blur==text==` | `==glow:#ffffff,4==echo==` | Text with glow shadow | `GlowTextMd` | `.glaze-glow` |
| `==cg:#textHex,#glowHex,blur==text==` | `==cg:#ffb6c1,#ff6eb4,4==rosa==` | Colored text + glow | `ColorGlowTextMd` | `.glaze-cg` |
| `==grad:#hex1,#hex2==text==` | `==grad:#ff33ff,#ff1493==text==` | Gradient text (ShaderMask) | `GradientTextMd` | `.glaze-grad` |
| `==bg:#hex==text==` | `==bg:#333333==highlighted==` | Text with background color | `BackgroundTextMd` | `.glaze-bg` |
| `==mark==text==` | `==mark=="dialogue"==` | Quote-highlighted text | `MarkMd` | `.glaze-mark` |
| `==active==text==` | `==active==search hit==` | Active search match | `ActiveMarkMd` | `.glaze-active` |

Note: `==mark==` and `==active==` are injected by the JS-side quote-highlighting and search-highlighting logic. `html_to_markdown.dart` does NOT produce these markers — it only produces the 5 styling markers above.

## Additional custom InlineMd/BlockMd classes

These do not use `==...==` syntax but are registered alongside the markers in `colored_markdown.dart`:

| Class | Pattern | Renders as |
|---|---|---|
| `ColoredItalicMd` | `*italic*` | Italic with optional color override from theme preset |
| `ColoredUnderscoreItalicMd` | `_italic_` | Underscore-italic with optional color override |
| `ColoredBoldMd` | `**bold**` | Bold with optional color override |
| `ColoredUnderscoreBoldMd` | `__bold__` | Underscore-bold with optional color override |
| `DetailsSummaryMd` | `<details><summary>` | Collapsible details/summary block |

## Guard: `styledRegex` in formatter.js

`_processText()` in `formatter.js` uses `styledRegex` to extract all custom `==...==` markers
plus standard markdown formatting patterns (`**bold**`, `*italic*`, `__bold__`, `_italic_`, `~~strike~~`)
before wrapping quotes in `==mark==`. This prevents `==mark==` from being injected inside other markers
(e.g. a `"..."` inside `==grad:...==`). When adding a new marker, add its pattern to `styledRegex`
so quotes inside it are left alone.

Single quotes (`'...'`) are **not** protected so that nested quotes like `"...'...'..."` work —
the outer quote regex captures the entire span and the inner single quotes inherit the color from
the outer `==mark==` region.
