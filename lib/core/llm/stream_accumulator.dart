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
    var reasoningPart = '';

    while (input.isNotEmpty) {
      if (_inReasoningBlock) {
        final endIdx = input.indexOf(tagEnd!);
        if (endIdx == -1) {
          _reasoning += input;
          _pending = '';
          return;
        }
        _reasoning += input.substring(0, endIdx);
        input = input.substring(endIdx + tagEnd!.length);
        _inReasoningBlock = false;
      } else {
        final startIdx = input.indexOf(tagStart!);
        if (startIdx == -1) {
          textPart += input;
          _pending = '';
          break;
        }
        textPart += input.substring(0, startIdx);
        input = input.substring(startIdx + tagStart!.length);
        _inReasoningBlock = true;
      }
    }

    _text += textPart;
    _reasoning += reasoningPart;
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
}
