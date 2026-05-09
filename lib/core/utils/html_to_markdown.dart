import 'dart:developer';

String htmlToMarkdown(String html) {
  var result = html;

  result = _stripBlock(result, 'style');
  result = _stripBlock(result, 'script');

  result = result.replaceAll(RegExp(r'<br\s*/?>\s*', caseSensitive: false), '\n');

  result = _convertColoredSpan(result);
  result = _convertColoredFont(result);

  final afterColor = result;

  result = result.replaceAllMapped(
    RegExp(r'<h([1-6])[^>]*>(.*?)</h\1>', caseSensitive: false, dotAll: true),
    (m) => '\n${'#' * int.parse(m[1]!)} ${_inline(m[2]!)}\n',
  );

  result = result.replaceAllMapped(
    RegExp(r'<p[^>]*>(.*?)</p>', caseSensitive: false, dotAll: true),
    (m) => '\n${_inline(m[1]!)}\n',
  );

  result = result.replaceAllMapped(
    RegExp(r'<blockquote[^>]*>(.*?)</blockquote>', caseSensitive: false, dotAll: true),
    (m) => _inline(m[1]!).split('\n').map((l) => '> $l').join('\n'),
  );

  result = _convertInline(result, 'strong', '**');
  result = _convertInline(result, 'b', '**');
  result = _convertInline(result, 'em', '*');
  result = _convertInline(result, 'i', '*');
  result = _convertInline(result, 'del', '~~');
  result = _convertInline(result, 's', '~~');
  result = _convertInline(result, 'u', '__');
  result = _convertInline(result, 'code', '`');

  result = result.replaceAllMapped(
    RegExp(r'''<a[^>]*href=["']([^"']*)["'][^>]*>(.*?)</a>''', caseSensitive: false, dotAll: true),
    (m) => '[${_inline(m[2]!)}](${m[1]!})',
  );

  result = result.replaceAllMapped(
    RegExp(r'''<img[^>]*src=["']([^"']*)["'][^>]*>''', caseSensitive: false),
    (m) => '![](${m[1]!})',
  );

  result = result.replaceAllMapped(
    RegExp(r'<hr\s*/?>', caseSensitive: false),
    (m) => '\n---\n',
  );

  result = result.replaceAll(
    RegExp(r'</?(?:div|span|section|article|header|footer|nav|main|figure|figcaption|details|summary|center|font|small|sub|sup|mark|table|tr|td|th|thead|tbody|ul|ol|li|dl|dt|dd|pre)[^>]*>', caseSensitive: false),
    '\n',
  );

  result = result.replaceAll(RegExp(r'<[^>]+>'), '');

  result = result.replaceAll('&amp;', '&');
  result = result.replaceAll('&lt;', '<');
  result = result.replaceAll('&gt;', '>');
  result = result.replaceAll('&quot;', '"');
  result = result.replaceAll('&#39;', "'");
  result = result.replaceAll('&apos;', "'");
  result = result.replaceAllMapped(
    RegExp(r'&#(\d+);'),
    (m) {
      final code = int.tryParse(m[1]!);
      return code != null ? String.fromCharCode(code) : m[0]!;
    },
  );
  result = result.replaceAll(RegExp(r'&nbsp;'), ' ');

  result = result.replaceAll(RegExp(r'\n{3,}'), '\n\n');

  if (result.contains('~~')) {
    log('[htmlToMarkdown] ~~ found in output', error: 'BEFORE_COLOR:\n$afterColor\n\nAFTER:\n$result');
  }

  return result.trim();
}

String _inline(String text) {
  return text.replaceAll(RegExp(r'<[^>]+>'), '').trim();
}

String _stripBlock(String html, String tag) {
  return html.replaceAll(RegExp('<$tag[^>]*>.*?</$tag>', caseSensitive: false, dotAll: true), '');
}

String _convertInline(String html, String tag, String marker) {
  return html.replaceAllMapped(
    RegExp('<$tag[^>]*>(.*?)</$tag>', caseSensitive: false, dotAll: true),
    (match) => '$marker${_inline(match[1]!)}$marker',
  );
}

final _cssColorRegex = RegExp(r'(?:(?:color|background-color)\s*:\s*)(#[0-9a-fA-F]{3,8}|(?:rgb|hsl)a?\([^)]+\)|[a-zA-Z]+)');

String _extractColor(String styleAttr) {
  final match = _cssColorRegex.firstMatch(styleAttr);
  if (match == null) return '';
  var color = match[1]!.trim();
  if (color.startsWith('rgb')) {
    color = _rgbToHex(color);
  }
  if (color.startsWith('hsl')) {
    color = _hslToHex(color);
  }
  if (RegExp(r'^[a-zA-Z]+$').hasMatch(color)) {
    final hex = _namedColorToHex(color.toLowerCase());
    if (hex != null) color = hex;
  }
  if (!color.startsWith('#')) return '';
  return color;
}

String _convertInlineTags(String html) {
  var result = html;
  for (final entry in [
    ('strong', '**'), ('b', '**'), ('em', '*'), ('i', '*'),
    ('del', '~~'), ('s', '~~'), ('u', '__'), ('code', '`'),
  ]) {
    result = result.replaceAllMapped(
      RegExp('<${entry.$1}[^>]*>(.*?)</${entry.$1}>', caseSensitive: false, dotAll: true),
      (m) => '${entry.$2}${m[1]!}${entry.$2}',
    );
  }
  return result;
}

String _wrapColored(String color, String content) {
  if (!color.startsWith('#')) return _inline(content);
  final text = _convertInlineTags(content).replaceAll(RegExp(r'<[^>]+>'), '').trim();
  return text.split('\n').map((line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return '';
    return '==hc:$color==$trimmed==';
  }).join('\n');
}

String _convertColoredSpan(String html) {
  return html.replaceAllMapped(
    RegExp(r'''<span\s+[^>]*style=(["'])([^"']*?)\1[^>]*>(.*?)</span>''', caseSensitive: false, dotAll: true),
    (m) {
      final color = _extractColor(m[2]!);
      if (color.isEmpty) return _inline(m[3]!);
      return _wrapColored(color, m[3]!);
    },
  );
}

String _convertColoredFont(String html) {
  return html.replaceAllMapped(
    RegExp(r'''<font\s+[^>]*color=(["'])([^"']*?)\1[^>]*>(.*?)</font>''', caseSensitive: false, dotAll: true),
    (m) {
      var color = m[2]!.trim();
      if (RegExp(r'^[a-zA-Z]+$').hasMatch(color)) {
        final hex = _namedColorToHex(color.toLowerCase());
        if (hex != null) color = hex;
      }
      return _wrapColored(color, m[3]!);
    },
  );
}

String _rgbToHex(String rgb) {
  final nums = RegExp(r'(\d+)').allMatches(rgb).map((m) => int.parse(m[1]!)).toList();
  if (nums.length < 3) return rgb;
  final r = nums[0].clamp(0, 255);
  final g = nums[1].clamp(0, 255);
  final b = nums[2].clamp(0, 255);
  return '#${r.toRadixString(16).padLeft(2, '0')}${g.toRadixString(16).padLeft(2, '0')}${b.toRadixString(16).padLeft(2, '0')}';
}

String _hslToHex(String hsl) {
  final nums = RegExp(r'([\d.]+)').allMatches(hsl).map((m) => double.parse(m[1]!)).toList();
  if (nums.length < 3) return hsl;
  final h = nums[0] / 360;
  final s = nums[1] / 100;
  final l = nums[2] / 100;
  if (s == 0) {
    final v = (l * 255).round().clamp(0, 255);
    return '#${v.toRadixString(16).padLeft(2, '0')}${v.toRadixString(16).padLeft(2, '0')}${v.toRadixString(16).padLeft(2, '0')}';
  }
  double hue2rgb(double p, double q, double t) {
    if (t < 0) t += 1;
    if (t > 1) t -= 1;
    if (t < 1 / 6) return p + (q - p) * 6 * t;
    if (t < 1 / 2) return q;
    if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6;
    return p;
  }
  final q = l < 0.5 ? l * (1 + s) : l + s - l * s;
  final p = 2 * l - q;
  final r = (hue2rgb(p, q, h + 1 / 3) * 255).round().clamp(0, 255);
  final g = (hue2rgb(p, q, h) * 255).round().clamp(0, 255);
  final b = (hue2rgb(p, q, h - 1 / 3) * 255).round().clamp(0, 255);
  return '#${r.toRadixString(16).padLeft(2, '0')}${g.toRadixString(16).padLeft(2, '0')}${b.toRadixString(16).padLeft(2, '0')}';
}

const _namedColors = <String, String>{
  'red': '#ff0000', 'crimson': '#dc143c', 'firebrick': '#b22222', 'darkred': '#8b0000',
  'orange': '#ff8c00', 'orangered': '#ff4500', 'darkorange': '#ff8c00',
  'yellow': '#ffff00', 'gold': '#ffd700', 'khaki': '#f0e68c',
  'green': '#008000', 'lime': '#00ff00', 'limegreen': '#32cd32', 'forestgreen': '#228b22',
  'seagreen': '#2e8b57', 'darkgreen': '#006400', 'olive': '#808000',
  'cyan': '#00ffff', 'aqua': '#00ffff', 'teal': '#008080', 'darkcyan': '#008b8b',
  'blue': '#0000ff', 'navy': '#000080', 'darkblue': '#00008b', 'royalblue': '#4169e1',
  'steelblue': '#4682b4', 'cornflowerblue': '#6495ed',
  'purple': '#800080', 'magenta': '#ff00ff', 'fuchsia': '#ff00ff', 'violet': '#ee82ee',
  'indigo': '#4b0082', 'darkviolet': '#9400d3', 'blueviolet': '#8a2be2',
  'pink': '#ffc0cb', 'hotpink': '#ff69b4', 'deeppink': '#ff1493',
  'white': '#ffffff', 'silver': '#c0c0c0', 'gray': '#808080', 'grey': '#808080',
  'darkgray': '#a9a9a9', 'darkgrey': '#a9a9a9', 'lightgray': '#d3d3d3', 'lightgrey': '#d3d3d3',
  'black': '#000000', 'snow': '#fffafa', 'ivory': '#fffff0',
  'coral': '#ff7f50', 'tomato': '#ff6347', 'salmon': '#fa8072',
  'chocolate': '#d2691e', 'sienna': '#a0522d', 'tan': '#d2b48c',
  'wheat': '#f5deb3', 'burlywood': '#deb887', 'peru': '#cd853f',
  'maroon': '#800000', 'brown': '#a52a2a',
};

String? _namedColorToHex(String name) => _namedColors[name];

bool hasHtmlTags(String content) => _htmlTagRegex.hasMatch(content);

String stripHtml(String content) {
  if (!hasHtmlTags(content)) return content;
  var result = _stripBlock(content, 'style');
  result = _stripBlock(result, 'script');
  result = result.replaceAll(RegExp(r'<br\s*/?>\s*', caseSensitive: false), '\n');
  result = result.replaceAll(RegExp(r'<[^>]+>'), '');
  result = result.replaceAll('&amp;', '&');
  result = result.replaceAll('&lt;', '<');
  result = result.replaceAll('&gt;', '>');
  result = result.replaceAll('&quot;', '"');
  result = result.replaceAll('&#39;', "'");
  result = result.replaceAll('&apos;', "'");
  result = result.replaceAll(RegExp(r'&nbsp;'), ' ');
  return result.replaceAll(RegExp(r'\n{2,}'), '\n').trim();
}

final _htmlTagRegex = RegExp(
  r'<(div|span|p|br|img|a|table|tr|td|th|ul|ol|li|h[1-6]|hr|pre|code|blockquote|style|font|center|b|i|u|s|em|strong|small|sub|sup|mark|details|summary|section|article|header|footer|nav|figure|figcaption|iframe)\b',
  caseSensitive: false,
);
