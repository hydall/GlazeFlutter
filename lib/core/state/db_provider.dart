import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar/isar.dart';
import '../db/app_db.dart';
import '../db/repositories/character_repo.dart';
import '../db/repositories/chat_repo.dart';
import '../db/repositories/preset_repo.dart';
import '../db/repositories/api_config_repo.dart';
import '../db/repositories/persona_repo.dart';

final isarProvider = FutureProvider<Isar>((ref) => AppDb.instance);

final characterRepoProvider = FutureProvider<CharacterRepo>((ref) async {
  final isar = await ref.watch(isarProvider.future);
  return CharacterRepo(isar);
});

final chatRepoProvider = FutureProvider<ChatRepo>((ref) async {
  final isar = await ref.watch(isarProvider.future);
  return ChatRepo(isar);
});

final presetRepoProvider = FutureProvider<PresetRepo>((ref) async {
  final isar = await ref.watch(isarProvider.future);
  return PresetRepo(isar);
});

final apiConfigRepoProvider = FutureProvider<ApiConfigRepo>((ref) async {
  final isar = await ref.watch(isarProvider.future);
  return ApiConfigRepo(isar);
});

final personaRepoProvider = FutureProvider<PersonaRepo>((ref) async {
  final isar = await ref.watch(isarProvider.future);
  return PersonaRepo(isar);
});
