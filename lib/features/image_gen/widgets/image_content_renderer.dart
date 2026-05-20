import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

import '../../../shared/theme/app_colors.dart';
import '../../../shared/widgets/colored_markdown.dart';
import '../../chat/widgets/message.dart' show MarkMd, ActiveMarkMd;

class ImageContentRenderer extends StatelessWidget {
  final String content;
  final Color textColor;
  final VoidCallback? onRegenerate;

  const ImageContentRenderer({
    super.key,
    required this.content,
    required this.textColor,
    this.onRegenerate,
  });

  static final _imgGenRegex = RegExp(r'\[IMG:GEN(?::(.*?))?\]');
  static final _imgResultRegex = RegExp(r'\[IMG:RESULT:(.*?)\]');
  static final _imgErrorRegex = RegExp(r'\[IMG:ERROR:(.*?)\]');

  static bool hasImageMarkers(String text) =>
      _imgGenRegex.hasMatch(text) ||
      _imgResultRegex.hasMatch(text) ||
      _imgErrorRegex.hasMatch(text);

  @override
  Widget build(BuildContext context) {
    final spans = <_ContentSpan>[];
    int pos = 0;

    final allMarkers = <({int start, int end, _ContentSpan span})>[];

    for (final m in _imgGenRegex.allMatches(content)) {
      allMarkers.add((start: m.start, end: m.end, span: _ImgGenSpan(m.group(1) ?? '')));
    }
    for (final m in _imgResultRegex.allMatches(content)) {
      allMarkers.add((start: m.start, end: m.end, span: _ImgResultSpan(m.group(1) ?? '')));
    }
    for (final m in _imgErrorRegex.allMatches(content)) {
      allMarkers.add((start: m.start, end: m.end, span: _ImgErrorSpan(m.group(1) ?? '')));
    }

    allMarkers.sort((a, b) => a.start.compareTo(b.start));

    for (final marker in allMarkers) {
      if (marker.start > pos) {
        spans.add(_TextSpan(content.substring(pos, marker.start)));
      }
      spans.add(marker.span);
      pos = marker.end;
    }
    if (pos < content.length) {
      spans.add(_TextSpan(content.substring(pos)));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: spans.map((s) => _buildSpanWidget(context, s)).toList(),
    );
  }

  static _InstructionData? _parseInstruction(String raw) {
    if (raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return _InstructionData(
        style: json['style'] as String? ?? '',
        prompt: (json['prompt'] as String? ?? '').replaceFirst(RegExp(r'^SCENE_PROMPT:\s*'), ''),
        caption: json['caption'] as String? ?? '',
        aspectRatio: json['aspect_ratio'] as String? ?? '',
        imageSize: json['image_size'] as String? ?? '',
        containerStyle: json['containerStyle'] as String? ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  static double _parseAspectRatio(String? ratio) {
    if (ratio == null || ratio.isEmpty) return 16 / 9;
    final parts = ratio.split(':');
    if (parts.length == 2) {
      final w = double.tryParse(parts[0]);
      final h = double.tryParse(parts[1]);
      if (w != null && h != null && w > 0 && h > 0) return w / h;
    }
    return 16 / 9;
  }

  Widget _buildFrame({required Widget child, String? containerStyle}) {
    final deco = containerStyle != null && containerStyle.isNotEmpty
        ? _parseCssDecoration(containerStyle)
        : null;

    return Container(
      margin: deco?.margin ?? const EdgeInsets.symmetric(vertical: 8),
      constraints: BoxConstraints(maxWidth: deco?.maxWidth ?? 680),
      decoration: BoxDecoration(
        color: deco?.color ?? const Color(0xFF0F0F1C).withValues(alpha: 0.94),
        borderRadius: deco?.borderRadius ?? BorderRadius.circular(20),
        border: deco?.border ?? Border.all(color: const Color(0xFF825ADC).withValues(alpha: 0.25)),
        boxShadow: deco?.boxShadow ?? [
          BoxShadow(color: Colors.black.withValues(alpha: 0.75), blurRadius: 40, offset: const Offset(0, 12)),
          BoxShadow(color: const Color(0xFF7850D2).withValues(alpha: 0.18), blurRadius: 30),
        ],
      ),
      padding: deco?.padding ?? const EdgeInsets.all(18),
      child: child,
    );
  }

  Widget _buildCaption(String caption) {
    if (caption.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 15),
      child: Center(
        child: Text(
          caption,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFFC8C8C8),
            fontSize: 13,
            height: 1.45,
            fontStyle: FontStyle.italic,
          ),
        ),
      ),
    );
  }

  Widget _buildSpanWidget(BuildContext context, _ContentSpan span) {
    if (span is _TextSpan) {
      if (span.text.trim().isEmpty) return const SizedBox.shrink();
      return GptMarkdown(
        span.text,
        style: TextStyle(color: textColor),
        inlineComponents: _kInlineComponents,
      );
    }
    if (span is _ImgResultSpan) {
      final file = File(span.path);
      if (!file.existsSync()) {
        return _buildFrame(
          child: Text('[Image not found]', style: TextStyle(color: textColor.withValues(alpha: 0.5), fontSize: 12, fontStyle: FontStyle.italic)),
        );
      }
      return _buildFrame(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 500),
            child: Image.file(file, fit: BoxFit.contain),
          ),
        ),
      );
    }
    if (span is _ImgGenSpan) {
      final data = _parseInstruction(span.instruction);
      return _buildFrame(
        containerStyle: data?.containerStyle,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: _parseAspectRatio(data?.aspectRatio),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: context.cs.primary)),
                      const SizedBox(height: 10),
                      Text('Generating image...', style: TextStyle(color: textColor.withValues(alpha: 0.6), fontSize: 12, fontStyle: FontStyle.italic)),
                      if (onRegenerate != null) ...[
                        const SizedBox(height: 8),
                        GestureDetector(
                          onTap: onRegenerate,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                            ),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.stop, size: 12, color: textColor.withValues(alpha: 0.7)),
                              const SizedBox(width: 4),
                              Text('Stop', style: TextStyle(fontSize: 11, color: textColor.withValues(alpha: 0.7), fontWeight: FontWeight.w500)),
                            ]),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            if (data?.caption != null && data!.caption.isNotEmpty) _buildCaption(data.caption),
          ],
        ),
      );
    }
    if (span is _ImgErrorSpan) {
      String errorMsg = 'Unknown error';
      try {
        final json = jsonDecode(span.data) as Map<String, dynamic>;
        errorMsg = json['error'] as String? ?? 'Unknown error';
      } catch (_) {}
      return _buildFrame(
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.red.withValues(alpha: 0.3))),
          child: Row(children: [
            Icon(Icons.error_outline, size: 16, color: Colors.red.withValues(alpha: 0.7)),
            const SizedBox(width: 6),
            Flexible(child: Text('Image gen error: $errorMsg', style: const TextStyle(fontSize: 12, color: Colors.red))),
            if (onRegenerate != null) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onRegenerate,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.refresh, size: 12, color: Colors.red),
                    SizedBox(width: 4),
                    Text('Retry', style: TextStyle(fontSize: 11, color: Colors.red, fontWeight: FontWeight.w600)),
                  ]),
                ),
              ),
            ],
          ]),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  static _ParsedDecoration? _parseCssDecoration(String css) {
    final props = <String, String>{};
    for (final part in css.split(';')) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) continue;
      final colon = trimmed.indexOf(':');
      if (colon < 0) continue;
      props[trimmed.substring(0, colon).trim().toLowerCase()] = trimmed.substring(colon + 1).trim();
    }

    Color? bgColor;
    if (props.containsKey('background')) {
      bgColor = _parseCssColor(props['background']!);
    } else if (props.containsKey('background-color')) {
      bgColor = _parseCssColor(props['background-color']!);
    }

    Border? border;
    if (props.containsKey('border')) {
      border = _parseCssBorder(props['border']!);
    }

    BorderRadius? borderRadius;
    if (props.containsKey('border-radius')) {
      borderRadius = _parseCssBorderRadius(props['border-radius']!);
    }

    List<BoxShadow>? boxShadow;
    if (props.containsKey('box-shadow')) {
      boxShadow = _parseCssBoxShadow(props['box-shadow']!);
    }

    EdgeInsets? padding;
    if (props.containsKey('padding')) {
      padding = _parseCssEdgeInsets(props['padding']!);
    }

    EdgeInsets? margin;
    if (props.containsKey('margin')) {
      margin = _parseCssEdgeInsets(props['margin']!);
    }

    double? maxWidth;
    if (props.containsKey('max-width')) {
      maxWidth = _parseCssPx(props['max-width']!);
    }

    if (bgColor == null && border == null && borderRadius == null && boxShadow == null && padding == null && maxWidth == null) {
      return null;
    }

    return _ParsedDecoration(
      color: bgColor,
      border: border,
      borderRadius: borderRadius,
      boxShadow: boxShadow,
      padding: padding,
      margin: margin,
      maxWidth: maxWidth,
    );
  }

  static Color? _parseCssColor(String value) {
    final v = value.trim();
    final rgbaMatch = RegExp(r'rgba?\(\s*([\d.]+)\s*,\s*([\d.]+)\s*,\s*([\d.]+)\s*(?:,\s*([\d.]+))?\s*\)', caseSensitive: false).firstMatch(v);
    if (rgbaMatch != null) {
      final r = (double.tryParse(rgbaMatch[1]!) ?? 0).round().clamp(0, 255);
      final g = (double.tryParse(rgbaMatch[2]!) ?? 0).round().clamp(0, 255);
      final b = (double.tryParse(rgbaMatch[3]!) ?? 0).round().clamp(0, 255);
      final a = (double.tryParse(rgbaMatch[4] ?? '1') ?? 1).clamp(0.0, 1.0);
      return Color.fromARGB((a * 255).round(), r, g, b);
    }
    final hexMatch = RegExp(r'^#([0-9a-f]{3,8})$', caseSensitive: false).firstMatch(v);
    if (hexMatch != null) {
      final hex = hexMatch[1]!;
      if (hex.length == 3) {
        return Color(int.parse('FF${hex[0]}${hex[0]}${hex[1]}${hex[1]}${hex[2]}${hex[2]}', radix: 16));
      } else if (hex.length == 6) {
        return Color(int.parse('FF$hex', radix: 16));
      } else if (hex.length == 8) {
        return Color(int.parse(hex, radix: 16));
      }
    }
    return null;
  }

  static Border? _parseCssBorder(String value) {
    final parts = value.trim().split(RegExp(r'\s+'));
    if (parts.length < 3) return null;
    final width = _parseCssPx(parts[0]) ?? 1.0;
    final color = _parseCssColor(parts.sublist(2).join(' '));
    if (color == null) return null;
    return Border.all(color: color, width: width);
  }

  static BorderRadius? _parseCssBorderRadius(String value) {
    final radius = _parseCssPx(value.trim());
    if (radius == null) return null;
    return BorderRadius.circular(radius);
  }

  static List<BoxShadow>? _parseCssBoxShadow(String value) {
    final shadows = <BoxShadow>[];
    for (final part in value.split(',')) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) continue;
      final tokens = trimmed.split(RegExp(r'\s+'));
      if (tokens.length < 3) continue;

      double? dx, dy, blur, spread;
      Color? color;
      int numIndex = 0;
      final nums = <double>[];

      for (final token in tokens) {
        final n = double.tryParse(token);
        if (n != null) {
          nums.add(n);
        } else {
          color = _parseCssColor(token);
        }
      }

      if (nums.length >= 2) {
        dx = nums[0];
        dy = nums[1];
        if (nums.length >= 3) blur = nums[2];
        if (nums.length >= 4) spread = nums[3];
      }
      if (color == null && tokens.length > 3) {
        color = _parseCssColor(tokens.sublist(nums.length).join(' '));
      }

      shadows.add(BoxShadow(
        color: color ?? Colors.black,
        blurRadius: blur ?? 0,
        offset: Offset(dx ?? 0, dy ?? 0),
        spreadRadius: spread ?? 0,
      ));
    }
    return shadows.isEmpty ? null : shadows;
  }

  static EdgeInsets? _parseCssEdgeInsets(String value) {
    final parts = value.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return null;
    final values = parts.map((p) => _parseCssPx(p) ?? 0.0).toList();
    if (values.length == 1) return EdgeInsets.all(values[0]);
    if (values.length == 2) return EdgeInsets.symmetric(vertical: values[0], horizontal: values[1]);
    if (values.length == 4) return EdgeInsets.fromLTRB(values[3], values[0], values[1], values[2]);
    return null;
  }

  static double? _parseCssPx(String value) {
    final v = value.trim();
    if (v.endsWith('px')) return double.tryParse(v.substring(0, v.length - 2));
    return double.tryParse(v);
  }
}

class _ParsedDecoration {
  final Color? color;
  final Border? border;
  final BorderRadius? borderRadius;
  final List<BoxShadow>? boxShadow;
  final EdgeInsets? padding;
  final EdgeInsets? margin;
  final double? maxWidth;

  _ParsedDecoration({
    this.color,
    this.border,
    this.borderRadius,
    this.boxShadow,
    this.padding,
    this.margin,
    this.maxWidth,
  });
}

class _InstructionData {
  final String style;
  final String prompt;
  final String caption;
  final String aspectRatio;
  final String imageSize;
  final String containerStyle;

  _InstructionData({
    required this.style,
    required this.prompt,
    required this.caption,
    required this.aspectRatio,
    required this.imageSize,
    required this.containerStyle,
  });
}

final _kInlineComponents = [
  HtmlColorMd(),
  GlowTextMd(),
  ColorGlowTextMd(),
  GradientTextMd(),
  BackgroundTextMd(),
  MarkMd(textColor: const Color(0xFFB39DDB)),
  ColoredBoldMd(color: const Color(0xFFB39DDB)),
  ColoredUnderscoreBoldMd(color: const Color(0xFFB39DDB)),
  ColoredItalicMd(color: const Color(0xFFB39DDB)),
  ColoredUnderscoreItalicMd(color: const Color(0xFFB39DDB)),
];

sealed class _ContentSpan {}

class _TextSpan extends _ContentSpan {
  final String text;
  _TextSpan(this.text);
}

class _ImgGenSpan extends _ContentSpan {
  final String instruction;
  _ImgGenSpan(this.instruction);
}

class _ImgResultSpan extends _ContentSpan {
  final String path;
  _ImgResultSpan(this.path);
}

class _ImgErrorSpan extends _ContentSpan {
  final String data;
  _ImgErrorSpan(this.data);
}
