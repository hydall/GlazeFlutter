import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// MIME-inferred, base64-encoded image attachment ready to embed into a
/// provider request.
class EncodedAttachment {
  /// e.g. `image/png`, `image/jpeg`.
  final String mimeType;

  /// Raw base64 payload (no `data:...;base64,` prefix).
  final String base64Data;

  /// Convenience `data:` URL (used by OpenAI/OpenRouter `image_url` parts).
  String get dataUrl => 'data:$mimeType;base64,$base64Data';

  const EncodedAttachment({required this.mimeType, required this.base64Data});
}

/// Reads a local image file and encodes it for transport. Returns `null` on
/// any failure (missing file, unreadable, IO error) and logs via `debugPrint`
/// — image attachment is best-effort and must never crash generation.
///
/// Path may also be a `data:` URL (web/desktop image picker) — in that case
/// the base64 + mime are parsed directly without disk I/O.
Future<EncodedAttachment?> encodeImageAttachment(String pathOrDataUrl) async {
  if (pathOrDataUrl.isEmpty) return null;

  if (pathOrDataUrl.startsWith('data:')) {
    return _parseDataUrl(pathOrDataUrl);
  }

  try {
    final file = File(pathOrDataUrl);
    if (!await file.exists()) {
      debugPrint('[attachment] file not found: $pathOrDataUrl');
      return null;
    }
    final bytes = await file.readAsBytes();
    if (bytes.length > 5 * 1024 * 1024) {
      debugPrint(
        '[attachment] image > 5 MB (${bytes.length} bytes) — '
        'Anthropic/Gemini may reject',
      );
    }
    final mime = _inferMimeFromPath(pathOrDataUrl);
    return EncodedAttachment(mimeType: mime, base64Data: base64Encode(bytes));
  } catch (e) {
    debugPrint('[attachment] encode failed: $e');
    return null;
  }
}

EncodedAttachment? _parseDataUrl(String dataUrl) {
  final match = RegExp(r'^data:([^;]+);base64,(.+)$').firstMatch(dataUrl);
  if (match == null) return null;
  return EncodedAttachment(
    mimeType: match.group(1)!,
    base64Data: match.group(2)!,
  );
}

String _inferMimeFromPath(String path) {
  final lower = path.toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.gif')) return 'image/gif';
  // Anthropic supports png/jpeg/gif/webp only; Gemini same. Default to jpeg
  // for unknown extensions — providers reject explicitly on unsupported MIME.
  return 'image/jpeg';
}
