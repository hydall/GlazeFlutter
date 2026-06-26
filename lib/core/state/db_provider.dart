import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/app_db.dart';
import '../db/repositories/character_repo.dart';
import '../db/repositories/chat_repo.dart';
import '../db/repositories/preset_repo.dart';
import '../models/preset.dart';
import '../db/repositories/api_config_repo.dart';
import '../db/repositories/persona_repo.dart';
import '../db/repositories/lorebook_repo.dart';
import '../db/repositories/embedding_repo.dart';
import '../db/repositories/summary_repo.dart';
import '../db/repositories/memory_book_repo.dart';
import '../db/repositories/pipeline_settings_repo.dart';
import '../db/repositories/memory_catalog_repo.dart';
import '../db/repositories/memory_entity_repo.dart';
import '../db/repositories/memory_salience_repo.dart';
import '../db/repositories/memory_cadence_repo.dart';
import '../db/repositories/memory_consolidation_repo.dart';
import '../db/repositories/studio_config_repo.dart';
import '../db/repositories/tracker_repo.dart';
import '../db/repositories/extension_presets_repository.dart';
import '../db/repositories/info_blocks_repository.dart';
import '../models/memory_book.dart';
import '../models/pipeline_settings.dart';
import '../services/character_importer.dart';
import '../services/image_storage_service.dart';
import '../services/migration_service.dart';

final appDbProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final imageStorageProvider = FutureProvider<ImageStorageService>((ref) async {
  return await ImageStorageService.create();
});

final characterImporterProvider = FutureProvider<CharacterImporter>((
  ref,
) async {
  final imageStorage = await ref.watch(imageStorageProvider.future);
  return CharacterImporter(imageStorage);
});

final migrationServiceProvider = FutureProvider<MigrationService>((ref) async {
  final imageStorage = await ref.watch(imageStorageProvider.future);
  return MigrationService(
    charRepo: ref.watch(characterRepoProvider),
    chatRepo: ref.watch(chatRepoProvider),
    personaRepo: ref.watch(personaRepoProvider),
    presetRepo: ref.watch(presetRepoProvider),
    apiRepo: ref.watch(apiConfigRepoProvider),
    imageStorage: imageStorage,
  );
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

final presetsListProvider = FutureProvider<List<Preset>>((ref) {
  return ref.watch(presetRepoProvider).getAll();
});

final apiConfigRepoProvider = Provider<ApiConfigRepo>((ref) {
  return ApiConfigRepo(ref.watch(appDbProvider));
});

final personaRepoProvider = Provider<PersonaRepo>((ref) {
  return PersonaRepo(ref.watch(appDbProvider));
});

final lorebookRepoProvider = Provider<LorebookRepo>((ref) {
  return LorebookRepo(ref.watch(appDbProvider));
});

final embeddingRepoProvider = Provider<EmbeddingRepo>((ref) {
  return EmbeddingRepo(ref.watch(appDbProvider));
});

final summaryRepoProvider = Provider<SummaryRepo>((ref) {
  return SummaryRepo(ref.watch(appDbProvider));
});

final memoryBookRepoProvider = Provider<MemoryBookRepo>((ref) {
  return MemoryBookRepo(ref.watch(appDbProvider), ref);
});

final pipelineSettingsRepoProvider = Provider<PipelineSettingsRepo>((ref) {
  return PipelineSettingsRepo(ref.watch(appDbProvider), ref);
});

final memoryCatalogRepoProvider = Provider<MemoryCatalogRepo>((ref) {
  return MemoryCatalogRepo(ref.watch(appDbProvider));
});

final memoryEntityRepoProvider = Provider<MemoryEntityRepo>((ref) {
  return MemoryEntityRepo(ref.watch(appDbProvider));
});

final memorySalienceRepoProvider = Provider<MemorySalienceRepo>((ref) {
  return MemorySalienceRepo(ref.watch(appDbProvider));
});

final memoryCadenceRepoProvider = Provider<MemoryCadenceRepo>((ref) {
  return MemoryCadenceRepo(ref.watch(appDbProvider));
});

final memoryConsolidationRepoProvider = Provider<MemoryConsolidationRepo>((
  ref,
) {
  return MemoryConsolidationRepo(ref.watch(appDbProvider));
});

final studioConfigRepoProvider = Provider<StudioConfigRepo>((ref) {
  return StudioConfigRepo(ref.watch(appDbProvider));
});

final trackerRepoProvider = Provider<TrackerRepo>((ref) {
  return TrackerRepo(ref.watch(appDbProvider));
});

final memoryBookProvider = FutureProvider.family<MemoryBook?, String>((
  ref,
  sessionId,
) async {
  final repo = ref.watch(memoryBookRepoProvider);
  return repo.getBySessionId(sessionId);
});

/// Per-session [PipelineSettings] provider. The repo seeds a row from
/// [PipelineGlobalSettings] defaults on first access; afterwards the row is
/// the source of truth and per-session edits override the global defaults.
final pipelineSettingsProvider =
    FutureProvider.family<PipelineSettings, String>((ref, sessionId) async {
  final repo = ref.watch(pipelineSettingsRepoProvider);
  return repo.ensureForSession(sessionId);
});

final extensionPresetsRepoProvider = Provider<ExtensionPresetsRepository>((
  ref,
) {
  return ExtensionPresetsRepository(ref.watch(appDbProvider));
});

final infoBlocksRepoProvider = Provider<InfoBlocksRepository>((ref) {
  return InfoBlocksRepository(ref.watch(appDbProvider));
});
