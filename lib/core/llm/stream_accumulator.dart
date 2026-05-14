class StreamAccumulator {
  final String? tagStart;
  final String? tagEnd;
  final bool hasInlineTags;

  String _text = '';
  String _reasoning = '';
  bool _inReasoningBlock = false;
  String _pending = '';

  StreamAccumulator({
    this.tagStart,
    this.tagEnd,
    this.hasInlineTags = false,
  });

  void consumeDelta(String delta, {String? reasoningDelta}) {
    if (reasoningDelta != null && reasoningDelta.isNotEmpty) {
      _reasoning += reasoningDelta;
    }

    if (hasInlineTags && tagStart != null && tagEnd != null) {
      _pending += delta;
      _processPending();
    } else {
      _text += delta;
    }
  }

  void _processPending() {
    var input = _pending;
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
        final tag = tagStart!;
        final startIdx = input.indexOf(tag);
        if (startIdx == -1) {
          // Check if input ends with a partial tagStart prefix
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

  void reset() {
    _text = '';
    _reasoning = '';
    _inReasoningBlock = false;
    _pending = '';
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
