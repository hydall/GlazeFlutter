import 'dart:convert' as convert;

import 'package:glaze_flutter/core/constants/image_gen_patterns.dart';

String htmlToMarkdown(String html) {
  var result = html;

  result = _stripBlock(result, 'style');
  result = _stripBlock(result, 'script');

  result = result.replaceAll(RegExp(r'<br\s*/?>\s*', caseSensitive: false), '\n');

  final detailsBlocks = <String>[];
  result = result.replaceAllMapped(
    RegExp(r'<details[^>]*>.*?</details>', caseSensitive: false, dotAll: true),
    (m) {
      final idx = detailsBlocks.length;
      detailsBlocks.add(m[0]!);
      return '\n\x00DETAILS$idx\x00\n';
    },
  );

  result = _convertColoredSpan(result);
  result = _convertColoredFont(result);
  result = _convertBackgroundImages(result);

  result = result.replaceAllMapped(
    RegExp(r'<h([1-6])[^>]*>(.*?)</h\1>', caseSensitive: false, dotAll: true),
    (m) => '\n${'#' * int.parse(m[1]!)} ${_inline(m[2]!)}\n',
  );

  result = _convertInline(result, 'strong', '**');
  result = _convertInline(result, 'b', '**');

  result = _extractStyledImageFrames(result);

  result = result.replaceAllMapped(
    RegExp(r'<img\s[^>]*>', caseSensitive: false, dotAll: true),
    (m) {
      final tag = m[0]!;
      final iigDouble = RegExp(r'''data-iig-instruction\s*=\s*"([^"]*)"''', caseSensitive: false).firstMatch(tag);
      final iigSingle = RegExp(r"""data-iig-instruction\s*=\s*'([^']*)'""", caseSensitive: false).firstMatch(tag);
      final iigMatch = iigDouble ?? iigSingle;
      if (iigMatch != null) {
        return '[IMG:GEN:${iigMatch[1]!}]';
      }
      final srcMatch = RegExp(r'''src\s*=\s*["']([^"']*)["']''', caseSensitive: false).firstMatch(tag);
      if (srcMatch != null) {
        return '![](${srcMatch[1]!})';
      }
      return '';
    },
  );

  result = result.replaceAllMapped(
    RegExp(r'''<a[^>]*href=["']([^"']*)["'][^>]*>(.*?)</a>''', caseSensitive: false, dotAll: true),
    (m) => '[${_inline(m[2]!)}](${m[1]!})',
  );

  result = result.replaceAllMapped(
    RegExp(r'<p[^>]*>(.*?)</p>', caseSensitive: false, dotAll: true),
    (m) => '\n${_inline(m[1]!)}\n',
  );

  result = result.replaceAllMapped(
    RegExp(r'<blockquote[^>]*>(.*?)</blockquote>', caseSensitive: false, dotAll: true),
    (m) => _inline(m[1]!).split('\n').map((l) => '> $l').join('\n'),
  );

  result = _convertInline(result, 'em', '*');
  result = _convertInline(result, 'i', '*');
  result = _convertInline(result, 'del', '~~');
  result = _convertInline(result, 's', '~~');
  result = _convertInlineKeep(result, 'u');
  result = _convertInline(result, 'code', '`');

  result = result.replaceAllMapped(
    RegExp(r'<hr\s*/?>', caseSensitive: false),
    (m) => '\n---\n',
  );

  result = result.replaceAll(
    RegExp(r'</?(?:div|span|section|article|header|footer|nav|main|figure|figcaption|center|font|small|sub|sup|mark|table|tr|td|th|thead|tbody|ul|ol|li|dl|dt|dd|pre)[^>]*>', caseSensitive: false),
    '\n',
  );

  result = result.replaceAll(RegExp(r'<[^>]+>'), '');

  for (var i = 0; i < detailsBlocks.length; i++) {
    final block = detailsBlocks[i];
    final summaryMatch = RegExp(r'<summary[^>]*>(.*?)</summary>', caseSensitive: false, dotAll: true).firstMatch(block);
    final summary = summaryMatch != null ? _inline(summaryMatch[1]!) : 'Details';
    var body = block;
    if (summaryMatch != null) {
      body = block.replaceFirst(summaryMatch.group(0)!, '');
    }
    body = body.replaceAll(RegExp(r'<[^>]+>'), '').trim();
    final restored = '<details><summary>$summary</summary>$body</details>';
    result = result.replaceFirst('\x00DETAILS$i\x00', restored);
  }

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

String _convertInlineKeep(String html, String tag) {
  return html.replaceAllMapped(
    RegExp('<$tag[^>]*>(.*?)</$tag>', caseSensitive: false, dotAll: true),
    (match) => '<$tag>${_inline(match[1]!)}</$tag>',
  );
}

final _cssColorRegex = RegExp(r'(?:(?:color|background-color)\s*:\s*)(#[0-9a-fA-F]{3,8}|(?:rgb|hsl)a?\([^)]+\)|[a-zA-Z]+)');

final _textShadowColorRegex = RegExp(r'text-shadow\s*:[^;]*?(#[0-9a-fA-F]{3,8}|(?:rgb|hsl)a?\([^)]+\)|[a-zA-Z]+)');

final _gradientColorsRegex = RegExp(r'linear-gradient\s*\([^)]*\)');

List<String> _extractGradientColors(String styleAttr) {
  final gradMatch = _gradientColorsRegex.firstMatch(styleAttr);
  if (gradMatch == null) return [];
  final gradContent = gradMatch[0]!;
  final hexMatches = RegExp(r'#[0-9a-fA-F]{3,8}').allMatches(gradContent);
  return hexMatches.map((m) => m[0]!).toList();
}

final _textShadowRegex = RegExp(r'text-shadow\s*:\s*([^;]+)');

class _ShadowInfo {
  final String color;
  final double blur;
  _ShadowInfo(this.color, this.blur);
}

List<_ShadowInfo> _extractTextShadows(String styleAttr) {
  final match = _textShadowRegex.firstMatch(styleAttr);
  if (match == null) return [];
  var value = match[1]!.trim();
  final placeholders = <String, String>{};
  var idx = 0;
  value = value.replaceAllMapped(
    RegExp(r'(?:rgb|hsl)a?\([^)]+\)'),
    (m) {
      final key = '\x00PH$idx\x00';
      placeholders[key] = m[0]!;
      idx++;
      return key;
    },
  );
  final shadows = <_ShadowInfo>[];
  for (final part in value.split(',')) {
    final trimmed = part.trim();
    if (trimmed.isEmpty) continue;
    var resolved = trimmed;
    for (final entry in placeholders.entries) {
      resolved = resolved.replaceFirst(entry.key, entry.value);
    }
    var color = '';
    double? blur;
    final hexMatch = RegExp(r'(#[0-9a-fA-F]{3,8})').firstMatch(resolved);
    if (hexMatch != null) color = hexMatch[1]!;
    final rgbaMatch = RegExp(r'(?:rgb|hsl)a?\([^)]+\)').firstMatch(resolved);
    if (color.isEmpty && rgbaMatch != null) color = _rgbToHex(rgbaMatch[0]!);
    if (color.isEmpty) {
      final namedMatch = RegExp(r'^([a-zA-Z]+)').firstMatch(resolved);
      if (namedMatch != null) {
        final hex = _namedColorToHex(namedMatch[1]!.toLowerCase());
        if (hex != null) color = hex;
      }
    }
    final blurMatch = RegExp(r'(\d+(?:\.\d+)?)px\s*$').firstMatch(resolved);
    if (blurMatch != null) blur = double.tryParse(blurMatch[1]!);
    if (color.isNotEmpty) shadows.add(_ShadowInfo(color, blur ?? 4.0));
  }
  return shadows;
}

String _extractColor(String styleAttr) {
  var color = _extractColorFromCss(styleAttr);
  if (color.isEmpty) color = _extractColorFromTextShadow(styleAttr);
  if (color.isEmpty) {
    final gradColors = _extractGradientColors(styleAttr);
    if (gradColors.isNotEmpty) color = gradColors.first;
  }
  return color;
}

String _extractColorFromCss(String styleAttr) {
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

final _bgColorRegex = RegExp(r'background-color\s*:\s*(#[0-9a-fA-F]{3,8}|(?:rgb|hsl)a?\([^)]+\)|[a-zA-Z]+)');

String _extractBgColor(String styleAttr) {
  final match = _bgColorRegex.firstMatch(styleAttr);
  if (match == null) return '';
  var color = match[1]!.trim();
  if (color.startsWith('rgb')) color = _rgbToHex(color);
  if (color.startsWith('hsl')) color = _hslToHex(color);
  if (RegExp(r'^[a-zA-Z]+$').hasMatch(color)) {
    final hex = _namedColorToHex(color.toLowerCase());
    if (hex != null) color = hex;
  }
  if (!color.startsWith('#')) return '';
  return color;
}

String _extractColorFromTextShadow(String styleAttr) {
  final match = _textShadowColorRegex.firstMatch(styleAttr);
  if (match == null) return '';
  var color = match[1]!.trim();
  if (color.startsWith('rgb')) color = _rgbToHex(color);
  if (color.startsWith('hsl')) color = _hslToHex(color);
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
    ('del', '~~'), ('s', '~~'), ('code', '`'),
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
  // Variant C: carry rich inner HTML (including <summary>, nested tags, etc.)
  // so the webview renderer can render color + structure.
  final inner = content.trim();
  if (inner.isEmpty) return '';
  return '==hc:$color==$inner==';
}

String _convertColoredSpan(String html) {
  return html.replaceAllMapped(
    RegExp(r'''<span\s+[^>]*style=(["'])(.*?)\1[^>]*>(.*?)</span>''', caseSensitive: false, dotAll: true),
    (m) {
      final styleAttr = m[2]!;
      final content = m[3]!;
      final text = _convertInlineTags(content).replaceAll(RegExp(r'<[^>]+>'), '').trim();
      if (text.isEmpty) return '';

      final cssColor = _extractColorFromCss(styleAttr);
      final bgColor = _extractBgColor(styleAttr);
      final shadows = _extractTextShadows(styleAttr);
      final isItalic = RegExp(r'font-style\s*:\s*italic', caseSensitive: false).hasMatch(styleAttr);

      if (bgColor.isNotEmpty) {
        return text.split('\n').map((line) {
          final trimmed = line.trim();
          if (trimmed.isEmpty) return '';
          // Variant C: preserve rich inner HTML for background blocks too
          return '==bg:$bgColor==${content.trim()}==';
        }).join('\n');
      }

      if (cssColor.isNotEmpty && shadows.isNotEmpty) {
        final shadow = shadows.first;
        return '==cg:$cssColor,${shadow.color},${shadow.blur.round()}==${content.trim()}==';
      }
      if (shadows.isNotEmpty) {
        final shadow = shadows.first;
        return '==glow:${shadow.color},${shadow.blur.round()}==${content.trim()}==';
      }
      if (cssColor.isNotEmpty) return _wrapColored(cssColor, content);

      if (isItalic) return '*$text*';
      return _inline(content);
    },
  );
}

String _convertColoredFont(String html) {
  var result = html.replaceAllMapped(
    RegExp(r'''<font\s+[^>]*color=(["'])(.*?)\1[^>]*>(.*?)</font>''', caseSensitive: false, dotAll: true),
    (m) {
      var color = m[2]!.trim();
      if (RegExp(r'^[a-zA-Z]+$').hasMatch(color)) {
        final hex = _namedColorToHex(color.toLowerCase());
        if (hex != null) color = hex;
      }
      return _wrapColored(color, m[3]!);
    },
  );

  result = result.replaceAllMapped(
    RegExp(r'''<font\s+[^>]*style=(["'])(.*?)\1[^>]*>(.*?)</font>''', caseSensitive: false, dotAll: true),
    (m) {
      final styleAttr = m[2]!;
      final content = m[3]!;
      final text = _convertInlineTags(content).replaceAll(RegExp(r'<[^>]+>'), '').trim();
      if (text.isEmpty) return '';

      final gradColors = _extractGradientColors(styleAttr);
      if (gradColors.length >= 2) {
        // Variant C: pass original rich inner content (may contain <summary> etc.)
        return '==grad:${gradColors.join(",")}==${content.trim()}==';
      }
      if (gradColors.length == 1) return _wrapColored(gradColors.first, content);

      final color = _extractColor(styleAttr);
      if (color.isNotEmpty) return _wrapColored(color, content);
      // No recognized color/gradient — fall back to stripped text for plain style-only font
      return text;
    },
  );

  return result;
}

final _bgImageUrlRegex = RegExp(r"""background[^:]*:\s*[^;]*?url\(\s*['"]?([^'")\s]+)['"]?\s*\)""", caseSensitive: true);

String _convertBackgroundImages(String html) {
  return html.replaceAllMapped(
    RegExp(r'<((?:div|span|section|article)\s[^>]*?)style=(["\x27])(.*?)\2([^>]*>)', caseSensitive: false, dotAll: true),
    (m) {
      final urlMatch = _bgImageUrlRegex.firstMatch(m[3]!);
      if (urlMatch != null) {
        return '\n![](${urlMatch[1]!})\n';
      }
      return '<${m[1]}style=${m[2]}${m[3]}${m[2]}${m[4]}';
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

bool hasHtmlTags(String content) => content.contains('<') && _htmlTagRegex.hasMatch(content);

String ensureLineBreaks(String text) {
  final buffer = StringBuffer();
  var i = 0;
  while (i < text.length) {
    if (text[i] == '\n') {
      var nextNonNewline = i + 1;
      while (nextNonNewline < text.length && text[nextNonNewline] == '\n') {
        nextNonNewline++;
      }
      final newlineCount = nextNonNewline - i;
      if (newlineCount >= 2) {
        for (var n = 0; n < newlineCount; n++) buffer.write('\n');
      } else {
        buffer.write('  \n');
      }
      i = nextNonNewline;
    } else {
      buffer.write(text[i]);
      i++;
    }
  }
  return buffer.toString();
}

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

String _extractStyledImageFrames(String html) {
  final imgRegex = ImgGenPatterns.htmlIigTagRegex;
  final imgRegexDouble = ImgGenPatterns.htmlIigTagDoubleRegex;

  final matches = <RegExpMatch>[];
  matches.addAll(imgRegex.allMatches(html));
  matches.addAll(imgRegexDouble.allMatches(html));
  matches.sort((a, b) => a.start.compareTo(b.start));

  if (matches.isEmpty) return html;

  var result = html;
  int offset = 0;

  for (final m in matches) {
    final instructionRaw = m[1]!;
    final adjustedStart = m.start + offset;
    final adjustedEnd = m.end + offset;

    String? containerStyle;
    int blockStart = adjustedStart;

    final before = result.substring(0, adjustedStart);
    final divOpenMatch = RegExp(r"""<div\s[^>]*?style\s*=\s*["']([^"']+)["'][^>]*>\s*$""", caseSensitive: false).firstMatch(before);
    if (divOpenMatch != null) {
      containerStyle = divOpenMatch[1]!;
      blockStart = divOpenMatch.start;
    }

    String? caption;
    int blockEnd = adjustedEnd;

    final after = result.substring(adjustedEnd);
    final captionMatch = RegExp(r'\s*(?:<div[^>]*>)?\s*<i>([\s\S]*?)</i>\s*(?:</div>)?\s*</div>', caseSensitive: false).firstMatch(after);
    if (captionMatch != null) {
      caption = captionMatch[1]!.trim();
      blockEnd = adjustedEnd + captionMatch.end;
    }

    String enrichedJson;
    try {
      final json = Map<String, dynamic>.from(convert.jsonDecode(instructionRaw) as Map);
      if (containerStyle != null) json['containerStyle'] = containerStyle;
      if (caption != null) json['caption'] = caption;
      enrichedJson = convert.jsonEncode(json);
    } catch (_) {
      enrichedJson = instructionRaw;
    }

    final replacement = '[IMG:GEN:$enrichedJson]';
    result = result.substring(0, blockStart) + replacement + result.substring(blockEnd);
    offset += replacement.length - (blockEnd - blockStart);
  }

  return result;
}
