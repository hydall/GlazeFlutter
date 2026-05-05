import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import 'collections.dart';

class AppDb {
  static Isar? _instance;

  static Future<Isar> get instance async {
    if (_instance != null && _instance!.isOpen) return _instance!;
    _instance = await _open();
    return _instance!;
  }

  static Future<Isar> _open() async {
    final dir = await getApplicationDocumentsDirectory();
    return await Isar.open(
      [
        CharacterCollectionSchema,
        ChatSessionCollectionSchema,
        PresetCollectionSchema,
        ApiConfigCollectionSchema,
        PersonaCollectionSchema,
      ],
      directory: dir.path,
      inspector: true,
    );
  }
}
