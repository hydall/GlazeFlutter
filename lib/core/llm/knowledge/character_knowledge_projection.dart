import '../../models/character_knowledge_fact.dart';

/// Renders scoped, committed character deltas as a separate prompt layer.
///
/// This deliberately does not merge facts into a character card: a fact about
/// Lucy's relationship with Danvi must not silently become a global personality
/// rewrite. The model gets the card normally, then this bounded higher-priority
/// delta for the relevant relationship/subject only.
String? compileCharacterKnowledgeProjection(
  List<CharacterKnowledgeFact> facts, {
  String latestUserText = '',
  String latestAssistantText = '',
  int maxFacts = 8,
}) {
  if (facts.isEmpty || maxFacts <= 0) return null;

  final context = '$latestUserText\n$latestAssistantText'.toLowerCase();
  bool relevant(CharacterKnowledgeFact fact) {
    if (context.trim().isEmpty) return true;
    final terms =
        <String>{
              fact.subjectName,
              ...fact.entities.where(
                (entity) =>
                    entity.toLowerCase() != fact.knowerName.toLowerCase(),
              ),
              ...fact.topics,
            }
            .map((term) => term.trim().toLowerCase())
            .where((term) => term.length >= 3);
    return terms.any(context.contains);
  }

  final candidates = facts.where(relevant).toList()
    ..sort((left, right) {
      final importance = right.importance.compareTo(left.importance);
      return importance != 0
          ? importance
          : right.updatedAt.compareTo(left.updatedAt);
    });
  if (candidates.isEmpty) return null;

  final lines = <String>[];
  for (final fact in candidates.take(maxFacts)) {
    final scope = fact.scopeKey.isNotEmpty
        ? fact.scopeKey
        : '${fact.factClass.wireName}:${fact.subjectKey}';
    final subject = fact.subjectName.isNotEmpty
        ? fact.subjectName
        : fact.subjectKey;
    final knower = fact.knowerName.isNotEmpty
        ? fact.knowerName
        : fact.knowerKey;
    lines.add(
      '- [$scope] $knower ${fact.predicate} $subject: ${fact.object} '
      '(${fact.epistemicState.wireName}).',
    );
  }

  return '''<current_character_state>
These are committed, session-scoped changes. They take priority over the base card ONLY within their stated scope; do not generalize them to other people, scenes, or traits. Do not mention this block.
${lines.join('\n')}
</current_character_state>''';
}
