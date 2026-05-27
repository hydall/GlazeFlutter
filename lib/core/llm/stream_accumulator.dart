class StreamAccumulator {
  final String? tagStart;
  final String? tagEnd;
  final bool hasInlineTags;

  String _text = '';
  String _reasoning = '';
  bool _inReasoningBlock = false;
  String _pending = '';
  // True once we've received at least one non-empty reasoningDelta via the
  // dedicated API field.  When this is set we know the model is delivering
  // reasoning out-of-band, so any tagEnd that leaks into the content stream
  // should be stripped rather than parsed as inline.
  bool _hasExternalReasoning = false;

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
      if (delta.isNotEmpty) {
        _pending += delta;
        _processPending();
      }
    } else {
      _text += delta;
    }
  }

  void _processPending() {
    var input = _pending;
    input = _normalizeThinkTagVariants(input);
    var textPart = '';

    while (input.isNotEmpty) {
      if (_inReasoningBlock) {
        final tag = tagEnd!;
        final endIdx = input.indexOf(tag);
        if (endIdx == -1) {
          // Check if input ends with a partial tagEnd prefix
          final partial = _partialSuffixLength(input, tag);
          if (partial > 0) {
            _reasoning += input.substring(0, input.length - partial);
            _pending = input.substring(input.length - partial);
          } else {
            _reasoning += input;
            _pending = '';
          }
          _text += textPart;
          return;
        }
        _reasoning += input.substring(0, endIdx);
        input = input.substring(endIdx + tag.length);
        _inReasoningBlock = false;
      } else {
        if (_hasExternalReasoning && tagEnd != null) {
          final endIdx = input.indexOf(tagEnd!);
          if (endIdx != -1) {
            textPart += input.substring(0, endIdx);
            input = input.substring(endIdx + tagEnd!.length);
            continue;
          }
          final partial = _partialSuffixLength(input, tagEnd!);
          if (partial > 0) {
            textPart += input.substring(0, input.length - partial);
            _pending = input.substring(input.length - partial);
          } else {
            textPart += input;
            _pending = '';
          }
          break;
        }
        final tag = tagStart!;
        final startIdx = input.indexOf(tag);
        if (startIdx == -1) {
          final partial = _partialSuffixLength(input, tag);
          if (partial > 0) {
            textPart += input.substring(0, input.length - partial);
            _pending = input.substring(input.length - partial);
          } else {
            textPart += input;
            _pending = '';
          }
          break;
        }
        textPart += input.substring(0, startIdx);
        input = input.substring(startIdx + tag.length);
        _inReasoningBlock = true;
      }
    }

    _text += textPart;
  }

  /// Returns the length of the longest suffix of [input] that is a prefix of [tag].
  int _partialSuffixLength(String input, String tag) {
    for (var len = tag.length - 1; len > 0; len--) {
      if (input.endsWith(tag.substring(0, len))) return len;
    }
    return 0;
  }

  String get text => _text;
  String get reasoning => _reasoning;
  bool get isInReasoningBlock => _inReasoningBlock;

  bool get hasExternalReasoning => _hasExternalReasoning;

  void reset() {
    _text = '';
    _reasoning = '';
    _inReasoningBlock = false;
    _pending = '';
    _hasExternalReasoning = false;
  }

  void flush() {
    if (_pending.isEmpty) return;
    if (_inReasoningBlock) {
      _reasoning += _pending;
    } else {
      _text += _pending;
    }
    _pending = '';
  }
}
