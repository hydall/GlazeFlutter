import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/chat_message.dart';
import '../models/character.dart';

class ChatExportResult {
  final String filePath;
  ChatExportResult({required this.filePath});
}

class ChatImportResult {
  final List<ChatMessage> messages;
  final String? userName;
  ChatImportResult({required this.messages, this.userName});
}

Future<ChatExportResult> exportChatAsJsonl({
  required ChatSession session,
  required Character character,
  required String outputDir,
  String userName = 'User',
}) async {
  final lines = <String>[];

  final metadata = {
    'user_name': userName,
    'character_name': character.name,
    'create_date': _formatSTDate(DateTime.now()),
    'chat_metadata': {
      'exported_from': 'GlazeFlutter',
      'import_date': DateTime.now().millisecondsSinceEpoch,
    },
  };
  lines.add(jsonEncode(metadata));

  for (final msg in session.messages) {
    if (msg.isHidden) continue;
    final isUser = msg.role == 'user';
    final name = isUser ? userName : character.name;

    final stMsg = <String, dynamic>{
      'name': name,
      'is_user': isUser,
      'is_system': msg.role == 'system',
      'send_date': _formatSTDate(DateTime.fromMillisecondsSinceEpoch(msg.timestamp ?? 0)),
      'mes': msg.content,
      'swipe_id': msg.swipeId,
      'swipes': msg.swipes,
      'extra': <String, dynamic>{},
    };

    if (msg.reasoning != null) {
      stMsg['extra']!['reasoning'] = msg.reasoning;
    }
    if (msg.id.isNotEmpty) {
      stMsg['extra']!['glazeMessageId'] = msg.id;
    }

    if (msg.swipes.isNotEmpty && msg.swipes.length > 1) {
      stMsg['swipe_info'] = msg.swipes.map((_) => <String, dynamic>{}).toList();
    }

    lines.add(jsonEncode(stMsg));
  }

  final fileContent = lines.join('\n');
  final safeName = character.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  final dateStr = DateTime.now().toIso8601String().replaceAll(RegExp(r'[:T]'), '-').split('.').first;
  final filename = '$safeName - $dateStr.jsonl';
  final filePath = p.join(outputDir, filename);

  await File(filePath).writeAsString(fileContent);
  return ChatExportResult(filePath: filePath);
}

Future<ChatImportResult> importChatFromJsonl(String filePath) async {
  final file = File(filePath);
  if (!await file.exists()) {
    throw FileSystemException('File not found', filePath);
  }
  final content = await file.readAsString();
  if (content.trim().isEmpty) {
    throw StateError('File is empty: $filePath');
  }
  return importChatFromJsonlString(content);
}

ChatImportResult importChatFromJsonlString(String content) {
  final lines = content.split('\n');
  final messages = <ChatMessage>[];
  String? userName;

  for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;

    Map<String, dynamic> obj;
    try {
      obj = jsonDecode(trimmed) as Map<String, dynamic>;
    } catch (_) {
      continue;
    }

    if (obj.containsKey('chat_metadata')) {
      userName = obj['user_name'] as String?;
      continue;
    }

    final msg = _convertStMessage(obj, messages.length);
    if (msg == null) continue;

    messages.add(msg);
  }

  return ChatImportResult(messages: messages, userName: userName);
}

ChatMessage? _convertStMessage(Map<String, dynamic> obj, int index) {
  final isUser = obj['is_user'] as bool? ?? false;
  final isSystem = obj['is_system'] as bool? ?? false;
  final text = (obj['mes'] as String?) ?? '';
  final sendDate = obj['send_date'] as String?;

  String role;
  if (isSystem) {
    role = 'system';
  } else if (isUser) {
    role = 'user';
  } else {
    role = 'assistant';
  }

  if (text.trim().isEmpty) return null;

  final timestamp = _parseSTDate(sendDate);

  final swipes = (obj['swipes'] as List<dynamic>?)
          ?.map((s) => s.toString())
          .toList() ??
      [];
  final swipeId = obj['swipe_id'] as int? ?? 0;

  String? reasoning;
  final extra = obj['extra'] as Map<String, dynamic>?;
  if (extra != null) {
    reasoning = extra['reasoning'] as String?;
  }

  return ChatMessage(
    id: (obj['extra']?['glazeMessageId'] as String?) ?? 'imp_${DateTime.now().millisecondsSinceEpoch}_$index',
    role: role,
    content: text,
    timestamp: timestamp,
    swipes: swipes,
    swipeId: swipeId,
    reasoning: reasoning,
  );
}

int _parseSTDate(String? dateStr) {
  if (dateStr == null) return DateTime.now().millisecondsSinceEpoch;
  try {
    final parts = dateStr.split(RegExp(r'[\s/:T]'));
    if (parts.length >= 6) {
      final dt = DateTime(
        int.parse(parts[0]),
        int.parse(parts[1]),
        int.parse(parts[2]),
        int.parse(parts[3]),
        int.parse(parts[4]),
        int.parse(parts[5]),
      );
      return dt.millisecondsSinceEpoch;
    }
  } catch (_) {}
  return DateTime.now().millisecondsSinceEpoch;
}

String _formatSTDate(DateTime dt) {
  final pad = (int n) => n.toString().padLeft(2, '0');
  return '${dt.year}-${pad(dt.month)}-${pad(dt.day)} ${pad(dt.hour)}:${pad(dt.minute)}:${pad(dt.second)}';
}
