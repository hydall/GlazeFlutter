import 'package:isar/isar.dart';
import '../collections.dart';
import '../../models/api_config.dart';

class ApiConfigRepo {
  final Isar _db;
  ApiConfigRepo(this._db);

  Future<List<ApiConfig>> getAll() async {
    final items = await _db.apiConfigCollections.where().findAll();
    return items.map(_toModel).toList();
  }

  Future<ApiConfig?> getById(String id) async {
    final c =
        await _db.apiConfigCollections.where().configIdEqualTo(id).findFirst();
    return c != null ? _toModel(c) : null;
  }

  Future<void> put(ApiConfig config) async {
    await _db.writeTxn(() async {
      await _db.apiConfigCollections.put(_toCollection(config));
    });
  }

  Future<void> delete(String id) async {
    await _db.writeTxn(() async {
      await _db.apiConfigCollections.where().configIdEqualTo(id).deleteAll();
    });
  }

  ApiConfig _toModel(ApiConfigCollection c) => ApiConfig(
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

  ApiConfigCollection _toCollection(ApiConfig m) => ApiConfigCollection()
    ..configId = m.id
    ..name = m.name
    ..providerId = m.providerId
    ..endpoint = m.endpoint
    ..apiKey = m.apiKey
    ..model = m.model
    ..maxTokens = m.maxTokens
    ..contextSize = m.contextSize
    ..temperature = m.temperature
    ..topP = m.topP
    ..stream = m.stream
    ..reasoningEffort = m.reasoningEffort
    ..requestReasoning = m.requestReasoning
    ..reasoningTagStart = m.reasoningTagStart
    ..reasoningTagEnd = m.reasoningTagEnd;
}
