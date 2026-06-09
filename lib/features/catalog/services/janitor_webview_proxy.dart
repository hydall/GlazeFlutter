import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../chat/bridge/chat_webview_environment.dart';
import 'cf_challenge_service.dart';

void _log(String m) => debugPrint('[CF-proxy] $m');

/// JS that locates the JanitorAI account access token and returns it (or null).
///
/// JanitorAI uses a Supabase (`@supabase/ssr`) session. The token is stored in
/// **cookies** named `sb-<ref>-auth-token`, split across numbered chunks
/// (`…-auth-token.0`, `.1`, …) whose concatenated value is `base64-<base64 of
/// the session JSON>`. So we: gather the chunks, strip the `base64-` prefix,
/// base64-decode (tolerating base64url), and pull `access_token` out of the
/// JSON. We also fall back to scanning `localStorage` for older/plain layouts.
/// Returns null when logged out (requests stay anonymous).
///
/// Raw string: the regexes use `\d`, `\.` and `$`, which a normal Dart string
/// would mangle. No Dart interpolation is needed here.
const String _findTokenJs = r'''
  const __glazeFindToken = () => {
    const b64decode = (s) => {
      try { return atob(s); } catch (e) {}
      try { return atob(s.replace(/-/g, "+").replace(/_/g, "/")); } catch (e) {}
      return null;
    };
    const extract = (raw) => {
      if (!raw) return null;
      try { raw = decodeURIComponent(raw); } catch (e) {}
      if (raw.indexOf("base64-") === 0) raw = raw.slice(7);
      if (raw.indexOf("eyJ") === 0 && raw.split(".").length === 3) return raw;
      const sources = [b64decode(raw), raw];
      for (let si = 0; si < sources.length; si++) {
        const s = sources[si];
        if (!s) continue;
        const m = s.match(/"access_token":"(eyJ[^"]+)"/);
        if (m) return m[1];
        try {
          const o = JSON.parse(s);
          const c = o && (o.access_token || o.accessToken || o.token ||
            (o.currentSession && o.currentSession.access_token) ||
            (Array.isArray(o) ? o[0] : null));
          if (typeof c === "string" && c.indexOf("eyJ") === 0) return c;
        } catch (e) {}
      }
      return null;
    };
    // 1) Chunked Supabase SSR cookies: sb-<ref>-auth-token(.N)
    try {
      const parts = {};
      const cookies = (document.cookie || "").split("; ");
      for (let i = 0; i < cookies.length; i++) {
        const c = cookies[i];
        const eq = c.indexOf("=");
        if (eq < 0) continue;
        const name = c.slice(0, eq);
        const val = c.slice(eq + 1);
        const m = name.match(/^(sb-.*-auth-token)(?:\.(\d+))?$/);
        if (!m) continue;
        const base = m[1];
        const idx = m[2] ? parseInt(m[2], 10) : 0;
        if (!parts[base]) parts[base] = {};
        parts[base][idx] = val;
      }
      for (const base in parts) {
        const idxs = Object.keys(parts[base]).map(Number).sort((a, b) => a - b);
        let joined = "";
        for (let j = 0; j < idxs.length; j++) joined += parts[base][idxs[j]];
        const t = extract(joined);
        if (t) return t;
      }
    } catch (e) {}
    // 2) localStorage fallback (older / plain layouts)
    try {
      for (let i = 0; i < localStorage.length; i++) {
        const t = extract(localStorage.getItem(localStorage.key(i)));
        if (t) return t;
      }
    } catch (e) {}
    return null;
  };
''';

/// Thrown when the proxy could not obtain a CF-cleared response.
class JanitorCfException implements Exception {
  final int status;
  JanitorCfException(this.status);
  @override
  String toString() => 'JanitorCfException(status=$status)';
}

/// Persistent offscreen WebView that runs janitorai.com API requests from
/// inside a real Chromium session.
///
/// **Why this exists.** Cloudflare binds `cf_clearance` to the TLS/JA3
/// fingerprint of the client that solved the Turnstile challenge. A cookie
/// obtained in a WebView cannot be replayed by Dio — the Dart HTTP stack
/// produces a different TLS handshake, so CF answers 403 even with the exact
/// same cookie + User-Agent. Running `fetch()` *inside* the page keeps the same
/// fingerprint and cookie jar, so the request passes.
///
/// **Turnstile.** The non-interactive (managed) challenge janitorai.com serves
/// is solved transparently just by loading the page — no user interaction. If CF
/// escalates to an interactive challenge, [_escalateToVisible] surfaces the
/// existing visible WebView ([CfChallengeService] / `_CfChallengeWebView`) for
/// the user to solve once; the offscreen session is then reused.
class JanitorWebViewProxy {
  JanitorWebViewProxy._();
  static final JanitorWebViewProxy instance = JanitorWebViewProxy._();

  static final WebUri _origin = WebUri('https://janitorai.com');

  HeadlessInAppWebView? _webView;
  InAppWebViewController? _controller;
  Completer<void>? _starting;

  /// Completes on the next `onLoadStop` for a janitorai.com page. Reset before
  /// every navigation so we can await the document actually being loaded —
  /// `callAsyncJavaScript` hangs forever if invoked while the page is still
  /// `about:blank`, so we must never fetch before a real load lands.
  Completer<void>? _loadStop;

  /// Serializes navigations / solves so concurrent [fetch] calls can't race on
  /// reload or escalation. Requests run one at a time; each is a single in-page
  /// round trip, so the latency cost is negligible for catalog browsing.
  Future<void> _gate = Future<void>.value();

  /// Whether the JanitorAI catalog is currently the foreground view. Driven by
  /// [setActive] from the UI so the offscreen WebView only lives while the
  /// catalog is open — it is never kept warm in the background.
  bool _active = false;
  Timer? _shutdownTimer;

  /// Called by the catalog UI to mark the JanitorAI catalog visible/hidden.
  /// On hide we tear the WebView down after a short grace period (debounces the
  /// branch cross-fade and sub-tab toggles); on show we just cancel any pending
  /// shutdown — the WebView itself is (re)created lazily on the next [fetch].
  void setActive(bool active) {
    if (active) {
      _shutdownTimer?.cancel();
      _shutdownTimer = null;
      if (!_active) _log('catalog active');
      _active = true;
    } else {
      if (!_active) return;
      _active = false;
      _log('catalog hidden — scheduling shutdown');
      _shutdownTimer?.cancel();
      _shutdownTimer = Timer(const Duration(seconds: 3), () {
        if (!_active) dispose();
      });
    }
  }

  /// Fetches [url] (must be a janitorai.com URL) from inside the WebView session
  /// and returns the raw response body. Throws [JanitorCfException] if CF cannot
  /// be cleared, or [Exception] on other HTTP errors.
  Future<String> fetch(String url) {
    final completer = Completer<String>();
    _gate = _gate.then((_) async {
      try {
        completer.complete(await _fetchLocked(url));
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  /// Whether a JanitorAI account session is present (a JWT lives in the shared
  /// `localStorage`). Boots the offscreen WebView if needed.
  Future<bool> isLoggedIn() async {
    await _ensureStarted();
    final controller = _controller;
    if (controller == null) return false;
    try {
      final res = await controller
          .callAsyncJavaScript(
            functionBody: '$_findTokenJs return __glazeFindToken() != null;',
          )
          .timeout(const Duration(seconds: 10));
      return res?.value == true;
    } catch (e) {
      _log('isLoggedIn error: $e');
      return false;
    }
  }

  /// Clears the JanitorAI account session (cookies + DOM storage) and reloads
  /// the offscreen page so subsequent requests are anonymous again.
  Future<void> logout() async {
    final controller = _controller;
    if (controller != null) {
      try {
        await controller.evaluateJavascript(
          source: 'try { localStorage.clear(); sessionStorage.clear(); } catch (e) {}',
        );
      } catch (_) {}
    }
    try {
      await CookieManager.instance().deleteAllCookies();
    } catch (_) {}
    await _reload();
  }

  Future<String> _fetchLocked(String url) async {
    await _ensureStarted();

    var result = await _rawFetch(url);

    // Soft block: reload the page to re-run Turnstile and refresh cf_clearance.
    if (_isCfBlocked(result)) {
      _log('CF block on fetch — reloading session');
      await _reload();
      result = await _rawFetch(url);
    }

    // Still blocked: CF wants an interactive challenge. Surface the visible
    // WebView for the user, then reuse the refreshed session.
    if (_isCfBlocked(result)) {
      _log('CF block persists — escalating to visible challenge');
      await _escalateToVisible();
      await _reload();
      result = await _rawFetch(url);
    }

    if (_isCfBlocked(result)) {
      throw JanitorCfException(result.status);
    }
    if (result.status < 0) {
      throw Exception('WebView fetch failed');
    }
    if (result.status >= 400) {
      throw Exception('HTTP ${result.status}');
    }
    return result.body;
  }

  Future<void> _ensureStarted() {
    if (_controller != null) return Future<void>.value();
    if (_starting != null) return _starting!.future;
    final c = Completer<void>();
    _starting = c;
    _start().then((_) {
      c.complete();
    }).catchError((Object e, StackTrace st) {
      _starting = null;
      c.completeError(e, st);
    });
    return c.future;
  }

  Future<void> _start() async {
    _log('starting headless webview');
    final created = Completer<void>();
    _loadStop = Completer<void>();
    final hv = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(url: _origin),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        domStorageEnabled: true,
        cacheEnabled: true,
        thirdPartyCookiesEnabled: true,
        isInspectable: false,
        useHybridComposition: true,
      ),
      webViewEnvironment: defaultTargetPlatform == TargetPlatform.windows
          ? chatWebViewEnvironment
          : null,
      onWebViewCreated: (controller) async {
        _controller = controller;
        try {
          final ua =
              await controller.evaluateJavascript(source: 'navigator.userAgent');
          if (ua is String && ua.isNotEmpty) {
            CfChallengeService.instance.setWebViewUA(ua);
            _log('UA: $ua');
          }
        } catch (_) {}
        if (!created.isCompleted) created.complete();
      },
      onLoadStop: (controller, url) {
        _log('onLoadStop: $url');
        final c = _loadStop;
        if (c != null && !c.isCompleted) c.complete();
      },
    );
    await hv.run();
    _webView = hv;
    await created.future;
    await _awaitLoad();
    await _waitForClearance();
  }

  Future<void> _reload() async {
    final controller = _controller;
    if (controller == null) return;
    _loadStop = Completer<void>();
    await controller.loadUrl(urlRequest: URLRequest(url: _origin));
    await _awaitLoad();
    await _waitForClearance();
  }

  /// Waits for the in-flight navigation to finish loading (bounded), so JS is
  /// never evaluated against `about:blank`.
  Future<void> _awaitLoad({
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final c = _loadStop;
    if (c == null || c.isCompleted) return;
    try {
      await c.future.timeout(timeout);
    } on TimeoutException {
      _log('onLoadStop timeout — proceeding anyway');
    }
  }

  Future<void> _escalateToVisible() async {
    CfChallengeService.instance.invalidate();
    // solve() flips isPending → CatalogGrid mounts the visible _CfChallengeWebView
    // which solves interactively and lands cf_clearance in the shared cookie jar.
    await CfChallengeService.instance.solve();
  }

  /// Polls the shared cookie jar until `cf_clearance` appears for janitorai.com.
  Future<bool> _waitForClearance({
    Duration timeout = const Duration(seconds: 12),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      try {
        final cookies = await CookieManager.instance().getCookies(url: _origin);
        for (final c in cookies) {
          if (c.name == 'cf_clearance') {
            final value = c.value?.toString() ?? '';
            if (value.isNotEmpty) {
              _log('cf_clearance present');
              return true;
            }
          }
        }
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
    _log('cf_clearance NOT obtained within timeout');
    return false;
  }

  Future<({int status, String body})> _rawFetch(String url) async {
    final controller = _controller;
    if (controller == null) return (status: -1, body: '');
    _log('rawFetch → ${url.length > 80 ? url.substring(0, 80) : url}');
    try {
      // Inline the URL as a JSON-escaped JS literal rather than passing it via
      // `arguments` (which has been flaky on Android in this plugin version).
      final res = await controller
          .callAsyncJavaScript(
            functionBody: '''
              $_findTokenJs
              const token = __glazeFindToken();
              const headers = { "Accept": "application/json, text/plain, */*" };
              if (token) headers["authorization"] = "Bearer " + token;
              const r = await fetch(${jsonEncode(url)}, {
                headers: headers,
                credentials: "include",
              });
              const body = await r.text();
              return { status: r.status, body: body, auth: token ? 1 : 0 };
            ''',
          )
          .timeout(const Duration(seconds: 25));
      if (res == null || res.error != null) {
        _log('rawFetch JS error: ${res?.error}');
        return (status: -1, body: '');
      }
      final value = res.value;
      if (value is Map) {
        final status = (value['status'] as num?)?.toInt() ?? -1;
        final body = value['body']?.toString() ?? '';
        final auth = (value['auth'] as num?)?.toInt() == 1;
        _log('rawFetch ← status=$status bytes=${body.length} auth=$auth');
        return (status: status, body: body);
      }
      _log('rawFetch ← unexpected value type: ${value.runtimeType}');
      return (status: -1, body: '');
    } on TimeoutException {
      _log('rawFetch TIMEOUT (JS call did not return in 25s)');
      return (status: -1, body: '');
    } catch (e) {
      _log('rawFetch exception: $e');
      return (status: -1, body: '');
    }
  }

  bool _isCfBlocked(({int status, String body}) r) {
    if (r.status == 403 || r.status == 503) return true;
    // CF interstitials can also return 200 with the challenge HTML.
    if (r.status == 200 && r.body.contains('Access Restricted')) return true;
    return false;
  }

  /// Tears the offscreen WebView down. Invoked when the catalog is hidden (see
  /// [setActive]); the next [fetch] transparently recreates it.
  Future<void> dispose() async {
    _log('disposing headless webview');
    _shutdownTimer?.cancel();
    _shutdownTimer = null;
    final webView = _webView;
    _webView = null;
    _controller = null;
    _starting = null;
    _loadStop = null;
    try {
      await webView?.dispose();
    } catch (_) {}
  }
}
