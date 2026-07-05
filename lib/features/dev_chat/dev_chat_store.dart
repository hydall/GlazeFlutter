import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/utils/id_generator.dart';
import 'dev_chat_config.dart';
import 'dev_chat_message.dart';

/// SharedPreferences-backed persistence for the developer chat. Low volume, so
/// the whole message list is stored as one JSON blob — no Drift table/migration.
class DevChatStore {
  /// A stable per-install anonymous id, minted on first access. This is the
  /// key the Worker uses to map the user to their Telegram topic.
  Future<String> userId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(DevChatConfig.kUserId);
    if (id == null || id.isEmpty) {
      id = generateId() + generateId();
      await prefs.setString(DevChatConfig.kUserId, id);
    }
    return id;
  }

  Future<String?> nick() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(DevChatConfig.kNick);
  }

  Future<void> setNick(String nick) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(DevChatConfig.kNick, nick);
  }

  Future<bool> hidden() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(DevChatConfig.kHidden) ?? false;
  }

  Future<void> setHidden(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(DevChatConfig.kHidden, value);
  }

  Future<int> since() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(DevChatConfig.kSince) ?? 0;
  }

  Future<void> setSince(int ts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(DevChatConfig.kSince, ts);
  }

  Future<List<DevChatMessage>> loadMessages() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(DevChatConfig.kMessages);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .whereType<Map<String, dynamic>>()
          .map(DevChatMessage.fromJson)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveMessages(List<DevChatMessage> messages) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      DevChatConfig.kMessages,
      jsonEncode(messages.map((m) => m.toJson()).toList()),
    );
  }
}
