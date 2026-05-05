import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/character.dart';
import 'db_provider.dart';

final charactersProvider =
    AsyncNotifierProvider<CharactersNotifier, List<Character>>(
        CharactersNotifier.new);

class CharactersNotifier extends AsyncNotifier<List<Character>> {
  @override
  Future<List<Character>> build() async {
    final repo = ref.watch(characterRepoProvider);
    return repo.getAll();
  }

  Future<void> add(Character character) async {
    final repo = ref.read(characterRepoProvider);
    await repo.put(character);
    ref.invalidateSelf();
  }

  Future<void> remove(String id) async {
    final repo = ref.read(characterRepoProvider);
    await repo.delete(id);
    ref.invalidateSelf();
  }
}
