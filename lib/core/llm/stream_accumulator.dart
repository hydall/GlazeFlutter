class StreamAccumulator {
  final String? tagStart;
  final String? tagEnd;
  final bool hasInlineTags;
  final String? headerModel;
  final String? headerInline;

  String _raw = '';
  String _text = '';
  String _externalReasoning = '';
  String _inlineReasoning = '';
  bool _hasExternalReasoning = false;
  bool _splitDone = false;

  StreamAccumulator({
    this.tagStart,
    this.tagEnd,
    this.hasInlineTags = false,
    this.headerModel,
    this.headerInline,
  });

  String _normalizeThinkTagVariants(String input) {
    if (!hasInlineTags || tagStart == null || tagEnd == null) return input;

    final startLower = tagStart!.toLowerCase();
    final endLower = tagEnd!.toLowerCase();

    final configuredIsThinking = startLower.startsWith('<thinking');
    final configuredIsThink = startLower.startsWith('<think') && !configuredIsThinking;

    final configuredEndIsThinking = endLower.startsWith('</thinking');
    final configuredEndIsThink = endLower.startsWith('</think') && !configuredEndIsThinking;

    // Support models that output <thinking>...</thinking> but our parser expects <think>...</think>.
    if (configuredIsThink && configuredEndIsThink) {
      input = input.replaceAll(
        RegExp(r'<thinking\b[^>]*>', caseSensitive: false),
        tagStart!,
      );
      input = input.replaceAll(
        RegExp(r'</thinking\b[^>]*>', caseSensitive: false),
        tagEnd!,
      );
    } else if (configuredIsThinking && configuredEndIsThinking) {
      input = input.replaceAll(
        RegExp(r'<think\b[^>]*>', caseSensitive: false),
        tagStart!,
      );
      input = input.replaceAll(
        RegExp(r'</think\b[^>]*>', caseSensitive: false),
        tagEnd!,
      );
    }

    return input;
  }

  void consumeDelta(String delta, {String? reasoningDelta}) {
    if (reasoningDelta != null && reasoningDelta.isNotEmpty) {
      _externalReasoning += reasoningDelta;
      _hasExternalReasoning = true;
    }

    if (hasInlineTags && tagStart != null && tagEnd != null) {
      _raw += delta;
      _resplit();
    } else {
      _text += delta;
    }
  }

  void _resplit() {
    _raw = _normalizeThinkTagVariants(_raw);

    final startIdx = _raw.indexOf(tagStart!);
    if (startIdx == -1) {
      _text = _raw;
      _inlineReasoning = '';
      _splitDone = false;
      return;
    }

    final endIdx = _raw.indexOf(tagEnd!, startIdx + tagStart!.length);
    if (endIdx == -1) {
      _text = _raw.substring(0, startIdx).trimLeft();
      _inlineReasoning = _raw.substring(startIdx + tagStart!.length);
      _splitDone = false;
      return;
    }

    _inlineReasoning = _raw.substring(startIdx + tagStart!.length, endIdx);
    _text = (_raw.substring(0, startIdx) + _raw.substring(endIdx + tagEnd!.length)).trimLeft();
    _splitDone = true;
  }

  void flush() {}

  String _combineReasoning() {
    final external = _externalReasoning.trim();
    final inline = _inlineReasoning.trim();

    if (external.isNotEmpty && inline.isNotEmpty) {
      final hModel = headerModel ?? '';
      final hInline = headerInline ?? '';
      final prefix = hModel.isNotEmpty ? '$hModel\n' : '';
      final midfix = hInline.isNotEmpty ? '$hInline\n' : '';
      return '$prefix$external\n\n---\n\n$midfix$inline';
    }
    return inline.isNotEmpty ? inline : external;
  }

  String get text => _text;
  String get reasoning => _combineReasoning();
  bool get hasExternalReasoning => _hasExternalReasoning;
  bool get splitDone => _splitDone;

  String get raw => _raw;

  void reset() {
    _raw = '';
    _text = '';
    _externalReasoning = '';
    _inlineReasoning = '';
    _hasExternalReasoning = false;
    _splitDone = false;
  }
}