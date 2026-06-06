import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/js_bridge_service.dart';
import '../services/js_engine_service.dart';

/// Process-wide singleton [JsEngineService]. `ref.read` is used (not watch)
/// because the engine has its own internal lifecycle and does not emit
/// reactive state — callers should rely on [JsEngineService.status] for
/// health checks.
final jsEngineServiceProvider = Provider<JsEngineService>(
  (ref) {
    final service = JsEngineService.instance;
    ref.onDispose(() {
      // The service is a process singleton, so we deliberately do NOT
      // dispose it when the provider tears down. Individual call sites can
      // call `service.dispose()` during app shutdown.
    });
    return service;
  },
);

/// Builds a [JsEngineBridgeHost] backed by the supplied [JsBridgeService].
/// Extracted into a small factory so the visual chat WebView and the
/// headless engine can share the same bridge dispatcher.
///
/// [currentCharIdProvider] is the fallback `characterId` used by
/// `glaze.triggerGeneration` when the JS request has no
/// `context.characterId` (e.g. scripts that run without an open chat).
JsEngineBridgeHost jsEngineBridgeHostFor(
  JsBridgeService bridge, {
  String? Function()? currentCharIdProvider,
}) {
  return JsEngineBridgeHost(
    bridge: bridge,
    currentCharIdProvider: currentCharIdProvider,
  );
}
