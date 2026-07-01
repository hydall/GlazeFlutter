import 'dart:convert';

import 'package:drift/drift.dart';

import '../../models/studio_config.dart';
import '../app_db.dart';

class StudioPresetRepo {
  final AppDatabase db;

  const StudioPresetRepo(this.db);

  Future<StudioPreset?> getById(String id) async {
    final row = await (db.select(
      db.studioPresetRows,
    )..where((t) => t.presetId.equals(id))).getSingleOrNull();
    if (row == null) return null;
    return _rowToModel(row);
  }

  Future<StudioPreset?> getDefault() => getById('default');

  Future<List<StudioPreset>> getAll() async {
    final rows = await db.select(db.studioPresetRows).get();
    return rows.map(_rowToModel).toList();
  }

  Future<void> upsert(StudioPreset preset) async {
    await db.into(db.studioPresetRows).insertOnConflictUpdate(
      StudioPresetRowsCompanion.insert(
        presetId: preset.id,
        name: preset.name,
        blocksJson: Value(jsonEncode(preset.blocks.map((b) => b.toJson()).toList())),
        updatedAt: Value(preset.updatedAt),
      ),
    );
  }

  Future<void> deleteById(String id) async {
    await (db.delete(
      db.studioPresetRows,
    )..where((t) => t.presetId.equals(id))).go();
  }

  StudioPreset _rowToModel(StudioPresetRow row) {
    List<StudioPresetBlock> blocks;
    try {
      final list = jsonDecode(row.blocksJson) as List<dynamic>;
      blocks = list
          .map((e) => StudioPresetBlock.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      blocks = [];
    }
    return StudioPreset(
      id: row.presetId,
      name: row.name,
      blocks: blocks,
      updatedAt: row.updatedAt,
    );
  }
}
