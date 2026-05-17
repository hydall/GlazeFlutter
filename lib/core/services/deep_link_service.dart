import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

class DeepLinkService {
  DeepLinkService._();
  static final DeepLinkService instance = DeepLinkService._();

  final Map<String, Completer<Uri>> _pendingOAuth = {};
  late final AppLinks _appLinks;
  StreamSubscription<Uri>? _subscription;

  Future<void> init() async {
    _appLinks = AppLinks();

    try {
      final initialLink = await _appLinks.getInitialLink();
      if (initialLink != null) _handleDeepLink(initialLink);
    } catch (_) {}

    _subscription = _appLinks.uriLinkStream.listen(
      _handleDeepLink,
      onError: (e) => debugPrint('DeepLinkService: error: $e'),
    );
  }

  void _handleDeepLink(Uri uri) {
    debugPrint('DeepLinkService: received $uri');
    final path = uri.path;
    if (path.startsWith('/oauth/')) {
      final provider = path.replaceFirst('/oauth/', '');
      final completer = _pendingOAuth.remove(provider);
      if (completer != null && !completer.isCompleted) {
        completer.complete(uri);
      }
      return;
    }
    if (uri.scheme.startsWith('db-') && path == '/auth') {
      final completer = _pendingOAuth.remove('dropbox');
      if (completer != null && !completer.isCompleted) {
        completer.complete(uri);
      }
      return;
    }
    final host = uri.host;
    if (host.contains('googleusercontent')) {
      final completer = _pendingOAuth.remove('gdrive');
      if (completer != null && !completer.isCompleted) {
        completer.complete(uri);
      }
    }
  }

  Future<Uri> waitForOAuthCallback(
    String provider, {
    Duration timeout = const Duration(minutes: 5),
  }) async {
    final completer = Completer<Uri>();
    _pendingOAuth[provider] = completer;
    return completer.future.timeout(timeout, onTimeout: () {
      _pendingOAuth.remove(provider);
      throw TimeoutException('OAuth callback for $provider timed out');
    });
  }

  void cancelOAuth(String provider) {
    final completer = _pendingOAuth.remove(provider);
    if (completer != null && !completer.isCompleted) {
      completer.completeError(StateError('OAuth cancelled'));
    }
  }

  void dispose() {
    _subscription?.cancel();
    for (final completer in _pendingOAuth.values) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('Service disposed'));
      }
    }
    _pendingOAuth.clear();
  }
}
