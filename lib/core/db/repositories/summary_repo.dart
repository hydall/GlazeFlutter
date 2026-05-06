import 'package:drift/drift.dart';

import '../app_db.dart';
import '../tables.dart';

part 'summary_repo.g.dart';

@DriftAccessor(tables: [ChatSummaries])
class SummaryRepo extends DatabaseAccessor<AppDatabase>
    with _$SummaryRepoMixin {
  SummaryRepo(super.db);

  Future<ChatSummary?> get(String sessionId) {
    return (select(chatSummaries)..where((t) => t.sessionId.equals(sessionId)))
        .getSingleOrNull();
  }

  Future<void> put({
    required String sessionId,
    required String content,
    required int messageCount,
    String? prompt,
  }) {
    return into(chatSummaries).insertOnConflictUpdate(
      ChatSummariesCompanion.insert(
        sessionId: sessionId,
        content: content,
        messageCount: Value(messageCount),
        prompt: Value(prompt),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch ~/ 1000),
      ),
    );
  }

  Future<void> deleteBySessionId(String sessionId) {
    return (delete(chatSummaries)..where((t) => t.sessionId.equals(sessionId)))
        .go();
  }
}
