import 'dart:async';

import '../js_bridge_context.dart';

class CommandHandler {
  const CommandHandler();

  FutureOr<Map<String, dynamic>> executeCommand(JsBridgeContext bridge) {
    bridge.requireCapability('execute_command');
    final command = bridge.params['command'];
    if (command is! String || command.isEmpty) {
      throw ArgumentError('executeCommand requires a non-empty string command');
    }
    final handler =
        bridge.executeCommand ??
        (throw UnsupportedError(
          'glaze.executeCommand is not available in this context',
        ));
    return handler(command, asBridgeMap(bridge.params['args']), bridge.context);
  }
}
