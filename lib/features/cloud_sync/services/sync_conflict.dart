import '../sync_models.dart';

class SyncConflict {
  final String key;
  final String type;
  final String id;
  final SyncManifestEntry localEntry;
  final SyncManifestEntry cloudEntry;
  final String name;

  const SyncConflict({
    required this.key,
    required this.type,
    required this.id,
    required this.localEntry,
    required this.cloudEntry,
    required this.name,
  });
}

class SyncConflictDetector {
  static bool needsConflict(
    SyncManifestEntry? localEntry,
    SyncManifestEntry cloudEntry,
  ) {
    if (localEntry == null) return false;
    if (localEntry.deleted) return false;
    if (localEntry.hash == cloudEntry.hash) return false;
    return localEntry.updatedAt > cloudEntry.updatedAt;
  }

  static String getConflictName(
    String type,
    dynamic localEntity,
    dynamic cloudEntity,
    String id,
  ) {
    switch (type) {
      case 'character':
        return (localEntity?['name'] ?? cloudEntity?['name'] ?? 'Character $id') as String;
      case 'persona':
        return (localEntity?['name'] ?? cloudEntity?['name'] ?? 'Persona $id') as String;
      case 'chat':
        final charName = localEntity?['characterName'] ?? cloudEntity?['characterName'];
        return charName != null ? 'Chat with $charName' : 'Chat $id';
      case 'lorebooks':
        return 'Lorebooks';
      case 'api_presets':
        return 'API Presets';
      case 'theme_presets':
        return 'Theme Presets';
      case 'theme_state':
        return 'Theme State';
      case 'local_storage':
        return 'Local Settings';
      default:
        return '$type $id';
    }
  }
}
