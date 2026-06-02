import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Computes a stable SHA-256 of a single OpenAI-compatible chat message.
/// Hash covers `role` + `content` (canonicalized) so identical messages
/// across requests produce identical hashes regardless of intermediate
/// runtime state.
String _messageHash(Map<String, dynamic> message) {
  final role = message['role']?.toString() ?? '';
  final content = _canonicalContent(message);
  final bytes = utf8.encode('$role\u0000$content');
  return sha256.convert(bytes).toString();
}

/// Normalizes a message's `content` field to a canonical string so that
/// structural variants (String vs List<Map> with cache_control, etc.) hash
/// the same way *for the purposes of prefix comparison*. The breakpoint
/// field is intentionally NOT part of the hash: only the underlying text
/// matters when deciding "is this message the same as before".
String _canonicalContent(Map<String, dynamic> message) {
  final c = message['content'];
  if (c == null) return '';
  if (c is String) return c;
  if (c is List) {
    final parts = <String>[];
    for (final part in c) {
      if (part is Map) {
        final type = part['type']?.toString() ?? 'text';
        if (type == 'text') {
          parts.add(part['text']?.toString() ?? '');
        } else {
          parts.add('[$type]');
        }
      } else {
        parts.add(part.toString());
      }
    }
    return parts.join('\n');
  }
  return c.toString();
}

/// Computes a list of per-message hashes for the messages that actually
/// go out to the LLM (i.e. after regex/macro/appendToLastMessage
/// transformations, but BEFORE we inject the explicit `cache_control`
/// breakpoint). Returned in the same order as [messages].
List<String> fingerprintMessages(List<Map<String, dynamic>> messages) {
  return messages.map(_messageHash).toList(growable: false);
}

/// Finds the highest index `i` such that
/// `previous[i] == current[i]` and `i < previous.length` and `i < current.length`.
/// This is the last message that is *byte-identical* to the prior request;
/// the optimal Anthropic explicit cache breakpoint is on this message.
///
/// Returns -1 if no common prefix exists (e.g. cold start, or a system
/// block changed).
int findLastCommonPrefixIndex({
  required List<String> previous,
  required List<String> current,
}) {
  final n = previous.length < current.length ? previous.length : current.length;
  int last = -1;
  for (int i = 0; i < n; i++) {
    if (previous[i] == current[i]) {
      last = i;
    } else {
      break;
    }
  }
  return last;
}

/// Converts a message's `content` from a plain String into the Anthropic
/// explicit-breakpoint content-block shape:
/// `[{ "type": "text", "text": "...", "cache_control": { "type": "ephemeral" } }]`.
///
/// If [ttl] is `'1h'`, the cache breakpoint gets `ttl: 1h`. Otherwise the
/// 5-minute default applies.
///
/// Returns the original message map unchanged if its content is already
/// structured or empty.
Map<String, dynamic> withExplicitCacheBreakpoint(
  Map<String, dynamic> message, {
  String ttl = '5min',
}) {
  final c = message['content'];
  if (c is! String || c.isEmpty) return message;
  final block = <String, dynamic>{
    'type': 'text',
    'text': c,
    'cache_control': <String, dynamic>{
      'type': 'ephemeral',
      if (ttl == '1h') 'ttl': '1h',
    },
  };
  return <String, dynamic>{
    ...message,
    'content': [block],
  };
}
