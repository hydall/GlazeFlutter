import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'dev_chat_message.dart';
import 'dev_chat_service.dart';

/// A fully self-contained WebView that renders the developer-chat message list.
///
/// Deliberately isolated from the RP chat WebView (`assets/chat_webview/`): it
/// shares no HTML, CSS, JS, bridge, or virtual-scroll code. The whole page is
/// embedded below as [_html] and loaded via `initialData`, so there are no
/// asset files and no ES-module/origin concerns on any platform.
///
/// Contract:
///   Flutter → JS : window.DevChat.setMessages(jsonArray)
///   JS → Flutter : handler 'devChatReady'  (page ready → push messages)
///                  handler 'devChatRetry'  (arg: message id → resend)
class DevChatWebView extends StatefulWidget {
  const DevChatWebView({
    super.key,
    required this.messages,
    required this.onRetry,
  });

  final List<DevChatMessage> messages;
  final void Function(String id) onRetry;

  @override
  State<DevChatWebView> createState() => _DevChatWebViewState();
}

class _DevChatWebViewState extends State<DevChatWebView> {
  InAppWebViewController? _controller;
  bool _ready = false;

  @override
  void didUpdateWidget(DevChatWebView old) {
    super.didUpdateWidget(old);
    if (_ready) _push();
  }

  void _push() {
    final data = [
      for (final m in widget.messages)
        {
          'id': m.id,
          'fromDev': m.fromDev,
          'text': m.text,
          'ts': m.ts,
          'devName': m.devName,
          'avatarUrl': (m.devId != null && m.devId!.isNotEmpty)
              ? DevChatService.avatarUrl(m.devId!)
              : null,
          'status': m.status.name,
        },
    ];
    _controller?.evaluateJavascript(
      source: 'window.DevChat && window.DevChat.setMessages(${jsonEncode(data)})',
    );
  }

  @override
  Widget build(BuildContext context) {
    return InAppWebView(
      initialData: InAppWebViewInitialData(
        data: _html,
        mimeType: 'text/html',
        encoding: 'utf-8',
      ),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        transparentBackground: false,
        supportZoom: false,
        disableVerticalScroll: false,
        disableHorizontalScroll: true,
      ),
      onWebViewCreated: (controller) {
        _controller = controller;
        controller.addJavaScriptHandler(
          handlerName: 'devChatReady',
          callback: (_) {
            _ready = true;
            _push();
          },
        );
        controller.addJavaScriptHandler(
          handlerName: 'devChatRetry',
          callback: (args) {
            if (args.isNotEmpty && args.first is String) {
              widget.onRetry(args.first as String);
            }
          },
        );
      },
    );
  }
}

/// The entire page. Dark, chat-like bubbles built with DOM APIs (text goes in
/// via textContent — no innerHTML — so message text can never inject markup).
const String _html = r'''
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
<style>
  :root {
    --bg: #121212;
    --dev-bubble: #2a2b2f;
    --dev-text: #e7e7ea;
    --user-bubble: #6d7fb3;
    --user-text: #ffffff;
    --name: #9db0dd;
    --hint: #8a8a90;
    --error: #e2726e;
  }
  * { box-sizing: border-box; margin: 0; padding: 0;
      -webkit-tap-highlight-color: transparent; }
  html, body { height: 100%; background: var(--bg); }
  body {
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
    font-size: 15px; color: var(--dev-text);
  }
  #list {
    height: 100vh; overflow-y: auto; overflow-x: hidden;
    padding: 12px; display: flex; flex-direction: column; gap: 8px;
    -webkit-overflow-scrolling: touch;
  }
  #list::-webkit-scrollbar { width: 0; }
  .row { display: flex; align-items: flex-end; gap: 8px; }
  .row.dev { justify-content: flex-start; }
  .row.user { justify-content: flex-end; }
  .avatar {
    width: 32px; height: 32px; border-radius: 50%; flex: 0 0 32px;
    overflow: hidden; background: #3a3b40; color: #cfd2dc;
    display: flex; align-items: center; justify-content: center;
    font-size: 12px; font-weight: 600;
  }
  .avatar img { width: 100%; height: 100%; object-fit: cover; display: block; }
  .col { display: flex; flex-direction: column; max-width: 74%; min-width: 0; }
  .row.dev .col { align-items: flex-start; }
  .row.user .col { align-items: flex-end; }
  .head { display: flex; align-items: center; gap: 6px; margin: 0 4px 3px; }
  .chip {
    background: var(--user-bubble); color: #fff; font-size: 10px;
    font-weight: 700; letter-spacing: .3px; line-height: 1.1;
    padding: 2px 7px; border-radius: 6px;
  }
  .name {
    color: var(--name); font-size: 12px; font-weight: 600;
    white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
    max-width: 180px;
  }
  .bubble {
    padding: 9px 14px; border-radius: 16px; line-height: 1.4;
    white-space: pre-wrap; word-wrap: break-word; overflow-wrap: anywhere;
  }
  .dev .bubble { background: var(--dev-bubble); color: var(--dev-text);
    border-bottom-left-radius: 5px; }
  .user .bubble { background: var(--user-bubble); color: var(--user-text);
    border-bottom-right-radius: 5px; }
  .status { font-size: 11px; color: var(--hint); margin: 2px 4px 0; }
  .status.failed { color: var(--error); cursor: pointer; }
  #empty {
    position: fixed; inset: 0; display: flex; align-items: center;
    justify-content: center; text-align: center; color: var(--hint);
    padding: 32px; line-height: 1.5;
  }
</style>
</head>
<body>
  <div id="list"></div>
  <div id="empty">Say hi to the developers.<br>Messages go straight to the team.</div>
<script>
(function () {
  var list = document.getElementById('list');
  var empty = document.getElementById('empty');

  function initials(name) {
    var n = (name || '').trim();
    if (!n) return '?';
    var p = n.split(/\s+/);
    if (p.length === 1) return p[0][0].toUpperCase();
    return (p[0][0] + p[1][0]).toUpperCase();
  }

  function avatarEl(m) {
    var a = document.createElement('div');
    a.className = 'avatar';
    if (m.avatarUrl) {
      var img = document.createElement('img');
      img.src = m.avatarUrl;
      img.onerror = function () {
        a.removeChild(img);
        a.textContent = initials(m.devName);
      };
      a.appendChild(img);
    } else {
      a.textContent = initials(m.devName);
    }
    return a;
  }

  function statusText(s) {
    if (s === 'sending') return 'sending…';
    if (s === 'sent') return '✓';
    if (s === 'failed') return 'failed — tap to retry';
    return '';
  }

  function render(msgs) {
    list.innerHTML = '';
    empty.style.display = msgs.length ? 'none' : 'flex';

    msgs.forEach(function (m) {
      var row = document.createElement('div');
      row.className = 'row ' + (m.fromDev ? 'dev' : 'user');

      if (m.fromDev) row.appendChild(avatarEl(m));

      var col = document.createElement('div');
      col.className = 'col';

      if (m.fromDev) {
        var head = document.createElement('div');
        head.className = 'head';
        var chip = document.createElement('span');
        chip.className = 'chip';
        chip.textContent = 'Dev';
        head.appendChild(chip);
        if (m.devName) {
          var name = document.createElement('span');
          name.className = 'name';
          name.textContent = m.devName;
          head.appendChild(name);
        }
        col.appendChild(head);
      }

      var bubble = document.createElement('div');
      bubble.className = 'bubble';
      bubble.textContent = m.text;
      col.appendChild(bubble);

      if (!m.fromDev) {
        var st = document.createElement('div');
        st.className = 'status' + (m.status === 'failed' ? ' failed' : '');
        st.textContent = statusText(m.status);
        if (m.status === 'failed') {
          st.addEventListener('click', function () {
            window.flutter_inappwebview.callHandler('devChatRetry', m.id);
          });
        }
        col.appendChild(st);
      }

      row.appendChild(col);
      list.appendChild(row);
    });

    // Keep the newest message in view.
    requestAnimationFrame(function () {
      list.scrollTop = list.scrollHeight;
    });
  }

  window.DevChat = { setMessages: render };

  function ready() {
    window.flutter_inappwebview.callHandler('devChatReady');
  }
  if (window.flutter_inappwebview) ready();
  else window.addEventListener('flutterInAppWebViewPlatformReady', ready);
})();
</script>
</body>
</html>
''';
