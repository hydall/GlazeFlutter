enum SyncProvider { dropbox, gdrive }

enum SyncStatus { idle, syncing, error, conflict }

enum EntityType {
  character,
  persona,
  chat,
  memoryBook,
  lorebooks,
  apiPresets,
  themePresets,
  themeState,
  localStorage,
  gallery,
  manifest,
}

class SyncManifestEntry {
  final String type;
  final String id;
  final String path;
  final int updatedAt;
  final String hash;
  final bool deleted;
  final String? charId;
  final String? imgId;
  final String? ext;

  const SyncManifestEntry({
    required this.type,
    required this.id,
    required this.path,
    required this.updatedAt,
    required this.hash,
    this.deleted = false,
    this.charId,
    this.imgId,
    this.ext,
  });

  String get key => entryKey(type, id);

  SyncManifestEntry copyWith({
    String? type,
    String? id,
    String? path,
    int? updatedAt,
    String? hash,
    bool? deleted,
    String? charId,
    String? imgId,
    String? ext,
  }) =>
      SyncManifestEntry(
        type: type ?? this.type,
        id: id ?? this.id,
        path: path ?? this.path,
        updatedAt: updatedAt ?? this.updatedAt,
        hash: hash ?? this.hash,
        deleted: deleted ?? this.deleted,
        charId: charId ?? this.charId,
        imgId: imgId ?? this.imgId,
        ext: ext ?? this.ext,
      );

  Map<String, dynamic> toJson() => {
        'type': type,
        'id': id,
        'path': path,
        'updatedAt': updatedAt,
        'hash': hash,
        'deleted': deleted,
        if (charId != null) 'charId': charId,
        if (imgId != null) 'imgId': imgId,
        if (ext != null) 'ext': ext,
      };

  factory SyncManifestEntry.fromJson(Map<String, dynamic> m) =>
      SyncManifestEntry(
        type: m['type'] as String,
        id: m['id'] as String,
        path: m['path'] as String,
        updatedAt: m['updatedAt'] as int,
        hash: m['hash'] as String,
        deleted: m['deleted'] as bool? ?? false,
        charId: m['charId'] as String?,
        imgId: m['imgId'] as String?,
        ext: m['ext'] as String?,
      );
}

class SyncManifest {
  /// Bump when hash/canonicalization changes so push can skip re-uploading
  /// existing cloud files and refresh manifest only.
  static const int currentVersion = 4;

  final int version;
  final String deviceId;
  final int? lastSync;
  final int createdAt;
  final Map<String, SyncManifestEntry> entries;
  /// Whether the last cloud push included API/embedding keys in api_presets.
  final bool apiKeysIncluded;

  const SyncManifest({
    this.version = 2,
    required this.deviceId,
    this.lastSync,
    required this.createdAt,
    this.entries = const {},
    this.apiKeysIncluded = false,
  });

  SyncManifest copyWith({
    int? version,
    String? deviceId,
    int? lastSync,
    int? createdAt,
    Map<String, SyncManifestEntry>? entries,
    bool? apiKeysIncluded,
  }) =>
      SyncManifest(
        version: version ?? this.version,
        deviceId: deviceId ?? this.deviceId,
        lastSync: lastSync ?? this.lastSync,
        createdAt: createdAt ?? this.createdAt,
        entries: entries ?? this.entries,
        apiKeysIncluded: apiKeysIncluded ?? this.apiKeysIncluded,
      );

  Map<String, dynamic> toJson() => {
        'version': version,
        'deviceId': deviceId,
        'lastSync': lastSync,
        'createdAt': createdAt,
        'apiKeysIncluded': apiKeysIncluded,
        'entries': entries.map((k, v) => MapEntry(k, v.toJson())),
      };

  factory SyncManifest.fromJson(Map<String, dynamic> m) => SyncManifest(
        version: m['version'] as int? ?? 2,
        deviceId: m['deviceId'] as String? ?? '',
        lastSync: m['lastSync'] as int?,
        createdAt: m['createdAt'] as int? ?? DateTime.now().millisecondsSinceEpoch,
        apiKeysIncluded: m['apiKeysIncluded'] as bool? ?? false,
        entries: _parseEntries(m['entries'] as Map<String, dynamic>?),
      );

  static Map<String, SyncManifestEntry> _parseEntries(Map<String, dynamic>? m) {
    if (m == null) return {};
    return m.map((k, v) =>
        MapEntry(k, SyncManifestEntry.fromJson(v as Map<String, dynamic>)));
  }
}

String entryKey(String type, String id) => '$type:$id';

const String cloudBase = '/Glaze';

const int maxSyncPayloadBytes = 30 * 1024 * 1024;

String cloudPath(String type, String id) {
  switch (type) {
    case 'character':
      return '$cloudBase/characters/$id.json';
    case 'persona':
      return '$cloudBase/personas/$id.json';
    case 'chat':
      return '$cloudBase/chats/$id.json';
    case 'memory_book':
      return '$cloudBase/memory_books/$id.json';
    case 'extension_preset':
      return '$cloudBase/extension_presets/$id.json';
    case 'extensions_settings':
      return '$cloudBase/extensions_settings.json';
    case 'info_block':
      return '$cloudBase/info_blocks/$id.json';
    case 'lorebooks':
      return '$cloudBase/lorebooks.json';
    case 'api_presets':
      return '$cloudBase/api_presets.json';
    case 'theme_presets':
      return '$cloudBase/theme_presets.json';
    case 'ui_themes':
      return '$cloudBase/ui_themes.json';
    case 'theme_state':
      return '$cloudBase/theme_state.json';
    case 'local_storage':
      return '$cloudBase/local_storage.json';
    case 'manifest':
      return '$cloudBase/manifest.json';
    default:
      return '$cloudBase/misc/$id.json';
  }
}

/// Canonical path for comparing manifest entry paths with cloud list_folder results.
/// Dropbox app-folder listings omit the `/Glaze` prefix; GDrive uses full paths.
String normalizeCloudSyncPath(String path) {
  var p = path.trim();
  if (p.isEmpty) return p;
  if (p.startsWith('$cloudBase/')) {
    p = p.substring(cloudBase.length);
  } else if (p == cloudBase) {
    p = '/';
  }
  if (!p.startsWith('/')) p = '/$p';
  return p;
}

bool cloudSyncPathExists(Set<String> normalizedPaths, String entryPath) {
  return normalizedPaths.contains(normalizeCloudSyncPath(entryPath));
}

String galleryCloudPath(String charId, String imgId, String ext) =>
    '$cloudBase/gallery/$charId/$imgId.$ext';

String personaAvatarCloudPath(String personaId, String ext) =>
    '$cloudBase/persona_avatars/$personaId/avatar.$ext';
