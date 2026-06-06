import 'dart:async';

import '../js_bridge_context.dart';

class AudioHandler {
  const AudioHandler();

  FutureOr<void> playAudio(JsBridgeContext bridge) {
    bridge.requireCapability('play_audio');
    final source = bridge.params['source'];
    if (source != null && source is! String) {
      throw ArgumentError('playAudio source must be a string');
    }
    final handler =
        bridge.playAudio ??
        (throw UnsupportedError(
          'glaze.playAudio is not available in this context',
        ));
    return handler(source as String?, asBridgeMap(bridge.params['options']));
  }
}
