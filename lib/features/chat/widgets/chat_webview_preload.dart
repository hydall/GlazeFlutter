import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../bridge/chat_webview_keep_alive.dart';

class ChatWebViewPreloader extends StatefulWidget {
  final Widget child;
  const ChatWebViewPreloader({super.key, required this.child});
  @override
  State<ChatWebViewPreloader> createState() => _ChatWebViewPreloaderState();
}

class _ChatWebViewPreloaderState extends State<ChatWebViewPreloader> {
  bool _preloaded = false;

  @override
  Widget build(BuildContext context) {
    // Skip webview preloading on Windows (no InAppWebView implementation) and
    // in widget tests (FLUTTER_TEST=true). In tests the InAppWebView platform
    // channel isn't mocked and would block forever.
    const isTest = bool.fromEnvironment('FLUTTER_TEST');
    final shouldPreload = !isTest && !Platform.isWindows;
    return Stack(
      children: [
        widget.child,
        if (shouldPreload && !_preloaded)
          IgnorePointer(
            child: Opacity(
              opacity: 0,
              child: SizedBox(
                width: 1,
                height: 1,
                child: InAppWebView(
                  keepAlive: chatWebViewKeepAlive,
                  initialFile: 'assets/chat_webview/index.html',
                  initialSettings: InAppWebViewSettings(
                    javaScriptEnabled: true,
                    domStorageEnabled: true,
                    transparentBackground: true,
                    isInspectable: true,
                    useHybridComposition: true,
                    cacheEnabled: true,
                    allowFileAccess: true,
                    allowContentAccess: true,
                    allowFileAccessFromFileURLs: true,
                    allowUniversalAccessFromFileURLs: true,
                    mixedContentMode:
                        MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
                  ),
                  onLoadStop: (_, _) {
                    if (mounted) setState(() => _preloaded = true);
                  },
                ),
              ),
            ),
          ),
      ],
    );
  }
}
