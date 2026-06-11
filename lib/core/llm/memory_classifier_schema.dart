class MemoryClassifierOutput {
  final bool needsMemory;
  final bool reliableCandidateFound;
  final double confidence;
  final List<String> queryExpansion;
  final List<String> reasons;

  const MemoryClassifierOutput({
    required this.needsMemory,
    required this.reliableCandidateFound,
    required this.confidence,
    this.queryExpansion = const [],
    this.reasons = const [],
  });

  factory MemoryClassifierOutput.fromJson(Map<String, dynamic> json) {
    final confidenceRaw = json['confidence'];
    final confidence = confidenceRaw is num ? confidenceRaw.toDouble() : 0.0;
    return MemoryClassifierOutput(
      needsMemory: json['needsMemory'] == true,
      reliableCandidateFound: json['reliableCandidateFound'] == true,
      confidence: confidence.clamp(0.0, 1.0),
      queryExpansion: _stringList(json['queryExpansion']),
      reasons: _stringList(json['reasons']),
    );
  }

  Map<String, dynamic> toJson() => {
    'needsMemory': needsMemory,
    'reliableCandidateFound': reliableCandidateFound,
    'confidence': confidence,
    'queryExpansion': queryExpansion,
    'reasons': reasons,
  };

  static List<String> _stringList(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<String>()
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
  }
}
