import 'dart:convert';
import 'package:isar/isar.dart';
import '../collections.dart';
import '../../models/preset.dart';

class PresetRepo {
  final Isar _db;
  PresetRepo(this._db);

  Future<List<Preset>> getAll() async {
    final items = await _db.presetCollections.where().findAll();
    return items.map(_toModel).toList();
  }

  Future<Preset?> getById(String id) async {
    final c =
        await _db.presetCollections.where().presetIdEqualTo(id).findFirst();
    return c != null ? _toModel(c) : null;
  }

  Future<void> put(Preset preset) async {
    await _db.writeTxn(() async {
      await _db.presetCollections.put(_toCollection(preset));
    });
  }

  Future<void> delete(String id) async {
    await _db.writeTxn(() async {
      await _db.presetCollections.where().presetIdEqualTo(id).deleteAll();
    });
  }

  Preset _toModel(PresetCollection c) =>
      Preset.fromJson(jsonDecode(c.dataJson) as Map<String, dynamic>);

  PresetCollection _toCollection(Preset m) => PresetCollection()
    ..presetId = m.id
    ..name = m.name
    ..dataJson = jsonEncode(m.toJson());
}
