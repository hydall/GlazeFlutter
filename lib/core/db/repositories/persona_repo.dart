import 'package:isar/isar.dart';
import '../collections.dart';
import '../../models/persona.dart';

class PersonaRepo {
  final Isar _db;
  PersonaRepo(this._db);

  Future<List<Persona>> getAll() async {
    final items = await _db.personaCollections.where().findAll();
    return items.map(_toModel).toList();
  }

  Future<Persona?> getById(String id) async {
    final c = await _db.personaCollections
        .where()
        .personaIdEqualTo(id)
        .findFirst();
    return c != null ? _toModel(c) : null;
  }

  Future<void> put(Persona persona) async {
    await _db.writeTxn(() async {
      await _db.personaCollections.put(_toCollection(persona));
    });
  }

  Future<void> delete(String id) async {
    await _db.writeTxn(() async {
      await _db.personaCollections.where().personaIdEqualTo(id).deleteAll();
    });
  }

  Persona _toModel(PersonaCollection c) => Persona(
        id: c.personaId,
        name: c.name,
        prompt: c.prompt,
        avatarPath: c.avatarPath,
      );

  PersonaCollection _toCollection(Persona m) => PersonaCollection()
    ..personaId = m.id
    ..name = m.name
    ..prompt = m.prompt
    ..avatarPath = m.avatarPath;
}
