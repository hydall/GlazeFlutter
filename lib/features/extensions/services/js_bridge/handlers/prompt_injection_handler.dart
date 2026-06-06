import 'dart:async';

import '../js_bridge_context.dart';

class PromptInjectionHandler {
  const PromptInjectionHandler();

  FutureOr<Map<String, dynamic>> injectPrompt(JsBridgeContext bridge) {
    bridge.requireCapability('inject_prompt');
    final id = bridge.params['id'];
    if (id is! String || id.trim().isEmpty) {
      throw ArgumentError('injectPrompt id is required');
    }
    final content = bridge.params['content'];
    if (content is! String || content.trim().isEmpty) {
      throw ArgumentError('injectPrompt content is required');
    }
    final handler =
        bridge.injectPrompt ??
        (throw UnsupportedError(
          'glaze.injectPrompt is not available in this context',
        ));
    return handler(
      id,
      content,
      asBridgeMap(bridge.params['options']),
      bridge.context,
    );
  }

  FutureOr<Map<String, dynamic>> uninjectPrompt(JsBridgeContext bridge) {
    bridge.requireCapability('uninject_prompt');
    final id = bridge.params['id'];
    if (id is! String || id.trim().isEmpty) {
      throw ArgumentError('uninjectPrompt id is required');
    }
    final handler =
        bridge.uninjectPrompt ??
        (throw UnsupportedError(
          'glaze.uninjectPrompt is not available in this context',
        ));
    return handler(id, bridge.context);
  }
}
