import 'dart:convert';
import 'dart:typed_data';

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
    final isChatModel = model.startsWith('google/');
    final endpoint = isChatModel ? '/v1/chat/completions' : '/v1/images/generations';
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
    return _generateImages(
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

    if (referenceImages != null && referenceImages.isNotEmpty) {
      body['image'] = referenceImages.first;
    }

    final b64 = await _http.postAndExtractBase64(
      url: url,
      apiKey: apiKey,
      body: body,
      cancelToken: cancelToken,
      extractBase64: (json) {
        final data = json['data'] as List?;
        if (data == null || data.isEmpty) throw Exception('No image data in response');
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
      },
    );
    return ImageGenHttp.base64ToBytes(b64);
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
      for (final dataUrl in referenceImages) {
        final commaIdx = dataUrl.indexOf(',');
        if (commaIdx == -1) continue;
        final meta = dataUrl.substring(5, commaIdx);
        final mimeType = meta.split(';')[0];
        final base64Data = dataUrl.substring(commaIdx + 1);
        content.add({
          'type': 'image_url',
          'image_url': {'url': 'data:$mimeType;base64,$base64Data'},
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
