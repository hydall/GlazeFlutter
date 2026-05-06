import 'dart:typed_data';

import 'image_gen_http.dart';

class RoutmyImageProvider {
  final ImageGenHttp _http = ImageGenHttp();

  Future<Uint8List> generate({
    required String apiKey,
    required String model,
    required String prompt,
    required String aspectRatio,
    required String imageSize,
    required String quality,
    List<Map<String, String>>? references,
  }) async {
    final body = <String, dynamic>{
      'model': model,
      'prompt': prompt,
      'aspect_ratio': aspectRatio,
      'image_size': imageSize,
      'quality': quality,
    };
    if (references != null && references.isNotEmpty) {
      body['references'] = references;
    }

    final b64 = await _http.postAndExtractBase64(
      url: 'https://rout.my/img/generate',
      apiKey: apiKey,
      body: body,
      extractBase64: (json) {
        final image = json['image'] as String?;
        if (image == null || image.isEmpty) throw Exception('No image in response');
        return image;
      },
    );
    return ImageGenHttp.base64ToBytes(b64);
  }

  Future<String> runRuBridge({
    required String llmEndpoint,
    required String llmApiKey,
    required String llmModel,
    required String conversationContext,
  }) async {
    String url = llmEndpoint;
    if (!url.contains('/v1')) {
      url = '$url/v1/chat/completions';
    }

    final response = await _http.post(
      url: url,
      apiKey: llmApiKey,
      body: {
        'model': llmModel,
        'messages': [
          {
            'role': 'system',
            'content': 'You are a visual description assistant. Describe the scene for image generation. Output only the visual description.',
          },
          {'role': 'user', 'content': conversationContext},
        ],
        'max_tokens': 300,
        'temperature': 0.8,
      },
    );

    final choices = response['choices'] as List?;
    if (choices == null || choices.isEmpty) throw Exception('No response from RU Bridge');
    final message = (choices.first as Map<String, dynamic>)['message'] as Map<String, dynamic>?;
    return message?['content'] as String? ?? '';
  }
}
