import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

import '../../../shared/theme/app_colors.dart';

class ImageContentRenderer extends StatelessWidget {
  final String content;
  final Color textColor;

  const ImageContentRenderer({
    super.key,
    required this.content,
    required this.textColor,
  });

  static final _imgGenRegex = RegExp(r'\[IMG:GEN:(.*?)\]');
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
      children: spans.map((s) => _buildSpanWidget(s)).toList(),
    );
  }

  Widget _buildSpanWidget(_ContentSpan span) {
    if (span is _TextSpan) {
      if (span.text.trim().isEmpty) return const SizedBox.shrink();
      return GptMarkdown(
        span.text,
        style: TextStyle(color: textColor),
      );
    }
    if (span is _ImgResultSpan) {
      final file = File(span.path);
      if (!file.existsSync()) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text('[Image not found]', style: TextStyle(color: textColor.withValues(alpha: 0.5), fontSize: 12, fontStyle: FontStyle.italic)),
        );
      }
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 300),
            child: Image.file(file, fit: BoxFit.contain),
          ),
        ),
      );
    }
    if (span is _ImgGenSpan) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent)),
            const SizedBox(width: 8),
            Flexible(child: Text('Generating image...', style: TextStyle(color: textColor.withValues(alpha: 0.6), fontSize: 12, fontStyle: FontStyle.italic))),
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
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.red.withValues(alpha: 0.3))),
          child: Row(children: [
            Icon(Icons.error_outline, size: 16, color: Colors.red.withValues(alpha: 0.7)),
            const SizedBox(width: 6),
            Flexible(child: Text('Image gen error: $errorMsg', style: const TextStyle(fontSize: 12, color: Colors.red))),
          ]),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

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
