import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/character.dart';
import 'db_provider.dart';

final charactersProvider =
    AsyncNotifierProvider<CharactersNotifier, List<Character>>(
        CharactersNotifier.new);

class CharactersNotifier extends AsyncNotifier<List<Character>> {
  @override
  Future<List<Character>> build() async {
    final repo = await ref.watch(characterRepoProvider.future);
    return repo.getAll();
  }

  Future<void> add(Character character) async {
    final repo = await ref.read(characterRepoProvider.future);
    await repo.put(character);
    ref.invalidateSelf();
  }

  Future<void> remove(String id) async {
    final repo = await ref.read(characterRepoProvider.future);
    await repo.delete(id);
    ref.invalidateSelf();
  }
}
