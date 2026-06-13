import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../cloud_adapter.dart';
import 'dropbox_auth.dart';

class DropboxAdapter implements CloudAdapter {
  static const _apiBase = 'https://api.dropboxapi.com/2';
  static const _contentBase = 'https://content.dropboxapi.com/2';
  static const _appFolderPrefix = '/Glaze';
  static const _deleteBatchPolls = 30;

  final DropboxAuth _auth;
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 120),
    ),
  );

  final Set<String> _ensuredFolders = {};

  DropboxAdapter(this._auth);

  String _stripPrefix(String path) {
    if (path.startsWith(_appFolderPrefix)) {
      return path.substring(_appFolderPrefix.length);
    }
    return path;
  }

  Future<Map<String, String>> _headers() async {
    final token = await _auth.getValidToken();
    return {'Authorization': 'Bearer $token'};
  }

  Future<T> _apiCall<T>(
    String endpoint,
    Map<String, dynamic> body, {
    T Function(Map<String, dynamic>)? fromJson,
  }) async {
    final headers = await _headers();
    headers['Content-Type'] = 'application/json';
    final response = await _dio.post<Map<String, dynamic>>(
      '$_apiBase$endpoint',
      data: jsonEncode(body),
      options: Options(headers: headers),
    );
    if (fromJson != null && response.data != null) {
      return fromJson(response.data!);
    }
    return response.data as T;
  }

  Future<T> _retryOn401<T>(Future<T> Function() fn) async {
    try {
      return await fn();
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        await _auth.getValidToken();
        return await fn();
      }
      rethrow;
    }
  }

  @override
  Future<bool> isConnected() =>
      _auth.isConnected ? Future.value(true) : Future.value(false);

  @override
  Future<void> ensureFolder(String path) async {
    final stripped = _stripPrefix(path);
    if (_ensuredFolders.contains(stripped)) return;

    final parts = stripped.split('/').where((s) => s.isNotEmpty).toList();
    var current = '';
    for (final part in parts) {
      current += '/$part';
      if (_ensuredFolders.contains(current)) continue;
      try {
        await _retryOn401(
          () => _apiCall<dynamic>('/files/create_folder_v2', {'path': current}),
        );
      } on DioException catch (e) {
        if (e.response?.statusCode != 409) rethrow;
      }
      _ensuredFolders.add(current);
    }
  }

  @override
  Future<void> upload(String path, String data) async {
    await _retryOn401(() async {
      final headers = await _headers();
      headers['Content-Type'] = 'application/octet-stream';
      headers['Dropbox-API-Arg'] = jsonEncode({
        'path': _stripPrefix(path),
        'mode': 'overwrite',
        'autorename': false,
        'mute': true,
      });
      await _dio.post<void>(
        '$_contentBase/files/upload',
        data: data,
        options: Options(headers: headers),
      );
    });
  }

  @override
  Future<void> uploadBinary(String path, Uint8List data) async {
    await _retryOn401(() async {
      final headers = await _headers();
      headers['Content-Type'] = 'application/octet-stream';
      headers['Dropbox-API-Arg'] = jsonEncode({
        'path': _stripPrefix(path),
        'mode': 'overwrite',
        'autorename': false,
        'mute': true,
      });
      await _dio.post<void>(
        '$_contentBase/files/upload',
        data: Stream.fromIterable([data]),
        options: Options(
          headers: headers,
          contentType: 'application/octet-stream',
        ),
      );
    });
  }

  @override
  Future<String> download(String path) async {
    return _retryOn401(() async {
      final headers = await _headers();
      headers['Dropbox-API-Arg'] = jsonEncode({'path': _stripPrefix(path)});
      final response = await _dio.post<String>(
        '$_contentBase/files/download',
        options: Options(headers: headers, responseType: ResponseType.plain),
      );
      return response.data ?? '';
    });
  }

  @override
  Future<Uint8List> downloadBinary(String path) async {
    return _retryOn401(() async {
      final headers = await _headers();
      headers['Dropbox-API-Arg'] = jsonEncode({'path': _stripPrefix(path)});
      final response = await _dio.post<List<int>>(
        '$_contentBase/files/download',
        options: Options(headers: headers, responseType: ResponseType.bytes),
      );
      return Uint8List.fromList(response.data ?? []);
    });
  }

  @override
  Future<void> deleteFile(String path) async {
    await _retryOn401(
      () => _apiCall<dynamic>('/files/delete_v2', {'path': _stripPrefix(path)}),
    );
  }

  @override
  Future<void> deleteFolder(String path) async {
    final stripped = _stripPrefix(path);
    if (stripped.isEmpty) {
      await _retryOn401(() => _deleteAllInRoot());
      _ensuredFolders.clear();
      return;
    }
    await _retryOn401(
      () => _apiCall<dynamic>('/files/delete_v2', {'path': stripped}),
    );
    _ensuredFolders.remove(stripped);
  }

  Future<void> _deleteAllInRoot() async {
    final entries = <Map<String, dynamic>>[];
    var result = await _apiCall<Map<String, dynamic>>('/files/list_folder', {
      'path': '',
      'recursive': true,
    });
    entries.addAll(
      (result['entries'] as List? ?? []).cast<Map<String, dynamic>>(),
    );

    var hasMore = result['has_more'] as bool? ?? false;
    while (hasMore) {
      result = await _apiCall<Map<String, dynamic>>(
        '/files/list_folder/continue',
        {'cursor': result['cursor']},
      );
      entries.addAll(
        (result['entries'] as List? ?? []).cast<Map<String, dynamic>>(),
      );
      hasMore = result['has_more'] as bool? ?? false;
    }

    if (entries.isEmpty) return;

    try {
      final result = await _apiCall<Map<String, dynamic>>(
        '/files/delete_batch',
        {
          'entries': entries
              .map((e) => {'path': e['path_lower'] ?? e['path_display']})
              .toList(),
        },
      );
      await _waitForDeleteBatch(result);
    } catch (_) {
      for (final entry in entries) {
        try {
          await _apiCall<dynamic>('/files/delete_v2', {
            'path': entry['path_lower'] ?? entry['path_display'],
          });
        } catch (_) {}
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
    }
  }

  Future<void> _waitForDeleteBatch(Map<String, dynamic> result) async {
    var tag = result['.tag'] as String?;
    var asyncJobId = result['async_job_id'] as String?;

    for (
      var i = 0;
      tag == 'async_job_id' && asyncJobId != null && i < _deleteBatchPolls;
      i++
    ) {
      await Future<void>.delayed(const Duration(seconds: 1));
      final check = await _apiCall<Map<String, dynamic>>(
        '/files/delete_batch/check',
        {'async_job_id': asyncJobId},
      );
      tag = check['.tag'] as String?;
      if (tag == 'complete') return;
      if (tag == 'failed') {
        throw Exception('Dropbox delete_batch failed: $check');
      }
    }

    if (tag == 'async_job_id') {
      throw Exception('Dropbox delete_batch did not complete in time');
    }
    if (tag == 'failed') {
      throw Exception('Dropbox delete_batch failed: $result');
    }
  }

  @override
  Future<List<CloudFileInfo>> listFolder(String path) async {
    return _retryOn401(() async {
      final result = <CloudFileInfo>[];
      var response = await _apiCall<Map<String, dynamic>>(
        '/files/list_folder',
        {'path': _stripPrefix(path), 'recursive': false},
      );
      result.addAll(_parseEntries(response['entries'] as List? ?? []));

      var hasMore = response['has_more'] as bool? ?? false;
      while (hasMore) {
        response = await _apiCall<Map<String, dynamic>>(
          '/files/list_folder/continue',
          {'cursor': response['cursor']},
        );
        result.addAll(_parseEntries(response['entries'] as List? ?? []));
        hasMore = response['has_more'] as bool? ?? false;
      }
      return result;
    });
  }

  List<CloudFileInfo> _parseEntries(List<Object?> entries) {
    return entries
        .whereType<Map<String, dynamic>>()
        .map(
          (e) => CloudFileInfo(
            path: e['path_display'] as String? ?? '',
            name: e['name'] as String? ?? '',
            isFolder: e['.tag'] == 'folder',
          ),
        )
        .toList();
  }

  @override
  Future<Map<String, dynamic>?> getAccountInfo() async {
    try {
      final result = await _apiCall<Map<String, dynamic>>(
        '/users/get_current_account',
        {},
      );
      return {
        'name': result['name']?['display_name'],
        'email': result['email'],
        'account_id': result['account_id'],
      };
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> invalidateFolderCache() {
    _ensuredFolders.clear();
    return Future.value();
  }
}
