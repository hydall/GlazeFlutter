import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/persona.dart';
import '../../core/state/db_provider.dart';
import '../../core/utils/sync_deletion_tracker.dart';

final personaListProvider =
    AsyncNotifierProvider<PersonaListNotifier, List<Persona>>(
      PersonaListNotifier.new,
    );

class PersonaListNotifier extends AsyncNotifier<List<Persona>> {
  @override
  Future<List<Persona>> build() async {
    return ref.watch(personaRepoProvider).getAll();
  }

  Future<void> add(Persona persona) async {
    await ref.read(personaRepoProvider).put(persona);
    ref.invalidateSelf();
  }

  Future<void> remove(String id) async {
    await ref.read(personaRepoProvider).delete(id);
    await SyncDeletionTracker.record('persona', id);
    ref.invalidateSelf();
  }
}
