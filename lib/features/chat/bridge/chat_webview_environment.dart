import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../../core/utils/platform_paths.dart';
import 'chat_webview_settings.dart';

WebViewEnvironment? _chatWebViewEnvironment;
HttpServer? _chatWebViewAssetServer;
WebUri? _chatWebViewAssetBaseUrl;

/// Shared WebView2 environment for Windows chat/headless WebViews.
///
/// The Windows implementation of `flutter_inappwebview` expects WebView2 to be
/// initialized before creating WebViews. Mobile platforms do not use this.
WebViewEnvironment? get chatWebViewEnvironment => _chatWebViewEnvironment;

String? chatWebViewInitialFile() {
  if (_chatWebViewAssetBaseUrl != null) return null;
  if (chatWebViewUsesAndroidAssetLoader()) return null;
  return 'assets/chat_webview/index.html';
}

URLRequest? chatWebViewInitialUrlRequest() {
  final baseUrl = _chatWebViewAssetBaseUrl;
  if (baseUrl != null) {
    return URLRequest(url: WebUri.uri(baseUrl.uriValue.resolve('index.html')));
  }
  final androidUrl = chatWebViewAndroidAssetUrl();
  if (androidUrl != null) {
    return URLRequest(url: WebUri(androidUrl));
  }
  return null;
}

String? chatWebViewResolveLocalFileUrl(String? source) {
  if (source == null || source.isEmpty) return source;
  if (source.startsWith('data:') ||
      source.startsWith('http://') ||
      source.startsWith('https://')) {
    return source;
  }

  final path = _sourceToFilePath(source);
  if (path == null) return source;
  final filePath = chatWebViewUsesAndroidAssetLoader()
      ? path
      : File(path).absolute.path;
  if (!_isInsideGlazeData(filePath)) {
    return source;
  }

  final androidUrl = _androidLocalFileUrl(filePath);
  if (androidUrl != null) return androidUrl;

  final baseUrl = _chatWebViewAssetBaseUrl;
  if (baseUrl == null) return source;

  final url = baseUrl.uriValue.replace(
    path: '/__glaze_file__',
    queryParameters: {'path': filePath},
  );
  return url.toString();
}

Future<void> initChatWebViewEnvironment() async {
  if (kIsWeb) return;
  if (defaultTargetPlatform == TargetPlatform.android) {
    setChatWebViewAndroidFileRoot(await getAppDataDir());
    return;
  }
  if (defaultTargetPlatform != TargetPlatform.windows) return;
  if (_chatWebViewEnvironment != null) return;

  try {
    final availableVersion = await WebViewEnvironment.getAvailableVersion();
    if (availableVersion == null) {
      return;
    }

    _chatWebViewEnvironment = await WebViewEnvironment.create();
    await _startChatWebViewAssetServer();
  } catch (_) {}
}

Future<void> _startChatWebViewAssetServer() async {
  if (_chatWebViewAssetServer != null) return;

  final assetDir = _chatWebViewAssetDirectory();
  if (!assetDir.existsSync()) {
    return;
  }

  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  _chatWebViewAssetServer = server;
  _chatWebViewAssetBaseUrl = WebUri('http://127.0.0.1:${server.port}/');
  unawaited(_serveChatWebViewAssets(server, assetDir));
}

Directory _chatWebViewAssetDirectory() {
  final exeDir = File(Platform.resolvedExecutable).parent.path;
  final separator = Platform.pathSeparator;
  return Directory(
    [
      exeDir,
      'data',
      'flutter_assets',
      'assets',
      'chat_webview',
    ].join(separator),
  );
}

Future<void> _serveChatWebViewAssets(HttpServer server, Directory root) async {
  await for (final request in server) {
    try {
      if (request.uri.path == '/__glaze_file__') {
        await _serveGlazeDataFile(request);
        continue;
      }

      final path = _safeAssetPath(request.uri.path);
      if (path == null) {
        request.response.statusCode = HttpStatus.forbidden;
        await request.response.close();
        continue;
      }

      final file = File('${root.path}${Platform.pathSeparator}$path');
      if (!file.existsSync()) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        continue;
      }

      request.response.headers.contentType = _contentTypeFor(path);
      await request.response.addStream(file.openRead());
      await request.response.close();
    } catch (_) {
      request.response.statusCode = HttpStatus.internalServerError;
      await request.response.close();
    }
  }
}

Future<void> _serveGlazeDataFile(HttpRequest request) async {
  final path = request.uri.queryParameters['path'];
  if (path == null || !_isInsideGlazeData(path)) {
    request.response.statusCode = HttpStatus.forbidden;
    await request.response.close();
    return;
  }

  final file = File(path).absolute;
  if (!file.existsSync()) {
    request.response.statusCode = HttpStatus.notFound;
    await request.response.close();
    return;
  }

  request.response.headers.contentType = _contentTypeFor(file.path);
  await request.response.addStream(file.openRead());
  await request.response.close();
}

String? _androidLocalFileUrl(String path) {
  if (!chatWebViewUsesAndroidAssetLoader()) return null;
  final root = chatWebViewAndroidFileRoot;
  if (root == null || root.isEmpty) return null;

  final rootDir = _normalizeAndroidPath(root);
  final rootPrefix = rootDir.endsWith('/') ? rootDir : '$rootDir/';
  final filePath = _normalizeAndroidPath(path);
  if (!filePath.startsWith(rootPrefix)) return null;

  final relativePath = filePath.substring(rootPrefix.length).split('/');
  return Uri.https(
    kChatWebViewAndroidAssetDomain,
    '$kChatWebViewAndroidFilePath${relativePath.join('/')}',
  ).toString();
}

String _normalizeAndroidPath(String path) => path.replaceAll('\\', '/');

String? _sourceToFilePath(String source) {
  if (source.startsWith('file://')) {
    try {
      return Uri.parse(source).toFilePath(windows: Platform.isWindows);
    } catch (_) {
      return source.replaceFirst('file:///', '').replaceFirst('file://', '');
    }
  }
  if (source.startsWith('/') || RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(source)) {
    return source;
  }
  return null;
}

bool _isInsideGlazeData(String path) {
  if (chatWebViewUsesAndroidAssetLoader()) {
    final root = chatWebViewAndroidFileRoot;
    if (root == null || root.isEmpty) return false;
    final rootDir = _normalizeAndroidPath(root);
    final rootPrefix = rootDir.endsWith('/') ? rootDir : '$rootDir/';
    return _normalizeAndroidPath(path).startsWith(rootPrefix);
  }

  final root = _glazeDataDirectory().absolute.path;
  final file = File(path).absolute.path;
  final rootPrefix = root.endsWith(Platform.pathSeparator)
      ? root
      : '$root${Platform.pathSeparator}';
  if (Platform.isWindows) {
    return file.toLowerCase().startsWith(rootPrefix.toLowerCase());
  }
  return file.startsWith(rootPrefix);
}

Directory _glazeDataDirectory() {
  if (Platform.isAndroid) {
    final root = chatWebViewAndroidFileRoot;
    if (root != null && root.isNotEmpty) return Directory(root);
  }
  if (Platform.isWindows) {
    final appData = Platform.environment['APPDATA'];
    if (appData != null && appData.isNotEmpty) {
      return Directory('$appData${Platform.pathSeparator}Glaze');
    }
  }
  return Directory.current;
}

String? _safeAssetPath(String rawPath) {
  var path = Uri.decodeComponent(rawPath);
  if (path == '/' || path.isEmpty) return 'index.html';
  if (path.startsWith('/')) path = path.substring(1);
  path = path.replaceAll('/', Platform.pathSeparator);
  final segments = path.split(Platform.pathSeparator);
  if (segments.any((segment) => segment == '..' || segment.isEmpty)) {
    return null;
  }
  return path;
}

ContentType _contentTypeFor(String path) {
  final lower = path.toLowerCase();
  if (lower.endsWith('.html')) return ContentType.html;
  if (lower.endsWith('.js')) {
    return ContentType('application', 'javascript', charset: 'utf-8');
  }
  if (lower.endsWith('.css')) {
    return ContentType('text', 'css', charset: 'utf-8');
  }
  if (lower.endsWith('.svg')) return ContentType('image', 'svg+xml');
  if (lower.endsWith('.png')) return ContentType('image', 'png');
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
    return ContentType('image', 'jpeg');
  }
  return ContentType.binary;
}
