class StreamAccumulator {
  final String? tagStart;
  final String? tagEnd;
  final bool hasInlineTags;

  String _raw = '';
  String _text = '';
  String _reasoning = '';
  bool _hasExternalReasoning = false;
  bool _splitDone = false;

  StreamAccumulator({
    this.tagStart,
    this.tagEnd,
    this.hasInlineTags = false,
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
      _reasoning += reasoningDelta;
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
    if (_hasExternalReasoning) {
      var content = _raw;
      if (tagStart != null) content = content.replaceAll(tagStart!, '');
      if (tagEnd != null) content = content.replaceAll(tagEnd!, '');
      _text = content.trimLeft();
      _splitDone = true;
      return;
    }

    final startIdx = _raw.indexOf(tagStart!);
    if (startIdx == -1) {
      _text = _raw;
      _reasoning = '';
      _splitDone = false;
      return;
    }

    final endIdx = _raw.indexOf(tagEnd!, startIdx + tagStart!.length);
    if (endIdx == -1) {
      _text = _raw.substring(0, startIdx).trimLeft();
      _reasoning = _raw.substring(startIdx + tagStart!.length);
      _splitDone = false;
      return;
    }

    _text = (_raw.substring(0, startIdx) + _raw.substring(endIdx + tagEnd!.length)).trimLeft();
    _reasoning = _raw.substring(startIdx + tagStart!.length, endIdx);
    _splitDone = true;
  }

  void flush() {}

  String get text => _text;
  String get reasoning => _reasoning;
  bool get hasExternalReasoning => _hasExternalReasoning;
  bool get splitDone => _splitDone;

  String get raw => _raw;

  void reset() {
    _raw = '';
    _text = '';
    _reasoning = '';
    _hasExternalReasoning = false;
    _splitDone = false;
  }
}