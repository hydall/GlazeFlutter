import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';

/// Returns a short, human-readable error string.
///
/// DioExceptions are translated to HTTP status codes or network descriptions.
/// API JSON error bodies (OpenAI / Anthropic / Gemini shape) are extracted
/// when available so the user sees "HTTP 401: Invalid API key" instead of
/// the full Dio verbose dump.
String formatError(Object err) {
  if (err is DioException) {
    if (err.type == DioExceptionType.cancel) return 'error_request_cancelled'.tr();

    final response = err.response;
    if (response != null) {
      final code = response.statusCode ?? '?';
      final apiMsg = _extractApiMessage(response.data);
      final fallbackMsg =
          response.statusCode != null ? _defaultHttpMessage(response.statusCode!) : null;
      final message = apiMsg ?? fallbackMsg;
      return message != null ? 'HTTP $code: $message' : 'HTTP $code';
    }

    return switch (err.type) {
      DioExceptionType.connectionTimeout => 'error_connection_timed_out'.tr(),
      DioExceptionType.receiveTimeout => 'error_server_too_long'.tr(),
      DioExceptionType.sendTimeout => 'error_upload_timed_out'.tr(),
      DioExceptionType.connectionError => 'error_connection_failed_check_network'.tr(),
      DioExceptionType.badCertificate => 'error_ssl_certificate'.tr(),
      _ => err.message ?? 'error_request_failed'.tr(),
    };
  }
  return err.toString();
}

String? _defaultHttpMessage(int code) {
  final key = switch (code) {
    400 => 'error_http_400',
    401 => 'error_http_401',
    403 => 'error_http_403',
    404 => 'error_http_404',
    408 => 'error_http_408',
    409 => 'error_http_409',
    413 => 'error_http_413',
    422 => 'error_http_422',
    429 => 'error_http_429',
    500 => 'error_http_500',
    502 => 'error_http_502',
    503 => 'error_http_503',
    504 => 'error_http_504',
    _ => null,
  };
  return key?.tr();
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
