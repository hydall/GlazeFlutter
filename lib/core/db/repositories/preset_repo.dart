import 'dart:convert';

import 'package:drift/drift.dart';

import '../app_db.dart';
import '../../models/preset.dart';

class PresetRepo {
  final AppDatabase _db;
  PresetRepo(this._db);

  Future<List<Preset>> getAll() async {
    final rows = await _db.select(_db.presets).get();
    return rows.map(_toModel).toList();
  }

  Future<Preset?> getById(String id) async {
    final row = await (_db.select(_db.presets)
          ..where((t) => t.presetId.equals(id)))
        .getSingleOrNull();
    return row != null ? _toModel(row) : null;
  }

  Future<void> put(Preset preset) async {
    await _db.into(_db.presets).insertOnConflictUpdate(_toCompanion(preset));
  }

  Future<void> delete(String id) async {
    await (_db.delete(_db.presets)..where((t) => t.presetId.equals(id))).go();
  }

  Preset _toModel(PresetRow c) =>
      Preset.fromJson(jsonDecode(c.dataJson) as Map<String, dynamic>);

  PresetsCompanion _toCompanion(Preset m) => PresetsCompanion(
        presetId: Value(m.id),
        name: Value(m.name),
        dataJson: Value(jsonEncode(m.toJson())),
      );
}
