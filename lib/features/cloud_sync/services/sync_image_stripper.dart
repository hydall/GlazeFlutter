import 'package:glaze_flutter/core/constants/image_gen_patterns.dart';

final _imgResultRegex = ImgGenPatterns.imgResultStripRegex;
final _imgErrorRegex = ImgGenPatterns.imgErrorStripRegex;
final _imgGenRegex = ImgGenPatterns.imgGenStripRegex;
final _base64DataUrlRegex = ImgGenPatterns.base64DataUrlRegex;
final _imgTagRegex = ImgGenPatterns.imgTagDataSrcRegex;

/// Strips inline image tags and base64 data URLs from a chat session JSON
/// before it is uploaded to cloud sync. Image payloads are large and
/// device-specific (saved to local disk paths), so they must not be synced.
Map<String, dynamic> stripImagesFromSession(Map<String, dynamic> json) {
  final messages = json['messages'];
  if (messages is! List) return json;
  final stripped = messages.map((m) {
    if (m is! Map<String, dynamic>) return m;
    var modified = false;
    final content = m['content'];
    String? cleanedContent;
    if (content is String && content.length >= 10) {
      cleanedContent = stripImageContent(content);
      if (!identical(cleanedContent, content)) modified = true;
    }
    List<dynamic>? cleanedSwipes;
    final swipes = m['swipes'];
    if (swipes is List && swipes.isNotEmpty) {
      cleanedSwipes = swipes.map((s) {
        if (s is String && s.length >= 10) {
          final c = stripImageContent(s);
          if (!identical(c, s)) modified = true;
          return c;
        }
        return s;
      }).toList();
    }
    if (!modified) return m;
    final result = <String, dynamic>{...m};
    if (cleanedContent != null) result['content'] = cleanedContent;
    if (cleanedSwipes != null) result['swipes'] = cleanedSwipes;
    return result;
  }).toList();
  return {...json, 'messages': stripped};
}

String stripImageContent(String text) {
  var result = text;
  result = result.replaceAll(_imgResultRegex, '');
  result = result.replaceAll(_imgErrorRegex, '');
  result = result.replaceAll(_imgGenRegex, '');
  result = result.replaceAll(_imgTagRegex, '');
  result = result.replaceAll(_base64DataUrlRegex, '');
  return result;
}
