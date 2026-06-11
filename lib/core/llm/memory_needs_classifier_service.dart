import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../models/memory_book.dart';
import 'memory_classifier_schema.dart';

typedef MemoryClassifierTextClient =
    Future<String> Function(
      MemoryClassifierRequest request,
      CancelToken cancelToken,
    );

class MemoryClassifierRequest {
  final MemoryBookSettings settings;
  final String currentText;
  final List<String> candidateTitles;
  final List<String> missingContextReasons;

  const MemoryClassifierRequest({
    required this.settings,
    required this.currentText,
    this.candidateTitles = const [],
    this.missingContextReasons = const [],
  });
}

class MemoryClassifierResult {
  final MemoryClassifierOutput? output;
  final String status;
  final String? error;

  const MemoryClassifierResult({required this.status, this.output, this.error});

  bool get usedModel => status == 'ok';

  static const disabled = MemoryClassifierResult(status: 'disabled');
  static const aborted = MemoryClassifierResult(status: 'aborted');
  static const timeout = MemoryClassifierResult(status: 'timeout');
}

class MemoryNeedsClassifierService {
  final MemoryClassifierTextClient _client;

  const MemoryNeedsClassifierService(this._client);

  Future<MemoryClassifierResult> classify(
    MemoryClassifierRequest request, {
    CancelToken? cancelToken,
  }) async {
    if (!request.settings.classifierEnabled) {
      return MemoryClassifierResult.disabled;
    }
    final token = cancelToken ?? CancelToken();
    if (token.isCancelled) return MemoryClassifierResult.aborted;

    try {
      final raw = await _client(request, token).timeout(
        Duration(milliseconds: request.settings.classifierTimeoutMs),
        onTimeout: () => throw TimeoutException('memory classifier timed out'),
      );
      if (token.isCancelled) return MemoryClassifierResult.aborted;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return const MemoryClassifierResult(
          status: 'invalid_output',
          error: 'classifier output was not an object',
        );
      }
      return MemoryClassifierResult(
        status: 'ok',
        output: MemoryClassifierOutput.fromJson(decoded),
      );
    } on TimeoutException {
      if (token.isCancelled) return MemoryClassifierResult.aborted;
      return MemoryClassifierResult.timeout;
    } catch (e) {
      if (token.isCancelled || (e is DioException && CancelToken.isCancel(e))) {
        return MemoryClassifierResult.aborted;
      }
      return MemoryClassifierResult(status: 'invalid_output', error: '$e');
    }
  }
}
