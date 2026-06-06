import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:glaze_flutter/features/extensions/services/js_bridge_service.dart';
import 'package:glaze_flutter/features/extensions/services/js_engine_service.dart';

class _FakeEngineController implements JsEngineController {
  _FakeEngineController();

  Object? scriptResult;
  final List<Map<String, dynamic>> calls = [];
  Completer<void>? pendingCall;
  Completer<Object>? pendingResult;

  @override
  Future<void> addJavaScriptHandler({
    required String handlerName,
    required Future<dynamic> Function(List<dynamic> args) callback,
  }) async {}

  @override
  Future<JsAsyncJsResult?> callAsyncJavaScript({
    required String functionBody,
    required Map<String, dynamic> arguments,
  }) async {
    calls.add({'functionBody': functionBody, 'arguments': arguments});
    if (pendingResult != null) {
      final result = await pendingResult!.future;
      return JsAsyncJsResult(result);
    }
    return JsAsyncJsResult(scriptResult);
  }

  @override
  Future<void> evaluateJavascript({required String source}) async {}

  @override
  Future<void> dispose() async {}
}

void main() {
  group('JsEngineService', () {
    tearDown(() {
      JsEngineService.debugSetInstance(null);
    });

    test('singleton returns the same instance across calls', () {
      final a = JsEngineService.instance;
      final b = JsEngineService.instance;
      expect(identical(a, b), isTrue);
    });

    test('debugInitWithController marks service ready and stores host',
        () async {
      final fake = _FakeEngineController();
      final host = JsEngineBridgeHost(bridge: JsBridgeService());
      final service = JsEngineService.instance;
      expect(service.isReady, isFalse);
      expect(service.status, JsEngineStatus.uninitialized);

      await service.debugInitWithController(controller: fake, host: host);
      // Re-init is a no-op once ready.
      await service.debugInitWithController(controller: fake, host: host);

      expect(service.status, JsEngineStatus.ready);
      expect(service.isReady, isTrue);
    });

    test('runScript returns the controller value as a string', () async {
      final fake = _FakeEngineController()..scriptResult = 'hello from headless';
      final host = JsEngineBridgeHost(bridge: JsBridgeService());
      final service = JsEngineService.instance;
      await service.debugInitWithController(controller: fake, host: host);

      final result = await service.runScript(
        script: 'return "hi";',
        context: const {'foo': 'bar'},
      );

      expect(result, 'hello from headless');
      expect(fake.calls, hasLength(1));
      final args = fake.calls.first['arguments'] as Map<String, dynamic>;
      expect(args['script'], 'return "hi";');
      expect(args['contextJson'], contains('foo'));
    });

    test('runScript throws HeadlessUnavailableError when not ready', () async {
      final service = JsEngineService.instance;
      expect(
        () => service.runScript(
          script: 'return 1;',
          context: const {},
        ),
        throwsA(isA<HeadlessUnavailableError>()),
      );
    });

    test('cancel rejects an in-flight run', () async {
      final fake = _FakeEngineController()..pendingResult = Completer<Object>();
      final host = JsEngineBridgeHost(bridge: JsBridgeService());
      final service = JsEngineService.instance;
      await service.debugInitWithController(controller: fake, host: host);

      final pending = service.runScript(
        script: 'return 1;',
        context: const {},
        timeout: const Duration(seconds: 5),
        cancelToken: CancelToken(),
      );
      service.cancel();

      await expectLater(
        pending,
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('cancelled'),
          ),
        ),
      );
    });

    test('dispose clears the controller and marks service disposed', () async {
      final fake = _FakeEngineController();
      final host = JsEngineBridgeHost(bridge: JsBridgeService());
      final service = JsEngineService.instance;
      await service.debugInitWithController(controller: fake, host: host);
      expect(service.isReady, isTrue);

      await service.dispose();
      expect(service.status, JsEngineStatus.disposed);
      expect(service.isReady, isFalse);
    });
  });
}
