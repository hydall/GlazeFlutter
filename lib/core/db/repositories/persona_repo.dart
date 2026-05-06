import 'package:drift/drift.dart';

import '../app_db.dart';
import '../../models/persona.dart';

class PersonaRepo {
  final AppDatabase _db;
  PersonaRepo(this._db);

  Future<List<Persona>> getAll() async {
    final rows = await (_db.select(_db.personas)
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
    return rows.map(_toModel).toList();
  }

  Future<Persona?> getById(String id) async {
    final row = await (_db.select(_db.personas)
          ..where((t) => t.personaId.equals(id)))
        .getSingleOrNull();
    return row != null ? _toModel(row) : null;
  }

  Future<void> put(Persona persona) async {
    await _db.into(_db.personas).insertOnConflictUpdate(_toCompanion(persona));
  }

  Future<void> delete(String id) async {
    await (_db.delete(_db.personas)..where((t) => t.personaId.equals(id))).go();
  }

  Persona _toModel(PersonaRow c) => Persona(
        id: c.personaId,
        name: c.name,
        prompt: c.prompt,
        avatarPath: c.avatarPath,
        createdAt: c.createdAt,
      );

  PersonasCompanion _toCompanion(Persona m) => PersonasCompanion(
        personaId: Value(m.id),
        name: Value(m.name),
        prompt: Value(m.prompt),
        avatarPath: Value(m.avatarPath),
        createdAt: Value(m.createdAt),
      );
}
