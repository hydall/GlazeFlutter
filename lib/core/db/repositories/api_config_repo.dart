import 'package:drift/drift.dart';

import '../app_db.dart';
import '../../models/api_config.dart';

class ApiConfigRepo {
  final AppDatabase _db;
  ApiConfigRepo(this._db);

  Future<List<ApiConfig>> getAll() async {
    final rows = await _db.select(_db.apiConfigs).get();
    return rows.map(_toModel).toList();
  }

  Future<ApiConfig?> getById(String id) async {
    final row = await (_db.select(_db.apiConfigs)
          ..where((t) => t.configId.equals(id)))
        .getSingleOrNull();
    return row != null ? _toModel(row) : null;
  }

  Future<void> put(ApiConfig config) async {
    await _db.into(_db.apiConfigs).insertOnConflictUpdate(_toCompanion(config));
  }

  Future<void> delete(String id) async {
    await (_db.delete(_db.apiConfigs)..where((t) => t.configId.equals(id))).go();
  }

  ApiConfig _toModel(ApiConfigRow c) => ApiConfig(
        id: c.configId,
        name: c.name,
        providerId: c.providerId,
        endpoint: c.endpoint ?? '',
        apiKey: c.apiKey ?? '',
        model: c.model ?? '',
        maxTokens: c.maxTokens,
        contextSize: c.contextSize,
        temperature: c.temperature,
        topP: c.topP,
        stream: c.stream,
        reasoningEffort: c.reasoningEffort ?? 'medium',
        requestReasoning: c.requestReasoning,
        reasoningTagStart: c.reasoningTagStart,
        reasoningTagEnd: c.reasoningTagEnd,
      );

  ApiConfigsCompanion _toCompanion(ApiConfig m) => ApiConfigsCompanion(
        configId: Value(m.id),
        name: Value(m.name),
        providerId: Value(m.providerId),
        endpoint: Value(m.endpoint),
        apiKey: Value(m.apiKey),
        model: Value(m.model),
        maxTokens: Value(m.maxTokens),
        contextSize: Value(m.contextSize),
        temperature: Value(m.temperature),
        topP: Value(m.topP),
        stream: Value(m.stream),
        reasoningEffort: Value(m.reasoningEffort),
        requestReasoning: Value(m.requestReasoning),
        reasoningTagStart: Value(m.reasoningTagStart),
        reasoningTagEnd: Value(m.reasoningTagEnd),
      );
}
