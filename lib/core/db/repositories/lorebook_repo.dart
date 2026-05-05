import 'dart:convert';

import 'package:drift/drift.dart';

import '../app_db.dart';
import '../../models/lorebook.dart';

class LorebookRepo {
  final AppDatabase _db;
  LorebookRepo(this._db);

  Future<List<Lorebook>> getAll() async {
    final rows = await _db.select(_db.lorebooks).get();
    return rows.map(_toModel).toList();
  }

  Future<Lorebook?> getById(String id) async {
    final row = await (_db.select(_db.lorebooks)
          ..where((t) => t.lorebookId.equals(id)))
        .getSingleOrNull();
    return row != null ? _toModel(row) : null;
  }

  Future<void> put(Lorebook lorebook) async {
    await _db.into(_db.lorebooks).insertOnConflictUpdate(_toCompanion(lorebook));
  }

  Future<void> delete(String id) async {
    await (_db.delete(_db.lorebooks)..where((t) => t.lorebookId.equals(id))).go();
  }

  Lorebook _toModel(LorebookRow r) => Lorebook(
        id: r.lorebookId,
        name: r.name,
        enabled: r.enabled,
        activationScope: r.activationScope,
        activationTargetId: r.activationTargetId,
        entries: _parseEntries(r.entriesJson),
        updatedAt: r.updatedAt,
      );

  LorebooksCompanion _toCompanion(Lorebook m) => LorebooksCompanion(
        lorebookId: Value(m.id),
        name: Value(m.name),
        enabled: Value(m.enabled),
        activationScope: Value(m.activationScope),
        activationTargetId: Value(m.activationTargetId),
        entriesJson: Value(jsonEncode(m.entries.map((e) => e.toJson()).toList())),
        updatedAt: Value(m.updatedAt),
      );

  List<LorebookEntry> _parseEntries(String json) {
    try {
      final list = jsonDecode(json) as List;
      return list.map((e) => LorebookEntry.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }
}
