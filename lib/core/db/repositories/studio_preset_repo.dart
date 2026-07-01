import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../features/cloud_sync/sync_repo_interfaces.dart';
import '../../models/studio_config.dart';
import '../app_db.dart';

class StudioPresetRepo implements SyncStudioPresetStore {
  final AppDatabase db;

  const StudioPresetRepo(this.db);

  @override
  Future<StudioPreset?> getById(String id) async {
    final row = await (db.select(
      db.studioPresetRows,
    )..where((t) => t.presetId.equals(id))).getSingleOrNull();
    if (row == null) return null;
    return _rowToModel(row);
  }

  Future<StudioPreset?> getDefault() => getById('default');

  @override
  Future<List<StudioPreset>> getAll() async {
    final rows = await db.select(db.studioPresetRows).get();
    return rows.map(_rowToModel).toList();
  }

  @override
  Future<void> put(StudioPreset preset) => upsert(preset);

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

  @override
  Future<void> delete(String id) => deleteById(id);

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
