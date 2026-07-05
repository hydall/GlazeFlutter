import 'package:dio/dio.dart';

import 'dev_chat_config.dart';
import 'dev_chat_message.dart';

/// Thin transport over the Cloudflare Worker bridge. No business logic — it
/// just does HTTP; the provider owns state and persistence.
class DevChatService {
  DevChatService([Dio? dio])
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 15),
            ));

  final Dio _dio;

  /// Sends a user message to the developer group. Throws on failure so the
  /// caller can mark the message as failed.
  Future<void> send({
    required String userId,
    required String nick,
    required String text,
  }) async {
    final r = await _dio.post<Map<String, dynamic>>(
      '${DevChatConfig.baseUrl}/send',
      data: {'userId': userId, 'nick': nick, 'text': text},
    );
    if (r.data?['ok'] != true) {
      throw DevChatException(r.data?['error']?.toString() ?? 'send_failed');
    }
  }

  /// Polls for developer replies newer than [since] (epoch ms).
  /// Returns the new messages and the server clock to use as the next cursor.
  Future<({List<DevChatMessage> messages, int now})> poll({
    required String userId,
    required int since,
  }) async {
    final r = await _dio.get<Map<String, dynamic>>(
      '${DevChatConfig.baseUrl}/poll',
      queryParameters: {'userId': userId, 'since': since},
    );
    final raw = (r.data?['messages'] as List?) ?? const [];
    final messages = raw
        .whereType<Map<String, dynamic>>()
        .map(DevChatMessage.fromJson)
        .toList();
    final now = (r.data?['now'] as num?)?.toInt() ?? since;
    return (messages: messages, now: now);
  }

  /// URL of a developer's avatar (proxied — no token exposure). 404 → the UI
  /// falls back to initials.
  static String avatarUrl(String devId) =>
      '${DevChatConfig.baseUrl}/avatar?devId=$devId';
}

class DevChatException implements Exception {
  DevChatException(this.message);
  final String message;
  @override
  String toString() => 'DevChatException: $message';
}
