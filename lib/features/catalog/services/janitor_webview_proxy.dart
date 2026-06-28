import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../chat/bridge/chat_webview_environment.dart';
import 'cf_challenge_service.dart';
import 'janitor_separate.dart';

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

/// Document-start user script installed before navigating to a chat page when
/// capturing a `generateAlpha` payload. It does two things, mirroring the
/// SillyTavern `janitor-lorebook` plugin's Playwright capture:
///
/// 1. **Intercepts** the assembled prompt. JanitorAI's frontend, in proxy/API
///    mode, calls `…/generateAlpha` and the *response* is the fully-assembled
///    `{messages:[{role:"system", …}]}` — the system message contains the
///    hidden card + the triggered (closed) lorebook entries. We wrap both
///    `fetch` and `XMLHttpRequest` (the site may use either) and stash the last
///    matching payload on `window.__glazeAlpha`.
/// 2. Exposes **`window.__glazeSend(text)`** which types [text] into the chat
///    input and submits — the trigger that makes the server assemble + return
///    the prompt. Ported from `capture.cjs` `_send`/`_autoTrigger`, including
///    the React controlled-input trick (native value setter + `input` event;
///    a plain `el.value = …` leaves React's state empty and the send no-ops).
///
/// Injected at document start so it hooks the network *before* page scripts
/// capture their own `fetch` reference. **Brittle by nature:** the input/send
/// selectors track JanitorAI's chat DOM, exactly like the plugin's Playwright
/// selectors — tune [_captureUserScript] if the site changes.
const String _captureUserScript = r'''
  (function () {
    if (window.__glazeHooked) return;
    window.__glazeHooked = true;
    window.__glazeAlpha = null;

    const looksLikePayload = (o) =>
      o && Array.isArray(o.messages) &&
      o.messages.some((m) => m && m.role === 'system' && typeof m.content === 'string');

    // --- fetch hook ---
    const origFetch = window.fetch ? window.fetch.bind(window) : null;
    if (origFetch) {
      window.fetch = async function (...args) {
        const res = await origFetch(...args);
        try {
          const a0 = args[0];
          const url = (a0 && a0.url) ? a0.url : (typeof a0 === 'string' ? a0 : '');
          if (typeof url === 'string' && url.indexOf('/generateAlpha') >= 0) {
            res.clone().json().then((j) => {
              if (looksLikePayload(j)) window.__glazeAlpha = j;
            }).catch(() => {});
          }
        } catch (e) {}
        return res;
      };
    }

    // --- XMLHttpRequest hook ---
    const OrigXHR = window.XMLHttpRequest;
    if (OrigXHR) {
      const open = OrigXHR.prototype.open;
      OrigXHR.prototype.open = function (method, url) {
        this.__glazeUrl = url;
        return open.apply(this, arguments);
      };
      OrigXHR.prototype.addEventListener &&
        (function () {
          const send = OrigXHR.prototype.send;
          OrigXHR.prototype.send = function () {
            this.addEventListener('load', function () {
              try {
                if (typeof this.__glazeUrl === 'string' &&
                    this.__glazeUrl.indexOf('/generateAlpha') >= 0) {
                  const j = JSON.parse(this.responseText);
                  if (looksLikePayload(j)) window.__glazeAlpha = j;
                }
              } catch (e) {}
            });
            return send.apply(this, arguments);
          };
        })();
    }

    // --- chat input + send ---
    const SEL = ['textarea[placeholder]', 'form textarea', 'textarea', 'div[contenteditable="true"]'];
    const findInput = () => {
      for (const s of SEL) {
        const els = document.querySelectorAll(s);
        for (let i = els.length - 1; i >= 0; i--) {
          const el = els[i];
          if (el && el.offsetParent !== null) return el;
        }
      }
      return null;
    };
    const setReactValue = (el, val) => {
      if (el.tagName === 'TEXTAREA' || el.tagName === 'INPUT') {
        const proto = el.tagName === 'TEXTAREA'
          ? window.HTMLTextAreaElement.prototype
          : window.HTMLInputElement.prototype;
        const setter = Object.getOwnPropertyDescriptor(proto, 'value').set;
        setter.call(el, val);
        el.dispatchEvent(new Event('input', { bubbles: true }));
      } else {
        el.focus();
        el.textContent = val;
        el.dispatchEvent(new InputEvent('input', { bubbles: true }));
      }
    };
    const pressEnter = (el) => {
      for (const type of ['keydown', 'keypress', 'keyup']) {
        el.dispatchEvent(new KeyboardEvent(type, {
          key: 'Enter', code: 'Enter', keyCode: 13, which: 13,
          bubbles: true, cancelable: true,
        }));
      }
    };
    window.__glazeSend = async (text) => {
      const el = findInput();
      if (!el) return { ok: false, reason: 'no-input' };
      el.focus();
      setReactValue(el, text);
      await new Promise((r) => setTimeout(r, 150));
      const btn = document.querySelector(
        'button[type="submit"]:not([disabled]), ' +
        'form button[aria-label*="send" i]:not([disabled]), ' +
        'button[aria-label*="send" i]:not([disabled])');
      if (btn) { btn.click(); } else { pressEnter(el); }
      return { ok: true };
    };
  })();
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

  static const String _profileUrl =
      'https://janitorai.com/hampter/profiles/mine';

  /// A self-owned proxy preset injected for the duration of a capture. The URL
  /// is intentionally unreachable: we capture the `/generateAlpha` RESPONSE (the
  /// assembled prompt) BEFORE the client ever POSTs to the proxy, so the proxy
  /// never needs to answer. Fixed id so a crashed run never leaves duplicates.
  static const String _dummyPresetId = 'a1b2c3d4-0000-4000-8000-000000000001';
  static const Map<String, dynamic> _dummyPreset = {
    'apiKey': 'x',
    'apiUrl': 'http://127.0.0.1:9/v1/chat/completions',
    'id': _dummyPresetId,
    'jailbreakPrompt': '',
    'model': 'gpt-4o',
    'name': 'glaze-lorebook-extractor (auto)',
  };

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
  ///
  /// [method] defaults to GET; pass e.g. `'PATCH'` with a JSON [body] string to
  /// mutate account data (the body is sent as `application/json`). Mutating
  /// requests need an account session — the bearer token is attached in-page.
  Future<String> fetch(String url, {String method = 'GET', String? body}) {
    final completer = Completer<String>();
    _gate = _gate.then((_) async {
      try {
        completer.complete(await _fetchLocked(url, method: method, body: body));
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  /// Captures the assembled `generateAlpha` payload for [characterId] — the
  /// fully-built system prompt containing the hidden character card and the
  /// triggered (closed) lorebook entries. Port of the SillyTavern
  /// `janitor-lorebook` plugin's `runFromUrl`/`_autoTrigger`.
  ///
  /// Pipeline (serialized through [_gate]): create a fresh chat, navigate the
  /// offscreen WebView to it with [_captureUserScript] installed, send `"."` to
  /// surface the card, then re-send the card text (+ optional [triggerText],
  /// e.g. the first message) to maximise lorebook keyword matches, and return
  /// the captured payload. Throws on timeout / login / CF failure.
  Future<Map<String, dynamic>> captureGenerateAlpha({
    required String characterId,
    String triggerText = '',
    void Function(String phase)? onPhase,
  }) {
    final completer = Completer<Map<String, dynamic>>();
    _gate = _gate.then((_) async {
      try {
        completer.complete(
            await _captureLocked(characterId, triggerText, onPhase));
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  Future<Map<String, dynamic>> _captureLocked(
    String characterId,
    String triggerText,
    void Function(String phase)? onPhase,
  ) async {
    void phase(String p) {
      _log('capture phase: $p');
      onPhase?.call(p);
    }

    phase('starting');
    await _ensureStarted();

    if (!await isLoggedIn()) {
      throw Exception('Not logged into JanitorAI — log in first (Menu → JanitorAI).');
    }

    // Force the account into proxy mode against an unreachable dummy preset (and
    // context_length 0) so the captured `/generateAlpha` prompt keeps its
    // wrappers and isn't truncated/reordered. Restored in the finally below.
    // Without this, an account on JLLM ("janitor") never assembles a proxy
    // prompt — the send just runs on Janitor's own model.
    phase('configuring proxy');
    final profileSnapshot = await _enterExtractionMode();
    try {
      // 1) Create a fresh chat for this character.
      phase('creating chat');
      final chatBody = await _fetchLocked(
        'https://janitorai.com/hampter/chats',
        method: 'POST',
        body: jsonEncode({'character_id': characterId}),
      );
      final chatJson = jsonDecode(chatBody);
      final chatId = (chatJson is Map ? chatJson['id'] : null)?.toString();
      if (chatId == null || chatId.isEmpty) {
        throw Exception('Could not create chat (no id in response).');
      }

      final controller = _controller;
      if (controller == null) throw Exception('WebView not available.');

      // 2) Install the capture hook at document start, then open the chat.
      phase('opening chat');
      await controller.removeAllUserScripts();
      await controller.addUserScript(
        userScript: UserScript(
          source: _captureUserScript,
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        ),
      );
      try {
        _loadStop = Completer<void>();
        await controller.loadUrl(
          urlRequest: URLRequest(
            url: WebUri('https://janitorai.com/chats/$chatId'),
          ),
        );
        await _awaitLoad();
        await _waitForClearance();
        // Give the React chat app time to hydrate before driving the input.
        await Future<void>.delayed(const Duration(milliseconds: 2500));

        // 3) Send "." → capture the card.
        phase('triggering (card)');
        final dot = await _captureOneSend('.', const Duration(seconds: 60));
        final card = dot != null ? extractCard(dot) : '';

        // 4) Send card (+ first message) → maximise lorebook triggers.
        final parts = <String>[
          if (card.isNotEmpty) card,
          if (triggerText.trim().isNotEmpty) triggerText.trim(),
        ];
        final trigger = parts.isEmpty ? '.' : parts.join('\n\n');
        phase('triggering (lorebook)');
        await _resetCapture();
        final full =
            await _captureOneSend(trigger, const Duration(seconds: 120));
        final result = full ?? dot;
        if (result == null) {
          throw Exception('Timed out waiting for a generateAlpha capture.');
        }
        phase('captured');
        return result;
      } finally {
        try {
          await controller.removeAllUserScripts();
        } catch (_) {}
      }
    } finally {
      if (profileSnapshot != null) {
        phase('restoring profile');
        await _restoreProfile(profileSnapshot);
      }
    }
  }

  /// Reshapes the JanitorAI profile so a capture yields a clean, tag-wrapped
  /// prompt, returning the ORIGINAL `config` snapshot to restore afterwards.
  /// Port of JAR `profile.js`. Two things must hold:
  ///  1. a custom OpenAI-compatible PROXY preset must be selected (not JLLM) —
  ///     only then does the client assemble the prompt for a proxy and fire
  ///     `/generateAlpha` with the `<…Persona>` / `<Scenario>` wrappers that
  ///     [separate] relies on;
  ///  2. `generation_settings.context_length` must be 0, or the server
  ///     compresses/reorders the prompt to fit and unwraps the persona block.
  /// Returns null if the profile could not be read/patched (capture proceeds
  /// against whatever the account has selected).
  Future<Map<String, dynamic>?> _enterExtractionMode() async {
    try {
      final body = await _fetchLocked(_profileUrl);
      final profile = jsonDecode(body);
      final original = (profile is Map && profile['config'] is Map)
          ? Map<String, dynamic>.from(profile['config'] as Map)
          : null;
      if (original == null) {
        _log('extraction mode skipped — profile has no config');
        return null;
      }

      final next =
          jsonDecode(jsonEncode(original)) as Map<String, dynamic>;
      final presets = (next['proxyConfigurations'] is List)
          ? List<dynamic>.from(next['proxyConfigurations'] as List)
          : <dynamic>[];
      if (!presets.any((p) => p is Map && p['id'] == _dummyPresetId)) {
        presets.add(Map<String, dynamic>.from(_dummyPreset));
      }
      next['proxyConfigurations'] = presets;
      next['selectedProxyConfigId'] = _dummyPresetId;
      next['api'] = 'openai';
      next['open_ai_mode'] = 'proxy';
      next['open_ai_reverse_proxy'] = _dummyPreset['apiUrl'];
      next['openAiModel'] = _dummyPreset['model'];
      next['generation_settings'] = {
        ...(next['generation_settings'] is Map
            ? Map<String, dynamic>.from(next['generation_settings'] as Map)
            : <String, dynamic>{}),
        'context_length': 0,
      };

      await _fetchLocked(_profileUrl,
          method: 'PATCH', body: jsonEncode({'config': next}));
      _log('extraction mode on (dummy proxy selected, context_length 0)');
      return original;
    } catch (e) {
      _log('enterExtractionMode failed (capture proceeds anyway): $e');
      return null;
    }
  }

  /// PATCHes the original `config` snapshot back (also drops the dummy preset).
  Future<void> _restoreProfile(Map<String, dynamic> original) async {
    try {
      await _fetchLocked(_profileUrl,
          method: 'PATCH', body: jsonEncode({'config': original}));
      _log('restored original profile config');
    } catch (e) {
      _log('restoreProfile failed: $e');
    }
  }

  /// Clears the last captured payload so the next send's capture is unambiguous.
  Future<void> _resetCapture() async {
    try {
      await _controller?.evaluateJavascript(source: 'window.__glazeAlpha = null;');
    } catch (_) {}
  }

  /// Drives one `__glazeSend(text)` and polls `window.__glazeAlpha` until a
  /// payload appears or [timeout] elapses. Returns null on timeout.
  Future<Map<String, dynamic>?> _captureOneSend(String text, Duration timeout) async {
    final controller = _controller;
    if (controller == null) return null;
    try {
      await controller.callAsyncJavaScript(
        functionBody: 'return await window.__glazeSend(${jsonEncode(text)});',
      );
    } catch (e) {
      _log('send error: $e');
    }
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 700));
      try {
        final res = await controller.evaluateJavascript(
          source: 'window.__glazeAlpha ? JSON.stringify(window.__glazeAlpha) : null',
        );
        if (res is String && res.isNotEmpty && res != 'null') {
          final decoded = jsonDecode(res);
          if (decoded is Map<String, dynamic>) return decoded;
          if (decoded is Map) return Map<String, dynamic>.from(decoded);
        }
      } catch (_) {}
    }
    return null;
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

  /// Returns true if a JanitorAI account token is detectable from [controller]'s
  /// page (shared cookie jar / `localStorage`). The login sheet uses this to
  /// confirm the session was actually persisted before it auto-closes — the
  /// sheet's visible WebView shares the same storage as this headless proxy, so
  /// a token visible here will be visible to catalog requests too.
  static Future<bool> hasSessionToken(InAppWebViewController controller) async {
    try {
      final res = await controller
          .callAsyncJavaScript(
            functionBody: '$_findTokenJs return __glazeFindToken() != null;',
          )
          .timeout(const Duration(seconds: 8));
      return res?.value == true;
    } catch (e) {
      _log('hasSessionToken error: $e');
      return false;
    }
  }

  /// Reads the signed-in JanitorAI profile's `user_name` from [controller]'s
  /// page, mirroring the request the site front-end makes after login
  /// (`GET /hampter/profiles/mine`). Runs in-page so it shares the cookie jar and
  /// CF fingerprint, and attaches the Supabase bearer token like [_rawFetch].
  /// Returns null when logged out or on any error.
  static Future<String?> fetchUserName(
    InAppWebViewController controller,
  ) async {
    try {
      final res = await controller
          .callAsyncJavaScript(
            functionBody: '''
              $_findTokenJs
              const token = __glazeFindToken();
              if (!token) return null;
              const r = await fetch(
                "https://janitorai.com/hampter/profiles/mine",
                {
                  headers: {
                    "Accept": "application/json, text/plain, */*",
                    "authorization": "Bearer " + token,
                  },
                  credentials: "include",
                },
              );
              if (!r.ok) return null;
              const j = await r.json();
              return (j && typeof j.user_name === "string") ? j.user_name : null;
            ''',
          )
          .timeout(const Duration(seconds: 10));
      final value = res?.value;
      return (value is String && value.isNotEmpty) ? value : null;
    } catch (e) {
      _log('fetchUserName error: $e');
      return null;
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

  Future<String> _fetchLocked(
    String url, {
    String method = 'GET',
    String? body,
  }) async {
    await _ensureStarted();

    var result = await _rawFetch(url, method: method, body: body);

    // Soft block: reload the page to re-run Turnstile and refresh cf_clearance.
    if (_isCfBlocked(result)) {
      _log('CF block on fetch — reloading session');
      await _reload();
      result = await _rawFetch(url, method: method, body: body);
    }

    // Still blocked: CF wants an interactive challenge. Surface the visible
    // WebView for the user, then reuse the refreshed session.
    if (_isCfBlocked(result)) {
      _log('CF block persists — escalating to visible challenge');
      await _escalateToVisible();
      await _reload();
      result = await _rawFetch(url, method: method, body: body);
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
        // Match the visible login sheet's UA: Edg-stripped but version-aligned
        // with the client hints CF validates. Null on mobile → native UA kept.
        userAgent: janitorWebViewUserAgent,
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

  Future<({int status, String body})> _rawFetch(
    String url, {
    String method = 'GET',
    String? body,
  }) async {
    final controller = _controller;
    if (controller == null) return (status: -1, body: '');
    _log('rawFetch $method → ${url.length > 80 ? url.substring(0, 80) : url}');
    try {
      // Inline the URL / method / body as JSON-escaped JS literals rather than
      // passing them via `arguments` (which has been flaky on Android in this
      // plugin version).
      final res = await controller
          .callAsyncJavaScript(
            functionBody: '''
              $_findTokenJs
              const token = __glazeFindToken();
              const headers = { "Accept": "application/json, text/plain, */*" };
              if (token) headers["authorization"] = "Bearer " + token;
              const opts = {
                method: ${jsonEncode(method)},
                headers: headers,
                credentials: "include",
              };
              ${body == null ? '' : 'headers["Content-Type"] = "application/json"; opts.body = ${jsonEncode(body)};'}
              const r = await fetch(${jsonEncode(url)}, opts);
              const respBody = await r.text();
              return { status: r.status, body: respBody, auth: token ? 1 : 0 };
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
