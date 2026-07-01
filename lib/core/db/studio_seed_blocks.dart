import 'app_db.dart' as db;

/// Public re-export of [db.studioPresetSeedBlocks] for UI screens that need
/// to reset a preset to its default seed data. The function lives in
/// `app_db.dart` as a top-level function but some analyzer configurations
/// misresolve it as an `AppDatabase` method when imported directly from
/// `app_db.dart` (which also defines the `AppDatabase` class and a `part`
/// directive for the Drift-generated file). This indirection avoids that
/// false positive.
List<Map<String, dynamic>> studioPresetSeedBlocks() =>
    db.studioPresetSeedBlocks();
