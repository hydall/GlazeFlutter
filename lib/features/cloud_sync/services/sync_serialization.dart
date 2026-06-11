import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../../core/models/chat_message.dart';
import '../../../core/models/memory_book.dart';
import '../cloud_adapter.dart';
import '../sync_models.dart';

class SyncSerialization {
  /// Content fingerprint for manifest conflict detection (not full session JSON).
  static String computeChatMetadataHash(SessionMetadata metadata) {
    return computeSyncHash({
      'sessionId': metadata.sessionId,
      'characterId': metadata.characterId,
      'sessionIndex': metadata.sessionIndex,
      'updatedAt': metadata.updatedAt,
      'messageCount': metadata.messageCount,
      'lastMessageContent': metadata.lastMessageContent,
      'lastMessageTimestamp': metadata.lastMessageTimestamp,
      'sessionName': metadata.sessionName,
    });
  }

  static String computeSyncHash(dynamic data) {
    final json = jsonEncode(data);
    return sha256.convert(utf8.encode(json)).toString();
  }

  /// Device-local / derived fields excluded so parity does not false-conflict.
  static const _memoryBookSettingsHashKeys = {
    'enabled',
    'autoCreateEnabled',
    'autoGenerateEnabled',
    'maxInjectedEntries',
    'maxInjectionBudgetPercent',
    'maxInjectedTokens',
    'memoryBudgetPreset',
    'autoCreateInterval',
    'useDelayedAutomation',
    'injectionTarget',
    'batchSize',
    'vectorSearchEnabled',
    'keyMatchMode',
    'promptPreset',
  };

  static Map<String, dynamic> normalizeMemoryBookForHash(
    Map<String, dynamic> json,
  ) {
    final settings = json['settings'];
    return {
      'sessionId': json['sessionId'],
      'entries': json['entries'] ?? <dynamic>[],
      'pendingDrafts': json['pendingDrafts'] ?? <dynamic>[],
      'settings': _memoryBookSettingsForHash(settings),
    };
  }

  static Map<String, dynamic> _memoryBookSettingsForHash(dynamic settings) {
    if (settings is! Map) return {};
    try {
      final canonical = MemoryBookSettings.fromJson(
        Map<String, dynamic>.from(settings),
      ).toJson();
      return {
        for (final key in _memoryBookSettingsHashKeys)
          if (canonical.containsKey(key)) key: canonical[key],
      };
    } catch (_) {
      return {};
    }
  }

  static String computeMemoryBookHash(Map<String, dynamic> json) {
    try {
      final canonical = MemoryBook.fromJson(json).toJson();
      return computeSyncHash(normalizeMemoryBookForHash(canonical));
    } catch (_) {
      return computeSyncHash(normalizeMemoryBookForHash(json));
    }
  }

  static String computeApiPresetsHash(Iterable<Map<String, dynamic>> items) {
    return computeSyncHash(
      items.map((item) {
        final copy = Map<String, dynamic>.from(item);
        copy['apiKey'] = '';
        copy['embeddingApiKey'] = '';
        return copy;
      }).toList(),
    );
  }

  static String computeBinaryHash(List<int> bytes) {
    return sha256.convert(bytes).toString();
  }

  static String computeImageHash(String dataUrl) {
    final commaIdx = dataUrl.indexOf(',');
    final raw = commaIdx >= 0 ? dataUrl.substring(commaIdx + 1) : dataUrl;
    final bytes = base64Decode(raw);
    return computeBinaryHash(bytes);
  }

  static String guessImageExt(String dataUrl) {
    final mimeMatch = RegExp(r'data:([^;]+);').firstMatch(dataUrl);
    if (mimeMatch == null) return 'png';
    final mime = mimeMatch[1]!;
    if (mime.contains('jpeg') || mime.contains('jpg')) return 'jpg';
    if (mime.contains('gif')) return 'gif';
    if (mime.contains('webp')) return 'webp';
    return 'png';
  }

  static Future<void> deleteCloudFileIfExists(
    CloudAdapter adapter,
    SyncManifestEntry entry,
  ) async {
    try {
      await adapter.deleteFile(entry.path);
    } catch (_) {}
  }

  static Future<Map<String, dynamic>?> readCloudEntity(
    CloudAdapter adapter,
    SyncManifestEntry entry,
  ) async {
    try {
      final raw = await adapter.download(entry.path);
      if (raw.isEmpty) return null;
      if (raw.length > maxSyncPayloadBytes) {
        throw Exception(
          'Payload exceeds ${maxSyncPayloadBytes ~/ 1024 ~/ 1024}MB limit',
        );
      }
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}
