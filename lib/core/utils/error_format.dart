import 'package:dio/dio.dart';

/// Returns a short, human-readable error string.
///
/// DioExceptions are translated to HTTP status codes or network descriptions.
/// API JSON error bodies (OpenAI / Anthropic / Gemini shape) are extracted
/// when available so the user sees "HTTP 401: Invalid API key" instead of
/// the full Dio verbose dump.
String formatError(Object err) {
  if (err is DioException) {
    if (err.type == DioExceptionType.cancel) return 'Cancelled';

    final response = err.response;
    if (response != null) {
      final code = response.statusCode ?? '?';
      final apiMsg = _extractApiMessage(response.data);
      return apiMsg != null ? 'HTTP $code: $apiMsg' : 'HTTP $code';
    }

    return switch (err.type) {
      DioExceptionType.connectionTimeout => 'Connection timed out',
      DioExceptionType.receiveTimeout => 'Server took too long to respond',
      DioExceptionType.sendTimeout => 'Upload timed out',
      DioExceptionType.connectionError =>
        'Connection failed — check endpoint and network',
      DioExceptionType.badCertificate => 'SSL certificate error',
      _ => err.message ?? 'Request failed',
    };
  }
  return err.toString();
}

/// Tries to pull a human-readable message out of common API error shapes.
/// Returns null if nothing useful is found.
String? _extractApiMessage(dynamic data) {
  if (data is! Map<String, dynamic>) return null;
  // OpenAI / Anthropic / Gemini: {"error": {"message": "..."}}
  final error = data['error'];
  if (error is Map) {
    final msg = error['message'];
    if (msg is String && msg.isNotEmpty) return msg;
  }
  // Fallback: top-level {"message": "..."}
  final msg = data['message'];
  if (msg is String && msg.isNotEmpty) return msg;
  return null;
}
