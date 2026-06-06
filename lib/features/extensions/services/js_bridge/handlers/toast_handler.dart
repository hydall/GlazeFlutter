import 'package:flutter/foundation.dart';

import '../js_bridge_context.dart';

class ToastHandler {
  const ToastHandler();

  bool showToast(JsBridgeContext bridge) {
    bridge.requireCapability('show_toast');
    final message = bridge.params['message'];
    if (message != null && message is! String) {
      throw ArgumentError('showToast message must be a string');
    }
    final options = asBridgeMap(bridge.params['options']);
    final handler =
        bridge.showToast ??
        (msg, _) => debugPrint('[JsBridge] toast: ${msg ?? ''}');
    handler(message as String?, {...options, '_context': bridge.context});
    return true;
  }
}
