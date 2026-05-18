import 'dart:typed_data';

import '../../core/models/api_config.dart';
import '../../core/models/character.dart';
import '../../core/models/chat_message.dart';
import '../../core/models/lorebook.dart';
import '../../core/models/persona.dart';
import '../../core/models/preset.dart';
import 'sync_models.dart';

abstract class SyncCharacterStore {
  Future<List<Character>> getAll();
  Future<Character?> getById(String id);
  Future<void> put(Character c);
  Future<void> delete(String id);
}

abstract class SyncChatStore {
  Future<List<SessionMetadata>> getAllSessionMetadata();
  Future<ChatSession?> getById(String id);
  Future<void> put(ChatSession s);
  Future<void> delete(String id);
}

abstract class SyncPersonaStore {
  Future<List<Persona>> getAll();
  Future<Persona?> getById(String id);
  Future<void> put(Persona p);
  Future<void> delete(String id);
}

abstract class SyncPresetStore {
  Future<List<Preset>> getAll();
  Future<Preset?> getById(String id);
  Future<void> put(Preset p);
  Future<void> delete(String id);
}

abstract class SyncApiConfigStore {
  Future<List<ApiConfig>> getAll();
  Future<ApiConfig?> getById(String id);
  Future<void> put(ApiConfig c);
  Future<void> delete(String id);
}

abstract class SyncLorebookStore {
  Future<List<Lorebook>> getAll();
  Future<Lorebook?> getById(String id);
  Future<void> put(Lorebook l);
  Future<void> delete(String id);
}

abstract class SyncEmbeddingStore {
  Future<void> deleteBySourceId(String sourceId);
}

abstract class SyncImageStore {
  String? absolutePath(String? relativePath);
  Future<String> saveBytes(
      Uint8List bytes, String subfolder, String filename, String ext);
}

abstract class SyncManifestProvider {
  Future<SyncManifest> buildLocalManifest();
  Future<SyncManifest> readLocalManifest();
  Future<void> writeLocalManifest(SyncManifest manifest);
  Future<void> clearDeleted();
}
