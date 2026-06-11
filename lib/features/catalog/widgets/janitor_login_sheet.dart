import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../../shared/theme/app_colors.dart';
import '../../chat/bridge/chat_webview_environment.dart';
import '../services/janitor_webview_proxy.dart';

/// Opens the JanitorAI login WebView as a modal sheet. After it closes the
/// account session (if any) is active for catalog requests; callers that show a
/// catalog should refresh it afterwards.
Future<void> showJanitorLoginSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const JanitorLoginSheet(),
  );
}

/// Full-height sheet hosting a visible WebView for logging into a JanitorAI
/// account. The WebView shares its cookie jar and `localStorage` with the
/// headless [JanitorWebViewProxy] (same origin, same app storage), so once the
/// user signs in here the account session is automatically used for catalog
/// requests. No cookies are wiped — unlike the CF challenge WebView.
class JanitorLoginSheet extends StatefulWidget {
  const JanitorLoginSheet({super.key});

  static const _loginUrl = 'https://janitorai.com/login';

  @override
  State<JanitorLoginSheet> createState() => _JanitorLoginSheetState();
}

class _JanitorLoginSheetState extends State<JanitorLoginSheet> {
  InAppWebViewController? _controller;
  bool _busy = false;

  /// Guards against re-entrant close attempts: once a successful login lands we
  /// pop exactly once, even if several navigation callbacks fire in a row.
  bool _closing = false;

  Future<void> _logout() async {
    setState(() => _busy = true);
    await JanitorWebViewProxy.instance.logout();
    await _controller?.loadUrl(
      urlRequest: URLRequest(url: WebUri(JanitorLoginSheet._loginUrl)),
    );
    if (mounted) setState(() => _busy = false);
  }

  /// Called on every navigation. JanitorAI redirects away from `/login` (to the
  /// site root) once sign-in succeeds — and the screenshot's success toast lands
  /// on that root page. So whenever we leave the login page for a janitorai.com
  /// URL we verify a session token was actually persisted (creds saved) and, if
  /// so, auto-close the sheet. The token check also prevents false closes when
  /// the user merely navigates to e.g. the sign-up page.
  Future<void> _maybeFinishLogin(WebUri? url) async {
    if (_closing || url == null) return;
    if (!url.host.endsWith('janitorai.com')) return;
    if (url.path.startsWith('/login')) return;
    final controller = _controller;
    if (controller == null) return;
    final loggedIn = await JanitorWebViewProxy.hasSessionToken(controller);
    if (!loggedIn || _closing || !mounted) return;
    _closing = true;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height * 0.92;
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: context.cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _Header(
            busy: _busy,
            onClose: () => Navigator.of(context).pop(),
            onLogout: _busy ? null : _logout,
          ),
          Expanded(
            child: InAppWebView(
              initialUrlRequest:
                  URLRequest(url: WebUri(JanitorLoginSheet._loginUrl)),
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                domStorageEnabled: true,
                cacheEnabled: true,
                thirdPartyCookiesEnabled: true,
                isInspectable: false,
                useHybridComposition: true,
              ),
              webViewEnvironment:
                  defaultTargetPlatform == TargetPlatform.windows
                      ? chatWebViewEnvironment
                      : null,
              // Claim vertical (and horizontal) drags so the WebView scrolls
              // instead of the enclosing modal sheet eating the gesture.
              gestureRecognizers: {
                Factory<VerticalDragGestureRecognizer>(
                  () => VerticalDragGestureRecognizer(),
                ),
                Factory<HorizontalDragGestureRecognizer>(
                  () => HorizontalDragGestureRecognizer(),
                ),
              },
              onWebViewCreated: (c) => _controller = c,
              // Full page loads / redirects (e.g. the post-login bounce to the
              // site root) — confirm the session and close on success.
              onLoadStop: (_, url) => _maybeFinishLogin(url),
              // JanitorAI is a SPA: a successful login can route client-side
              // without a full reload, so watch history pushes too.
              onUpdateVisitedHistory: (_, url, _) => _maybeFinishLogin(url),
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final bool busy;
  final VoidCallback onClose;
  final VoidCallback? onLogout;

  const _Header({
    required this.busy,
    required this.onClose,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: onClose,
            color: context.cs.onSurface,
          ),
          Expanded(
            child: Text(
              'janitor_auth_title'.tr(),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: context.cs.onSurface,
              ),
            ),
          ),
          if (busy)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            TextButton(
              onPressed: onLogout,
              child: Text(
                'janitor_auth_logout'.tr(),
                style: TextStyle(color: context.cs.error),
              ),
            ),
        ],
      ),
    );
  }
}
