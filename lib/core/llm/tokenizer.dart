import 'package:tiktoken/tiktoken.dart';

Tiktoken? _encoder;

Tiktoken _getEncoder() {
  if (_encoder != null) return _encoder!;
  _encoder = getEncoding('cl100k_base');
  return _encoder!;
}

int estimateTokens(String text) {
  if (text.isEmpty) return 0;
  final cleaned = _stripBase64Media(text);
  try {
    return _getEncoder().encode(cleaned, disallowedSpecial: SpecialTokensSet.empty()).length;
  } catch (_) {
    return (cleaned.length / 3.35).ceil();
  }
}

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
