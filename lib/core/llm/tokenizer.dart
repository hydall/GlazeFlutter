int estimateTokens(String text) {
  final cleaned = _stripBase64Media(text);
  return (cleaned.length / 3.35).ceil();
}

String _stripBase64Media(String text) {
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
