import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:gpt_markdown/custom_widgets/markdown_config.dart';

Color? parseHexColor(String hex) {
  var h = hex.replaceFirst('#', '');
  if (h.length == 3) h = '${h[0]}${h[0]}${h[1]}${h[1]}${h[2]}${h[2]}';
  if (h.length == 4) h = '${h[0]}${h[0]}${h[1]}${h[1]}${h[2]}${h[2]}${h[3]}${h[3]}';
  if (h.length == 6) h = 'ff$h';
  if (h.length != 8) return null;
  final value = int.tryParse(h, radix: 16);
  if (value == null) return null;
  return Color(value);
}

class HtmlColorMd extends InlineMd {
  @override
  RegExp get exp => RegExp(r'==hc:(#[0-9a-fA-F]{3,8})==(.+?)==', dotAll: true);

  @override
  InlineSpan span(BuildContext context, String text, GptMarkdownConfig config) {
    final match = exp.firstMatch(text);
    final colorHex = match?[1] ?? '#ffffff';
    final content = match?[2] ?? '';
    final color = parseHexColor(colorHex) ?? (config.style?.color ?? Colors.white);
    return TextSpan(
      children: MarkdownComponent.generate(context, content, config.copyWith(
        style: (config.style ?? const TextStyle()).copyWith(color: color),
      ), false),
      style: (config.style ?? const TextStyle()).copyWith(color: color),
    );
  }
}

class GlowTextMd extends InlineMd {
  @override
  RegExp get exp => RegExp(r'==glow:(#[0-9a-fA-F]{3,8}),(\d+)==(.+?)==', dotAll: true);

  @override
  InlineSpan span(BuildContext context, String text, GptMarkdownConfig config) {
    final match = exp.firstMatch(text);
    final glowColorHex = match?[1] ?? '#ffffff';
    final blurRadius = int.tryParse(match?[2] ?? '4') ?? 4;
    final content = match?[3] ?? '';
    final glowColor = parseHexColor(glowColorHex) ?? Colors.white;
    final baseStyle = config.style ?? const TextStyle();
    return TextSpan(
      children: MarkdownComponent.generate(context, content, config.copyWith(
        style: baseStyle.copyWith(
          shadows: [
            Shadow(color: glowColor, blurRadius: blurRadius.toDouble()),
            Shadow(color: glowColor, blurRadius: blurRadius.toDouble() * 0.5),
          ],
        ),
      ), false),
      style: baseStyle.copyWith(
        shadows: [
          Shadow(color: glowColor, blurRadius: blurRadius.toDouble()),
          Shadow(color: glowColor, blurRadius: blurRadius.toDouble() * 0.5),
        ],
      ),
    );
  }
}

class ColorGlowTextMd extends InlineMd {
  @override
  RegExp get exp => RegExp(r'==cg:(#[0-9a-fA-F]{3,8}),(#[0-9a-fA-F]{3,8}),(\d+)==(.+?)==', dotAll: true);

  @override
  InlineSpan span(BuildContext context, String text, GptMarkdownConfig config) {
    final match = exp.firstMatch(text);
    final textColorHex = match?[1] ?? '#ffffff';
    final glowColorHex = match?[2] ?? '#ffffff';
    final blurRadius = int.tryParse(match?[3] ?? '4') ?? 4;
    final content = match?[4] ?? '';
    final textColor = parseHexColor(textColorHex) ?? Colors.white;
    final glowColor = parseHexColor(glowColorHex) ?? Colors.white;
    final baseStyle = config.style ?? const TextStyle();
    return TextSpan(
      children: MarkdownComponent.generate(context, content, config.copyWith(
        style: baseStyle.copyWith(
          color: textColor,
          shadows: [
            Shadow(color: glowColor, blurRadius: blurRadius.toDouble()),
            Shadow(color: glowColor, blurRadius: blurRadius.toDouble() * 0.5),
          ],
        ),
      ), false),
      style: baseStyle.copyWith(
        color: textColor,
        shadows: [
          Shadow(color: glowColor, blurRadius: blurRadius.toDouble()),
          Shadow(color: glowColor, blurRadius: blurRadius.toDouble() * 0.5),
        ],
      ),
    );
  }
}

class GradientTextMd extends InlineMd {
  @override
  RegExp get exp => RegExp(r'==grad:(#[0-9a-fA-F]{3,8}(?:,#[0-9a-fA-F]{3,8})+)==(.+?)==', dotAll: true);

  @override
  InlineSpan span(BuildContext context, String text, GptMarkdownConfig config) {
    final match = exp.firstMatch(text);
    if (match == null) {
      return TextSpan(text: text, style: config.style);
    }
    final colorsParam = match[1]!;
    final content = match[2]!;

    final colors = RegExp(r'#[0-9a-fA-F]{3,8}')
        .allMatches(colorsParam)
        .map((m) => parseHexColor(m[0]!) ?? Colors.white)
        .toList();

    if (colors.length < 2) {
      final baseStyle = config.style ?? const TextStyle();
      return TextSpan(
        children: MarkdownComponent.generate(context, content, config, false),
        style: baseStyle,
      );
    }

    final baseStyle = config.style ?? const TextStyle();
    final fontSize = baseStyle.fontSize ?? 14;

    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: ShaderMask(
        shaderCallback: (bounds) => LinearGradient(
          colors: colors,
        ).createShader(Rect.fromLTWH(0, 0, bounds.width, bounds.height)),
        blendMode: BlendMode.srcIn,
        child: Text(
          content,
          style: baseStyle.copyWith(
            color: Colors.white,
            fontSize: fontSize,
          ),
        ),
      ),
    );
  }
}

class BackgroundTextMd extends InlineMd {
  @override
  RegExp get exp => RegExp(r'==bg:(#[0-9a-fA-F]{3,8})==(.+?)==', dotAll: true);

  @override
  InlineSpan span(BuildContext context, String text, GptMarkdownConfig config) {
    final match = exp.firstMatch(text);
    final bgColorHex = match?[1] ?? '#333333';
    final content = match?[2] ?? '';
    final bgColor = parseHexColor(bgColorHex) ?? const Color(0xFF333333);
    final baseStyle = config.style ?? const TextStyle();
    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Container(
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(4),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        child: Text(
          content,
          style: baseStyle.copyWith(color: Colors.white),
        ),
      ),
    );
  }
}

class ColoredItalicMd extends InlineMd {
  final Color? color;
  ColoredItalicMd({this.color});

  @override
  RegExp get exp =>
      RegExp(r"(?:(?<!\*)\*(?<!\s)(.+?)(?<!\s)\*(?!\*))", dotAll: true);

  @override
  InlineSpan span(
    BuildContext context,
    String text,
    final GptMarkdownConfig config,
  ) {
    var match = exp.firstMatch(text.trim());
    var data = match?[1] ?? match?[2];
    var conf = config.copyWith(
      style: (config.style ?? const TextStyle()).copyWith(
        fontStyle: FontStyle.italic,
        color: color ?? config.style?.color,
      ),
    );
    return TextSpan(
      children: MarkdownComponent.generate(context, "$data", conf, false),
      style: conf.style,
    );
  }
}

class ColoredUnderscoreItalicMd extends InlineMd {
  final Color? color;
  ColoredUnderscoreItalicMd({this.color});

  @override
  RegExp get exp =>
      RegExp(r"(?:(?<!_|\w)_(?<!\s)(.+?)(?<!\s)_(?!_|\w))", dotAll: true);

  @override
  InlineSpan span(
    BuildContext context,
    String text,
    final GptMarkdownConfig config,
  ) {
    var match = exp.firstMatch(text.trim());
    var data = match?[1] ?? match?[2];
    var conf = config.copyWith(
      style: (config.style ?? const TextStyle()).copyWith(
        fontStyle: FontStyle.italic,
        color: color ?? config.style?.color,
      ),
    );
    return TextSpan(
      children: MarkdownComponent.generate(context, "$data", conf, false),
      style: conf.style,
    );
  }
}

class ColoredBoldMd extends InlineMd {
  final Color? color;
  ColoredBoldMd({this.color});

  @override
  RegExp get exp => RegExp(r"(?<!\*)\*\*(?<!\s)(.+?)(?<!\s)\*\*(?!\*)");

  @override
  InlineSpan span(
    BuildContext context,
    String text,
    final GptMarkdownConfig config,
  ) {
    var match = exp.firstMatch(text.trim());
    var conf = config.copyWith(
      style: (config.style ?? const TextStyle()).copyWith(
        fontWeight: FontWeight.bold,
        color: color ?? config.style?.color,
      ),
    );
    return TextSpan(
      children: MarkdownComponent.generate(context, "${match?[1]}", conf, false),
      style: conf.style,
    );
  }
}

class ColoredUnderscoreBoldMd extends InlineMd {
  final Color? color;
  ColoredUnderscoreBoldMd({this.color});

  @override
  RegExp get exp => RegExp(r"(?<!_|\w)__(?<!\s)(.+?)(?<!\s)__(?!_|\w)");

  @override
  InlineSpan span(
    BuildContext context,
    String text,
    final GptMarkdownConfig config,
  ) {
    var match = exp.firstMatch(text.trim());
    var conf = config.copyWith(
      style: (config.style ?? const TextStyle()).copyWith(
        fontWeight: FontWeight.bold,
        color: color ?? config.style?.color,
      ),
    );
    return TextSpan(
      children: MarkdownComponent.generate(context, "${match?[1]}", conf, false),
      style: conf.style,
    );
  }
}
