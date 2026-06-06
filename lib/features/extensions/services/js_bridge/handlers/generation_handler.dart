import 'dart:async';

import '../js_bridge_context.dart';

class GenerationHandler {
  const GenerationHandler();

  FutureOr<Map<String, dynamic>> triggerGeneration(JsBridgeContext bridge) {
    bridge.requireCapability('trigger_generation');
    final handler =
        bridge.triggerGeneration ??
        (throw UnsupportedError(
          'glaze.triggerGeneration is not available in this context',
        ));
    return handler(bridge.characterIdOrNull(), bridge.params);
  }

  Future<String> generateText(JsBridgeContext bridge) {
    bridge.requireCapability('generate_text');
    final prompt = bridge.params['prompt'];
    if (prompt is! String || prompt.trim().isEmpty) {
      throw ArgumentError('generateText prompt is required');
    }
    final options = asBridgeMap(bridge.params['options']);
    final preset = options['preset'];
    if (preset != null && preset is! String) {
      throw ArgumentError('generateText preset must be a string');
    }
    if (preset is String &&
        preset.isNotEmpty &&
        preset != 'big' &&
        preset != 'medium' &&
        preset != 'small') {
      throw ArgumentError('Unsupported generateText preset "$preset"');
    }
    final handler =
        bridge.generateText ??
        (throw UnsupportedError(
          'glaze.generateText is not available in this context',
        ));
    return handler(prompt, options, bridge.context);
  }
}
