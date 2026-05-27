import 'dart:convert';

import 'package:drift/drift.dart';

import '../app_db.dart';
import '../tables.dart';
import '../../llm/vector_math.dart';
import '../../utils/time_helpers.dart';
import '../../../features/cloud_sync/sync_repo_interfaces.dart';

part 'embedding_repo.g.dart';

@DriftAccessor(tables: [Embeddings])
class EmbeddingRepo extends DatabaseAccessor<AppDatabase>
    with _$EmbeddingRepoMixin
    implements SyncEmbeddingStore {
  EmbeddingRepo(super.db);

  Future<EmbeddingRow?> getByEntryId(String entryId) {
    return (select(embeddings)..where((e) => e.entryId.equals(entryId))).getSingleOrNull();
  }

  Future<List<EmbeddingRow>> getAll() {
    return select(embeddings).get();
  }

  Future<List<EmbeddingRow>> getBySourceType(String sourceType) {
    return (select(embeddings)..where((e) => e.sourceType.equals(sourceType))).get();
  }

  Future<void> put(EmbeddingsCompanion entry) {
    return into(embeddings).insertOnConflictUpdate(entry);
  }

  Future<void> deleteByEntryId(String entryId) {
    return (delete(embeddings)..where((e) => e.entryId.equals(entryId))).go();
  }

  Future<void> deleteBySourceType(String sourceType) {
    return (delete(embeddings)..where((e) => e.sourceType.equals(sourceType))).go();
  }

  Future<void> deleteBySourceId(String sourceId) {
    return (delete(embeddings)..where((e) => e.sourceId.equals(sourceId))).go();
  }

  Future<void> putEmbeddingVector({
    required String entryId,
    required String sourceType,
    String? sourceId,
    required List<List<double>> vectors,
    required String textHash,
    List<String>? retrievalHints,
  }) async {
    final vectorsBlob = vectorListToBytes(vectors);
    final hintsJson = retrievalHints != null ? jsonEncode(retrievalHints) : null;

    await put(EmbeddingsCompanion.insert(
      entryId: entryId,
      sourceType: Value(sourceType),
      sourceId: Value(sourceId),
      vectorsBlob: Value(vectorsBlob),
      textHash: Value(textHash),
      retrievalHintsJson: Value(hintsJson),
      errorJson: const Value(null),
      updatedAt: Value(currentTimestampSeconds()),
    ));
  }

  Future<void> putEmbeddingError({
    required String entryId,
    required String sourceType,
    String? sourceId,
    required String textHash,
    required Map<String, dynamic> error,
    List<String>? retrievalHints,
  }) async {
    final hintsJson = retrievalHints != null ? jsonEncode(retrievalHints) : null;

    await put(EmbeddingsCompanion.insert(
      entryId: entryId,
      sourceType: Value(sourceType),
      sourceId: Value(sourceId),
      vectorsBlob: const Value(null),
      textHash: Value(textHash),
      retrievalHintsJson: Value(hintsJson),
      errorJson: Value(jsonEncode(error)),
      updatedAt: Value(currentTimestampSeconds()),
    ));
  }

  List<List<double>>? decodeVectors(EmbeddingRow row) {
    if (row.vectorsBlob == null) return null;
    return bytesToVectorList(row.vectorsBlob!);
  }

  bool hasUsableVectors(EmbeddingRow row) {
    final blob = row.vectorsBlob;
    return blob != null && blob.isNotEmpty;
  }

  List<String>? decodeHints(EmbeddingRow row) {
    if (row.retrievalHintsJson == null) return null;
    try {
      return (jsonDecode(row.retrievalHintsJson!) as List).cast<String>();
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic>? decodeError(EmbeddingRow row) {
    if (row.errorJson == null) return null;
    try {
      return jsonDecode(row.errorJson!) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}
