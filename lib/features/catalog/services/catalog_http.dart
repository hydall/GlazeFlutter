import 'dart:convert';

import 'package:dio/dio.dart';

const _timeout = Duration(seconds: 20);

final _dio = Dio(BaseOptions(
  connectTimeout: _timeout,
  receiveTimeout: _timeout,
  responseType: ResponseType.plain,
));

Future<Map<String, dynamic>> catalogGet(
  String url,
  Map<String, String> headers,
) async {
  final res = await _dio.get<String>(
    url,
    options: Options(headers: headers, responseType: ResponseType.plain),
  );
  if (res.statusCode != null && res.statusCode! >= 400) {
    throw Exception('HTTP ${res.statusCode}');
  }
  return _parseJson(res.data ?? '');
}

Future<String> catalogGetText(
  String url,
  Map<String, String> headers,
) async {
  final res = await _dio.get<String>(
    url,
    options: Options(headers: headers, responseType: ResponseType.plain),
  );
  if (res.statusCode != null && res.statusCode! >= 400) {
    throw Exception('HTTP ${res.statusCode}');
  }
  return res.data ?? '';
}

Future<Map<String, dynamic>> catalogPost(
  String url,
  Map<String, dynamic> body,
  Map<String, String> headers,
) async {
  final allHeaders = {'Content-Type': 'application/json', ...headers};
  final res = await _dio.post<String>(
    url,
    data: jsonEncode(body),
    options: Options(headers: allHeaders, responseType: ResponseType.plain),
  );
  if (res.statusCode != null && res.statusCode! >= 400) {
    throw Exception('HTTP ${res.statusCode}');
  }
  return _parseJson(res.data ?? '');
}

Map<String, dynamic> _parseJson(String text) {
  try {
    return jsonDecode(text) as Map<String, dynamic>;
  } catch (_) {
    throw Exception('Server returned invalid JSON');
  }
}

List<dynamic> _parseJsonList(String text) {
  try {
    return jsonDecode(text) as List<dynamic>;
  } catch (_) {
    throw Exception('Server returned invalid JSON');
  }
}

Future<List<dynamic>> catalogGetList(
  String url,
  Map<String, String> headers,
) async {
  final res = await _dio.get<String>(
    url,
    options: Options(headers: headers, responseType: ResponseType.plain),
  );
  if (res.statusCode != null && res.statusCode! >= 400) {
    throw Exception('HTTP ${res.statusCode}');
  }
  return _parseJsonList(res.data ?? '[]');
}
