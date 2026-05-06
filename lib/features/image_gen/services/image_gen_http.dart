import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

class ImageGenHttp {
  final Dio _dio;

  ImageGenHttp() : _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 60),
    receiveTimeout: const Duration(seconds: 120),
  ));

  Future<Map<String, dynamic>> post({
    required String url,
    required Map<String, dynamic> body,
    String? apiKey,
    Map<String, String>? extraHeaders,
  }) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (apiKey != null && apiKey.isNotEmpty)
        'Authorization': 'Bearer $apiKey',
      ...?extraHeaders,
    };
    final response = await _dio.post<Map<String, dynamic>>(
      url,
      data: body,
      options: Options(headers: headers),
    );
    return response.data ?? {};
  }

  Future<String> postAndExtractBase64({
    required String url,
    required Map<String, dynamic> body,
    String? apiKey,
    Map<String, String>? extraHeaders,
    required String Function(Map<String, dynamic>) extractBase64,
  }) async {
    final json = await post(url: url, body: body, apiKey: apiKey, extraHeaders: extraHeaders);
    final b64 = extractBase64(json);
    return b64;
  }

  static Uint8List base64ToBytes(String b64) {
    return base64Decode(b64);
  }

  static String bytesToDataUrl(Uint8List bytes, {String mime = 'image/png'}) {
    return 'data:$mime;base64,${base64Encode(bytes)}';
  }
}
