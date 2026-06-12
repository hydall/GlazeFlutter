import 'package:drift/drift.dart';

import '../app_db.dart';
import '../tables.dart';
import '../../utils/time_helpers.dart';

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
    bool? enabled,
    String? prompt,
  }) async {
    final existing = await get(sessionId);
    await into(chatSummaries).insertOnConflictUpdate(
      ChatSummariesCompanion.insert(
        sessionId: sessionId,
        content: content,
        enabled: Value(enabled ?? existing?.enabled ?? true),
        messageCount: Value(messageCount),
        prompt: Value(prompt ?? existing?.prompt),
        updatedAt: Value(currentTimestampSeconds()),
      ),
    );
  }

  Future<void> setEnabled({
    required String sessionId,
    required bool enabled,
  }) async {
    final existing = await get(sessionId);
    await into(chatSummaries).insertOnConflictUpdate(
      ChatSummariesCompanion.insert(
        sessionId: sessionId,
        content: existing?.content ?? '',
        enabled: Value(enabled),
        messageCount: Value(existing?.messageCount ?? 0),
        prompt: Value(existing?.prompt),
        updatedAt: Value(currentTimestampSeconds()),
      ),
    );
  }

  Future<void> deleteBySessionId(String sessionId) {
    return (delete(chatSummaries)..where((t) => t.sessionId.equals(sessionId)))
        .go()
        .then((_) {});
  }
}
