import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/app_db.dart';
import '../db/repositories/character_repo.dart';
import '../db/repositories/chat_repo.dart';
import '../db/repositories/preset_repo.dart';
import '../db/repositories/api_config_repo.dart';
import '../db/repositories/persona_repo.dart';
import '../services/character_importer.dart';
import '../services/image_storage_service.dart';

final appDbProvider = Provider<AppDatabase>((ref) => AppDatabase());

final imageStorageProvider = Provider<ImageStorageService>((ref) {
  return ImageStorageService.create();
});

final characterImporterProvider = Provider<CharacterImporter>((ref) {
  return CharacterImporter(ref.watch(imageStorageProvider));
});

final characterRepoProvider = Provider<CharacterRepo>((ref) {
  return CharacterRepo(ref.watch(appDbProvider));
});

final chatRepoProvider = Provider<ChatRepo>((ref) {
  return ChatRepo(ref.watch(appDbProvider));
});

final presetRepoProvider = Provider<PresetRepo>((ref) {
  return PresetRepo(ref.watch(appDbProvider));
});

final apiConfigRepoProvider = Provider<ApiConfigRepo>((ref) {
  return ApiConfigRepo(ref.watch(appDbProvider));
});

final personaRepoProvider = Provider<PersonaRepo>((ref) {
  return PersonaRepo(ref.watch(appDbProvider));
});
