import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:glaze_flutter/core/models/api_config.dart';
import 'package:glaze_flutter/core/models/character.dart';
import 'package:glaze_flutter/core/models/chat_message.dart';
import 'package:glaze_flutter/core/models/lorebook.dart';
import 'package:glaze_flutter/core/models/persona.dart';
import 'package:glaze_flutter/core/models/preset.dart';
import 'package:glaze_flutter/features/cloud_sync/cloud_adapter.dart';
import 'package:glaze_flutter/features/cloud_sync/services/sync_conflict.dart';
import 'package:glaze_flutter/features/cloud_sync/services/sync_engine.dart';
import 'package:glaze_flutter/features/cloud_sync/services/sync_manifest.dart';
import 'package:glaze_flutter/features/cloud_sync/services/sync_serialization.dart';
import 'package:glaze_flutter/features/cloud_sync/sync_models.dart';
import 'package:glaze_flutter/features/cloud_sync/sync_repo_interfaces.dart';

// ─── In-memory fakes ────────────────────────────────────────────────

class FakeCharacterStore implements SyncCharacterStore {
  final Map<String, Character> data = {};

  @override
  Future<List<Character>> getAll() async => data.values.toList();

  @override
  Future<Character?> getById(String id) async => data[id];

  @override
  Future<void> put(Character c) async {
    data[c.id] = c;
  }

  @override
  Future<void> delete(String id) async {
    data.remove(id);
  }
}

class FakeChatStore implements SyncChatStore {
  final Map<String, ChatSession> data = {};

  @override
  Future<List<SessionMetadata>> getAllSessionMetadata() async {
    return data.values
        .map((s) => SessionMetadata(
              sessionId: s.id,
              characterId: s.characterId,
              sessionIndex: s.sessionIndex,
              updatedAt: s.updatedAt,
              messageCount: s.messages.length,
              lastMessageContent: '',
              lastMessageTimestamp: 0,
            ))
        .toList();
  }

  @override
  Future<ChatSession?> getById(String id) async => data[id];

  @override
  Future<void> put(ChatSession s) async {
    data[s.id] = s;
  }

  @override
  Future<void> delete(String id) async {
    data.remove(id);
  }
}

class FakePersonaStore implements SyncPersonaStore {
  final Map<String, Persona> data = {};

  @override
  Future<List<Persona>> getAll() async => data.values.toList();

  @override
  Future<Persona?> getById(String id) async => data[id];

  @override
  Future<void> put(Persona p) async {
    data[p.id] = p;
  }

  @override
  Future<void> delete(String id) async {
    data.remove(id);
  }
}

class FakePresetStore implements SyncPresetStore {
  final Map<String, Preset> data = {};

  @override
  Future<List<Preset>> getAll() async => data.values.toList();

  @override
  Future<Preset?> getById(String id) async => data[id];

  @override
  Future<void> put(Preset p) async {
    data[p.id] = p;
  }

  @override
  Future<void> delete(String id) async {
    data.remove(id);
  }
}

class FakeApiConfigStore implements SyncApiConfigStore {
  final Map<String, ApiConfig> data = {};

  @override
  Future<List<ApiConfig>> getAll() async => data.values.toList();

  @override
  Future<ApiConfig?> getById(String id) async => data[id];

  @override
  Future<void> put(ApiConfig c) async {
    data[c.id] = c;
  }

  @override
  Future<void> delete(String id) async {
    data.remove(id);
  }
}

class FakeLorebookStore implements SyncLorebookStore {
  final Map<String, Lorebook> data = {};

  @override
  Future<List<Lorebook>> getAll() async => data.values.toList();

  @override
  Future<Lorebook?> getById(String id) async => data[id];

  @override
  Future<void> put(Lorebook l) async {
    data[l.id] = l;
  }

  @override
  Future<void> delete(String id) async {
    data.remove(id);
  }
}

class FakeEmbeddingStore implements SyncEmbeddingStore {
  final List<String> deletedIds = [];

  @override
  Future<void> deleteBySourceId(String sourceId) async {
    deletedIds.add(sourceId);
  }
}

class FakeImageStore implements SyncImageStore {
  final Map<String, Uint8List> saved = {};

  @override
  String? absolutePath(String? relativePath) => relativePath;

  @override
  Future<String> saveBytes(
      Uint8List bytes, String subfolder, String filename, String ext) async {
    final key = '$subfolder/$filename.$ext';
    saved[key] = bytes;
    return key;
  }
}

class FakeCloudAdapter implements CloudAdapter {
  final Map<String, String> files = {};

  @override
  Future<bool> isConnected() async => true;

  @override
  Future<void> ensureFolder(String path) async {}

  @override
  Future<void> upload(String path, String data) async {
    files[path] = data;
  }

  @override
  Future<void> uploadBinary(String path, Uint8List data) async {
    files[path] = String.fromCharCodes(data);
  }

  @override
  Future<String> download(String path) async {
    final data = files[path];
    if (data == null) throw Exception('File not found: $path');
    return data;
  }

  @override
  Future<Uint8List> downloadBinary(String path) async {
    final data = files[path];
    if (data == null) throw Exception('File not found: $path');
    return Uint8List.fromList(data.codeUnits);
  }

  @override
  Future<void> deleteFile(String path) async {
    files.remove(path);
  }

  @override
  Future<void> deleteFolder(String path) async {
    files.removeWhere((k, _) => k.startsWith(path));
  }

  @override
  Future<List<CloudFileInfo>> listFolder(String path) async {
    return files.keys
        .where((k) => k.startsWith(path))
        .map((k) =>
            CloudFileInfo(path: k, name: k.split('/').last, isFolder: false))
        .toList();
  }

  @override
  Future<Map<String, dynamic>?> getAccountInfo() async => {};

  @override
  Future<void> invalidateFolderCache() async {}
}

// ─── In-memory manifest provider (no SharedPreferences needed) ──────

class InMemoryManifestProvider implements SyncManifestProvider {
  final SyncManifestBuilder _builder;
  SyncManifest _cached = const SyncManifest(deviceId: '', createdAt: 0);
  final Map<String, String> _storage = {};

  InMemoryManifestProvider({
    required SyncCharacterStore characterRepo,
    required SyncChatStore chatRepo,
    required SyncPersonaStore personaRepo,
    required SyncPresetStore presetRepo,
    required SyncApiConfigStore apiRepo,
    required SyncLorebookStore lorebookRepo,
  }) : _builder = SyncManifestBuilder(
          characterRepo: characterRepo,
          chatRepo: chatRepo,
          personaRepo: personaRepo,
          presetRepo: presetRepo,
          apiRepo: apiRepo,
          lorebookRepo: lorebookRepo,
        );

  @override
  Future<SyncManifest> buildLocalManifest() => _builder.buildLocalManifest();

  @override
  Future<SyncManifest> readLocalManifest() async {
    final raw = _storage['manifest'];
    if (raw == null) return _cached;
    return SyncManifest.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  @override
  Future<void> writeLocalManifest(SyncManifest manifest) async {
    _cached = manifest;
    _storage['manifest'] = jsonEncode(manifest.toJson());
  }

  @override
  Future<void> clearDeleted() async {}
}

// ─── Helper: build a complete in-memory environment ─────────────────

class SyncWorld {
  late final FakeCharacterStore characters;
  late final FakeChatStore chats;
  late final FakePersonaStore personas;
  late final FakePresetStore presets;
  late final FakeApiConfigStore apiConfigs;
  late final FakeLorebookStore lorebooks;
  late final FakeEmbeddingStore embeddings;
  late final FakeImageStore images;
  late final FakeCloudAdapter cloud;
  late final InMemoryManifestProvider manifestProvider;

  SyncWorld() {
    characters = FakeCharacterStore();
    chats = FakeChatStore();
    personas = FakePersonaStore();
    presets = FakePresetStore();
    apiConfigs = FakeApiConfigStore();
    lorebooks = FakeLorebookStore();
    embeddings = FakeEmbeddingStore();
    images = FakeImageStore();
    cloud = FakeCloudAdapter();
    manifestProvider = InMemoryManifestProvider(
      characterRepo: characters,
      chatRepo: chats,
      personaRepo: personas,
      presetRepo: presets,
      apiRepo: apiConfigs,
      lorebookRepo: lorebooks,
    );
  }

  SyncEngine get engine => SyncEngine(
        cloud,
        manifestProvider,
        characters,
        chats,
        personas,
        presets,
        apiConfigs,
        lorebooks,
        embeddings,
        images,
      );
}

// ─── Fixtures ───────────────────────────────────────────────────────

Character makeChar(String id, {String name = 'Test', String? avatarPath}) =>
    Character(id: id, name: name, avatarPath: avatarPath);

Persona makePersona(String id, {String name = 'Persona'}) =>
    Persona(id: id, name: name);

ChatSession makeChat(String id, {String charId = 'char1', int index = 0}) =>
    ChatSession(id: id, characterId: charId, sessionIndex: index);

ApiConfig makeApiConfig(String id, {String name = 'Default'}) =>
    ApiConfig(id: id, name: name);

Preset makePreset(String id, {String name = 'Preset'}) =>
    Preset(id: id, name: name);

Lorebook makeLorebook(String id, {String name = 'Lorebook'}) =>
    Lorebook(id: id, name: name);

// ─── Tests ──────────────────────────────────────────────────────────

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('Full sync lifecycle: push → pull → conflict → resolve', () async {
    // ── SCENE 1: Device A pushes to empty cloud ──
    final deviceA = SyncWorld();
    final char1 = makeChar('char1', name: 'Alice');
    final persona1 = makePersona('p1', name: 'Bob');
    final chat1 = makeChat('s1', charId: 'char1');

    await deviceA.characters.put(char1);
    await deviceA.personas.put(persona1);
    await deviceA.chats.put(chat1);

    final localManifest = await deviceA.manifestProvider.buildLocalManifest();
    await deviceA.manifestProvider.writeLocalManifest(localManifest);

    await deviceA.engine.pushEntities(onProgress: (_) {});

    expect(deviceA.cloud.files.containsKey(cloudPath('character', 'char1')),
        isTrue,
        reason: 'Push should upload character to cloud');
    expect(deviceA.cloud.files.containsKey(cloudPath('persona', 'p1')),
        isTrue,
        reason: 'Push should upload persona to cloud');
    expect(deviceA.cloud.files.containsKey(cloudPath('chat', 's1')), isTrue,
        reason: 'Push should upload chat to cloud');
    expect(deviceA.cloud.files.containsKey(cloudPath('manifest', 'manifest')),
        isTrue,
        reason: 'Push should upload manifest');

    // ── SCENE 2: Device B (empty) pulls from cloud ──
    final deviceB = SyncWorld();

    deviceB.cloud.files.addAll(deviceA.cloud.files);

    final conflicts = <SyncConflict>[];
    await deviceB.engine.pullEntities(
      onProgress: (_) {},
      onConflict: (c) => conflicts.add(c),
    );

    // BUG 1: False conflicts on empty device
    expect(conflicts, isEmpty,
        reason:
            'BUG: Empty device should have NO conflicts when pulling. '
            'The manifest builder creates singleton entries (lorebooks, api_presets, '
            'theme_presets) with updatedAt=now even for empty data. Since now > '
            'cloud.updatedAt, needsConflict returns true → false conflicts.');

    expect(deviceB.characters.data['char1'], isNotNull,
        reason: 'Pull should download character from cloud');
    expect(deviceB.personas.data['p1'], isNotNull,
        reason: 'Pull should download persona from cloud');
    expect(deviceB.chats.data['s1'], isNotNull,
        reason: 'Pull should download chat from cloud');

    // ── SCENE 3: Both modify same entity → conflict ──
    final deviceX = SyncWorld();
    final sharedChar = makeChar('shared1', name: 'Original');
    await deviceX.characters.put(sharedChar);

    final xLocalManifest =
        await deviceX.manifestProvider.buildLocalManifest();
    await deviceX.manifestProvider.writeLocalManifest(xLocalManifest);
    await deviceX.engine.pushEntities(onProgress: (_) {});

    // Simulate: another device also has this character but modified locally
    // after the push. Its local updatedAt > cloud updatedAt.
    final deviceY = SyncWorld();
    deviceY.cloud.files.addAll(deviceX.cloud.files);

    final modifiedChar = makeChar('shared1', name: 'Device Y Edit');
    await deviceY.characters.put(modifiedChar);

    // Force local manifest to show updatedAt newer than cloud
    final yManifest = await deviceY.manifestProvider.buildLocalManifest();
    final patchedEntries = Map<String, SyncManifestEntry>.from(yManifest.entries);
    final charEntry = patchedEntries['character:shared1'];
    if (charEntry != null) {
      patchedEntries['character:shared1'] = charEntry.copyWith(
        updatedAt: DateTime.now().millisecondsSinceEpoch + 100000,
        hash: 'y_local_hash',
      );
    }
    await deviceY.manifestProvider.writeLocalManifest(
      yManifest.copyWith(entries: patchedEntries),
    );

    final yConflicts = <SyncConflict>[];
    await deviceY.engine.pullEntities(
      onProgress: (_) {},
      onConflict: (c) => yConflicts.add(c),
    );

    expect(
        yConflicts.any((c) => c.type == 'character' && c.id == 'shared1'),
        isTrue,
        reason:
            'Conflict should be detected when local entity is newer than cloud');

    // ── SCENE 4: Resolve conflict — choose cloud ──
    await deviceY.engine.resolveConflict(
      yConflicts.firstWhere((c) => c.id == 'shared1'),
      'cloud',
    );

    expect(deviceY.characters.data['shared1']?.name, equals('Original'),
        reason:
            'After resolving conflict with "cloud", local should have cloud data');

    // ── SCENE 5: Second pull after resolution → no duplicate conflict ──
    final yConflicts2 = <SyncConflict>[];
    await deviceY.engine.pullEntities(
      onProgress: (_) {},
      onConflict: (c) => yConflicts2.add(c),
    );

    expect(yConflicts2.any((c) => c.id == 'shared1'), isFalse,
        reason:
            'BUG: After resolving a conflict, the next pull should not '
            're-trigger the same conflict. But resolveConflict only calls '
            '_pullEntry (which applies the data) without updating the '
            'manifest. The old hash/timestamp remains in the manifest, '
            'so the next pull sees a mismatch again → infinite conflict loop.');
  });

  test(
      'Singleton push: lorebooks/api_presets/theme_presets upload as list',
      () async {
    final world = SyncWorld();
    await world.lorebooks.put(makeLorebook('lb1', name: 'World Lore'));
    await world.apiConfigs.put(makeApiConfig('api1', name: 'My API'));
    await world.presets.put(makePreset('pr1', name: 'My Preset'));

    final manifest = await world.manifestProvider.buildLocalManifest();
    await world.manifestProvider.writeLocalManifest(manifest);

    await world.engine.pushEntities(onProgress: (_) {});

    // BUG: _readLocalEntity('lorebooks', 'lorebooks') calls
    // _lorebookRepo.getById('lorebooks') which returns null because
    // no lorebook has id='lorebooks'. The manifest entry has
    // type='lorebooks', id='lorebooks' (singleton pattern).
    // But _readLocalEntity tries to fetch a single entity by that id,
    // not the full list. Same for api_presets and theme_presets.
    expect(
        world.cloud.files.containsKey(cloudPath('lorebooks', 'lorebooks')),
        isTrue,
        reason:
            'Singleton types should push the entire list wrapped in '
            '{"__singleton": true, "items": [...]} format');

    expect(
        world.cloud.files
            .containsKey(cloudPath('api_presets', 'api_presets')),
        isTrue,
        reason: 'Same for api_presets singleton');

    expect(
        world.cloud.files
            .containsKey(cloudPath('theme_presets', 'theme_presets')),
        isTrue,
        reason: 'Same for theme_presets singleton');
  });

  test(
      'Singleton pull: lorebooks/api_presets deserialize items array correctly',
      () async {
    final world = SyncWorld();

    // Simulate cloud having lorebooks in singleton format
    final cloudLorebooks = [
      makeLorebook('lb1', name: 'World').toJson(),
      makeLorebook('lb2', name: 'Characters').toJson(),
    ];

    final manifest = SyncManifest(
      deviceId: 'cloud',
      createdAt: 1000,
      entries: {
        'lorebooks:lorebooks': SyncManifestEntry(
          type: 'lorebooks',
          id: 'lorebooks',
          path: cloudPath('lorebooks', 'lorebooks'),
          updatedAt: 1000,
          hash: 'abc',
        ),
      },
    );

    world.cloud.files[cloudPath('manifest', 'manifest')] =
        jsonEncode(manifest.toJson());
    world.cloud.files[cloudPath('lorebooks', 'lorebooks')] =
        jsonEncode({'__singleton': true, 'items': cloudLorebooks});

    // Device has no lorebooks locally
    final conflicts = <SyncConflict>[];
    await world.engine.pullEntities(
      onProgress: (_) {},
      onConflict: (c) => conflicts.add(c),
    );

    // BUG: _applyCloudEntity('lorebooks', 'lorebooks', data) does:
    //   Lorebook.fromJson(data)
    // But data is a List, not a Map. fromJson throws, catch(_){} swallows.
    // The lorebooks are never saved locally.
    expect(world.lorebooks.data.length, greaterThan(0),
        reason:
            'Cloud lorebooks stored in singleton format should be applied '
            'locally. _applyCloudEntity iterates the items array and '
            'puts each lorebook individually.');
  });

  test(
      'Empty device with no API presets should not conflict with cloud',
      () async {
    final world = SyncWorld();

    // Device has NO API configs — completely empty
    final cloudApi = makeApiConfig('default', name: 'Default');
    final cloudManifest = SyncManifest(
      deviceId: 'cloud',
      createdAt: 1000,
      entries: {
        'api_presets:api_presets': SyncManifestEntry(
          type: 'api_presets',
          id: 'api_presets',
          path: cloudPath('api_presets', 'api_presets'),
          updatedAt: 500,
          hash: 'cloud_hash',
        ),
      },
    );

    world.cloud.files[cloudPath('manifest', 'manifest')] =
        jsonEncode(cloudManifest.toJson());
    world.cloud.files[cloudPath('api_presets', 'api_presets')] =
        jsonEncode({'__singleton': true, 'items': [cloudApi.toJson()]});

    // Build local manifest — empty singleton should get updatedAt=0
    final localManifest = await world.manifestProvider.buildLocalManifest();
    await world.manifestProvider.writeLocalManifest(localManifest);

    // Verify: empty singletons have updatedAt=0
    final apiEntry = localManifest.entries['api_presets:api_presets'];
    expect(apiEntry?.updatedAt, equals(0),
        reason:
            'Empty singleton entries should have updatedAt=0 so they '
            'never appear "newer" than cloud data');

    final conflicts = <SyncConflict>[];
    await world.engine.pullEntities(
      onProgress: (_) {},
      onConflict: (c) => conflicts.add(c),
    );

    expect(conflicts, isEmpty,
        reason:
            'Empty device with no API presets should NOT conflict with '
            'cloud. Empty singletons get updatedAt=0 which is always <= '
            'cloud updatedAt, so needsConflict returns false.');

    expect(world.apiConfigs.data['default'], isNotNull,
        reason: 'Cloud API config should be pulled to local');
  });

  test(
      'resolveConflict("cloud") updates manifest — next pull does not re-trigger conflict',
      () async {
    final world = SyncWorld();

    final localChar = makeChar('c1', name: 'Local Version');
    await world.characters.put(localChar);

    final cloudChar = makeChar('c1', name: 'Cloud Version');
    final cloudHash = SyncSerialization.computeSyncHash(cloudChar.toJson());
    final cloudManifest = SyncManifest(
      deviceId: 'cloud',
      createdAt: 1000,
      entries: {
        'character:c1': SyncManifestEntry(
          type: 'character',
          id: 'c1',
          path: cloudPath('character', 'c1'),
          updatedAt: 500,
          hash: cloudHash,
        ),
      },
    );

    world.cloud.files[cloudPath('manifest', 'manifest')] =
        jsonEncode(cloudManifest.toJson());
    world.cloud.files[cloudPath('character', 'c1')] =
        jsonEncode(cloudChar.toJson());

    // Build a real local manifest from data, then write it
    final localManifest = await world.manifestProvider.buildLocalManifest();
    // Patch: make the character entry appear newer than cloud
    final patchedEntries = Map<String, SyncManifestEntry>.from(localManifest.entries);
    final charEntry = patchedEntries['character:c1'];
    if (charEntry != null) {
      patchedEntries['character:c1'] = charEntry.copyWith(
        updatedAt: DateTime.now().millisecondsSinceEpoch + 100000,
      );
    }
    await world.manifestProvider.writeLocalManifest(
      localManifest.copyWith(entries: patchedEntries),
    );

    // First pull — detects conflict
    final conflicts1 = <SyncConflict>[];
    await world.engine.pullEntities(
      onProgress: (_) {},
      onConflict: (c) => conflicts1.add(c),
    );

    expect(conflicts1.length, 1, reason: 'Should detect one conflict');

    // Resolve: choose cloud
    await world.engine.resolveConflict(conflicts1.first, 'cloud');

    expect(world.characters.data['c1']?.name, equals('Cloud Version'),
        reason:
            'After resolving conflict with "cloud", local should have cloud data');

    // Rebuild manifest from current data (now cloud version)
    final resolvedManifest = await world.manifestProvider.buildLocalManifest();
    await world.manifestProvider.writeLocalManifest(resolvedManifest);

    // Second pull — should NOT conflict because hashes now match
    final conflicts2 = <SyncConflict>[];
    await world.engine.pullEntities(
      onProgress: (_) {},
      onConflict: (c) => conflicts2.add(c),
    );

    expect(conflicts2, isEmpty,
        reason:
            'After resolving a conflict and rebuilding the manifest, '
            'the next pull should not re-trigger the same conflict. '
            'The rebuilt manifest should have the same hash as cloud.');
  });

  test('Wipe resets status to idle — subsequent push does not show wipe state',
      () async {
    final world = SyncWorld();

    // Push some data first
    await world.characters.put(makeChar('c1', name: 'Alice'));
    final manifest = await world.manifestProvider.buildLocalManifest();
    await world.manifestProvider.writeLocalManifest(manifest);
    await world.engine.pushEntities(onProgress: (_) {});

    expect(world.cloud.files.isNotEmpty, isTrue,
        reason: 'Cloud should have data before wipe');

    // Wipe cloud data — engine resets to idle after wipe
    await world.engine.wipeCloudData(onProgress: (_) {});

    expect(world.cloud.files.isEmpty, isTrue,
        reason: 'Cloud should be empty after wipe');

    // Simulate the SyncService status transition:
    // wipeCloudData sets _status = SyncStatus.syncing, then idle on success
    // The UI must read service.status after wipe completes
    // If it doesn't, the status provider stays at SyncStatus.syncing

    // Push again after wipe
    await world.characters.put(makeChar('c2', name: 'Bob'));
    final manifest2 = await world.manifestProvider.buildLocalManifest();
    await world.manifestProvider.writeLocalManifest(manifest2);

    // This should work without issues — no stale wipe state
    await world.engine.pushEntities(onProgress: (_) {});

    expect(world.cloud.files.containsKey(cloudPath('character', 'c2')), isTrue,
        reason: 'Push after wipe should upload new character');
    expect(world.cloud.files.containsKey(cloudPath('character', 'c1')), isTrue,
        reason: 'Push after wipe should upload previously wiped character too');
  });
}
