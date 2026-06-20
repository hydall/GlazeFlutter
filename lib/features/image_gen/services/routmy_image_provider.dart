import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'image_gen_http.dart';
import '../image_gen_models.dart';

class RoutmyImageProvider {
  final ImageGenHttp _http = ImageGenHttp();
  final String baseUrl;

  RoutmyImageProvider({this.baseUrl = RoutMyConstants.baseUrl});

  Future<Uint8List> generate({
    required String apiKey,
    required String model,
    required String prompt,
    required String aspectRatio,
    required String imageSize,
    required String quality,
    List<String>? referenceImages,
    CancelToken? cancelToken,
  }) async {
    final isChatModel = RoutMyConstants.chatImageModels.contains(model);
    final hasRefs = referenceImages != null && referenceImages.isNotEmpty;
    // For non-chat (OpenAI-style) models, reference images are only honored by
    // the edits endpoint (/v1/images/edits with an `images` array). The plain
    // /v1/images/generations endpoint ignores reference input, so route to
    // edits whenever references are present. See https://docs.rout.my/api/images
    final endpoint = isChatModel
        ? '/v1/chat/completions'
        : (hasRefs ? '/v1/images/edits' : '/v1/images/generations');
    final fullUrl = '$baseUrl$endpoint';
    debugPrint('ROUTMY: url=$fullUrl model=$model apiKey=${apiKey.length > 8 ? "${apiKey.substring(0, 4)}...${apiKey.substring(apiKey.length - 4)}" : "SHORT"} refs=${referenceImages?.length ?? 0}');

    if (isChatModel) {
      return _generateChat(
        apiKey: apiKey,
        model: model,
        prompt: prompt,
        aspectRatio: aspectRatio,
        imageSize: imageSize,
        quality: quality,
        referenceImages: referenceImages,
        cancelToken: cancelToken,
      );
    }
    if (hasRefs) {
      return _editImages(
        apiKey: apiKey,
        model: model,
        prompt: prompt,
        aspectRatio: aspectRatio,
        imageSize: imageSize,
        quality: quality,
        referenceImages: referenceImages,
        cancelToken: cancelToken,
      );
    }
    return _generateImages(
      apiKey: apiKey,
      model: model,
      prompt: prompt,
      aspectRatio: aspectRatio,
      imageSize: imageSize,
      quality: quality,
      referenceImages: null,
      cancelToken: cancelToken,
    );
  }

  Future<Uint8List> _generateImages({
    required String apiKey,
    required String model,
    required String prompt,
    required String aspectRatio,
    required String imageSize,
    required String quality,
    List<String>? referenceImages,
    CancelToken? cancelToken,
  }) async {
    final url = '$baseUrl/v1/images/generations';

    final body = <String, dynamic>{
      'model': model,
      'prompt': prompt,
      'n': 1,
      'image_config': {
        'aspect_ratio': aspectRatio,
        'image_size': imageSize,
        if (quality.isNotEmpty) 'quality': quality,
      },
    };

    final b64 = await _http.postAndExtractBase64(
      url: url,
      apiKey: apiKey,
      body: body,
      cancelToken: cancelToken,
      extractBase64: _extractImageBase64,
    );
    return ImageGenHttp.base64ToBytes(b64);
  }

  /// OpenAI-style image edits (`/v1/images/edits`) sent as multipart/form-data.
  /// JSON body with `images` array was rejected (400) by the upstream provider;
  /// multipart with binary `image` fields is the canonical OpenAI edits format.
  Future<Uint8List> _editImages({
    required String apiKey,
    required String model,
    required String prompt,
    required String aspectRatio,
    required String imageSize,
    required String quality,
    required List<String> referenceImages,
    CancelToken? cancelToken,
  }) async {
    final url = '$baseUrl/v1/images/edits';

    final fields = <String, String>{
      'model': model,
      'prompt': prompt,
      'n': '1',
    };

    // image_config as individual fields (multipart form does not accept nested objects)
    fields['image_config[aspect_ratio]'] = aspectRatio;
    fields['image_config[image_size]'] = imageSize;
    if (quality.isNotEmpty) fields['image_config[quality]'] = quality;

    final imageFields = <(String, Uint8List, String, String)>[];
    for (final ref in referenceImages.where((s) => s.isNotEmpty)) {
      final bytes = _refToBytes(ref);
      if (bytes == null) continue;
      final mime = _sniffMime(ref);
      final ext = mime.split('/').last;
      imageFields.add(('image', bytes, 'ref.$ext', mime));
    }

    final json = await _http.postMultipart(
      url: url,
      fields: fields,
      imageFields: imageFields,
      apiKey: apiKey,
      cancelToken: cancelToken,
    );
    return ImageGenHttp.base64ToBytes(_extractImageBase64(json));
  }

  /// Converts a reference (bare base64 or data-URL) to raw bytes.
  Uint8List? _refToBytes(String s) {
    try {
      if (s.startsWith('data:')) {
        final commaIdx = s.indexOf(',');
        if (commaIdx == -1) return null;
        return base64Decode(s.substring(commaIdx + 1));
      }
      if (s.startsWith('http://') || s.startsWith('https://')) {
        // HTTP refs not supported for multipart — skip
        return null;
      }
      return base64Decode(s);
    } catch (_) {
      return null;
    }
  }

  /// Reference images arrive as bare base64 (from ImageGenService._fileToBase64)
  /// or already as data/https URLs. rout.my expects a full data URL (or https)
  /// in `image_url`, so wrap bare base64 and sniff the MIME from its signature.
  /// Without this, every avatar/context reference was silently dropped.
  String _asDataUrl(String s) {
    if (s.isEmpty) return s;
    if (s.startsWith('data:') || s.startsWith('http://') || s.startsWith('https://')) {
      return s;
    }
    return 'data:${_sniffMime(s)};base64,$s';
  }

  String _sniffMime(String b64) {
    if (b64.startsWith('/9j/')) return 'image/jpeg';
    if (b64.startsWith('iVBORw0KGgo')) return 'image/png';
    if (b64.startsWith('UklGR')) return 'image/webp';
    if (b64.startsWith('R0lGOD')) return 'image/gif';
    return 'image/png';
  }

  String _extractImageBase64(Map<String, dynamic> json) {
    final data = json['data'] as List?;
    if (data == null || data.isEmpty) {
      throw Exception('No image data in response');
    }
    final imageObj = data.first as Map<String, dynamic>;
    final b64 = imageObj['b64_json'] as String?;
    if (b64 != null && b64.isNotEmpty) return b64;
    final imgUrl = imageObj['url'] as String?;
    if (imgUrl != null && imgUrl.startsWith('data:')) {
      final commaIdx = imgUrl.indexOf(',');
      if (commaIdx != -1) return imgUrl.substring(commaIdx + 1);
    }
    if (imgUrl != null) {
      throw Exception('URL response — need to download');
    }
    throw Exception('No image in response');
  }

  Future<Uint8List> _generateChat({
    required String apiKey,
    required String model,
    required String prompt,
    required String aspectRatio,
    required String imageSize,
    required String quality,
    List<String>? referenceImages,
    CancelToken? cancelToken,
  }) async {
    final url = '$baseUrl/v1/chat/completions';

    final content = <Map<String, dynamic>>[];

    if (referenceImages != null) {
      for (final ref in referenceImages) {
        if (ref.isEmpty) continue;
        content.add({
          'type': 'image_url',
          'image_url': {'url': _asDataUrl(ref)},
        });
      }
    }
    content.add({'type': 'text', 'text': prompt});

    final body = <String, dynamic>{
      'model': model,
      'messages': [
        {'role': 'user', 'content': content},
      ],
      'modalities': ['image', 'text'],
      'image_config': {
        'aspect_ratio': aspectRatio,
        'image_size': imageSize,
        if (quality.isNotEmpty) 'quality': quality,
      },
    };

    final response = await _http.post(
      url: url,
      apiKey: apiKey,
      body: body,
      cancelToken: cancelToken,
    );

    final choices = response['choices'] as List?;
    if (choices == null || choices.isEmpty) throw Exception('No response from rout.my');
    final message = choices.first['message'] as Map<String, dynamic>?;
    if (message == null) throw Exception('No message in rout.my response');

    final images = message['images'] as List?;
    if (images != null && images.isNotEmpty) {
      final imgUrl = images.first['image_url']?['url'] as String?;
      if (imgUrl != null) {
        return _downloadImage(imgUrl, cancelToken: cancelToken);
      }
    }

    final msgContent = message['content'];
    if (msgContent is List) {
      for (final part in msgContent) {
        if (part is Map<String, dynamic> &&
            part['type'] == 'image_url' &&
            part['image_url']?['url'] != null) {
          return _downloadImage(part['image_url']['url'] as String, cancelToken: cancelToken);
        }
      }
    }

    throw Exception('No image in rout.my response');
  }

  Future<Uint8List> _downloadImage(String url, {CancelToken? cancelToken}) async {
    if (url.startsWith('data:')) {
      final commaIdx = url.indexOf(',');
      if (commaIdx == -1) throw Exception('Invalid data URL');
      final b64 = url.substring(commaIdx + 1);
      return ImageGenHttp.base64ToBytes(b64);
    }
    final response = await _http.getRaw(url, cancelToken: cancelToken);
    return response.data!;
  }
}
