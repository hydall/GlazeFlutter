import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:tiktoken/tiktoken.dart';

Tiktoken? _encoder;

Tiktoken _getEncoder() {
  if (_encoder != null) return _encoder!;
  _encoder = getEncoding('cl100k_base');
  return _encoder!;
}

final _tokenCache = <String, int>{};
const _maxCacheSize = 2048;

int estimateTokens(String text, {bool useCache = true}) {
  if (text.isEmpty) return 0;
  final cleaned = _stripBase64Media(text);
  if (cleaned.isEmpty) return 0;

  if (useCache) {
    final key = _cacheKey(cleaned);
    final cached = _tokenCache[key];
    if (cached != null) return cached;
    final count = _computeTokens(cleaned);
    if (_tokenCache.length >= _maxCacheSize) _tokenCache.remove(_tokenCache.keys.first);
    _tokenCache[key] = count;
    return count;
  }

  return _computeTokens(cleaned);
}

int _computeTokens(String cleaned) {
  try {
    return _getEncoder().encode(cleaned, disallowedSpecial: SpecialTokensSet.empty()).length;
  } catch (_) {
    return (cleaned.length / 3.35).ceil();
  }
}

String _cacheKey(String text) {
  if (text.length <= 128) return text;
  return md5.convert(utf8.encode(text)).toString();
}

void clearTokenCache() => _tokenCache.clear();

String _stripBase64Media(String text) {
  if (text.length < 256) return text;
  var result = text.replaceAllMapped(
    RegExp(r'<img\s+src="data:image/[^"]{256,}?"\s*/?>'),
    (_) => '',
  );
  result = result.replaceAllMapped(
    RegExp(r'data:image/[^;]+;base64,[A-Za-z0-9+/=]{256,}'),
    (_) => '',
  );
  return result;
}
