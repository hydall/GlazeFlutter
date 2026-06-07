// Tests for the wired `CommandRegistry` - the production path that
// dispatches `/trigger`, `/getvar`, `/setvar`, `/inject`, and `/toast`
// to the same services the dedicated bridge methods use.
//
// The wired registry replaced the previous echo-only MVP, so the
// contract pinned here is:
//   * `/getvar` / `/setvar` route through `JsBridgeService.dispatch`
//     (so scope, permission, and JSON validation are identical to
//     the dedicated `glaze.getVariables` / `glaze.setVariables` paths).
//   * `/inject` calls `RuntimePromptInjectionNotifier.inject`.
//   * `/toast` calls `JsBridgeToastController.show`.
//   * `/trigger` calls `TriggerGenerationHandler.handle`.
//   * Each command validates its args and returns `CommandResult.error`
//     for malformed inputs instead of throwing.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:glaze_flutter/core/db/app_db.dart';
import 'package:glaze_flutter/core/db/repositories/character_repo.dart';
import 'package:glaze_flutter/core/models/character.dart';
import 'package:glaze_flutter/features/extensions/services/command_registry.dart';
import 'package:glaze_flutter/features/extensions/models/trigger_mode.dart';
import 'package:glaze_flutter/features/extensions/models/trigger_result.dart';
import 'package:glaze_flutter/features/extensions/services/generation_dispatcher.dart';
import 'package:glaze_flutter/features/extensions/services/js_bridge_service.dart';
import 'package:glaze_flutter/features/extensions/services/js_bridge_toast_controller.dart';
import 'package:glaze_flutter/features/extensions/services/runtime_prompt_injection_service.dart';
import 'package:glaze_flutter/features/extensions/services/trigger_generation_handler.dart';

AppDatabase _testDb() => AppDatabase.forTesting(NativeDatabase.memory());

/// Noop `GenerationDispatcher` for unit tests. The wired command
/// registry's `/trigger` validation should never reach the dispatcher;
/// when it does, we return `TriggerNoSession` to keep the test
/// deterministic without touching `Ref`.
class _NoopDispatcher extends GenerationDispatcher {
  @override
  Future<TriggerResult> dispatch({
    required String charId,
    String? rawMode,
    String? reason,
  }) async {
    return TriggerNoSession(mode: TriggerMode.parse(rawMode));
  }

  _NoopDispatcher() : super(null);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late CharacterRepo characterRepo;

  setUp(() async {
    db = _testDb();
    characterRepo = CharacterRepo(db);
    await characterRepo.put(Character(id: 'c1', name: 'Alice'));
  });

  tearDown(() async {
    await db.close();
  });

  /// Helper to build a wired registry backed by a real bridge.
  WiredCommandDeps buildDeps() {
    final bridge = JsBridgeService(
      chatRepo: null,
      characterRepo: characterRepo,
      currentSessionId: () => 's1',
      currentCharacterId: () => 'c1',
      permissionCheck: (_) => true,
    );
    final promptInjection = RuntimePromptInjectionNotifier();
    final triggerHandler = TriggerGenerationHandler(
      dispatcher: _NoopDispatcher(),
    );
    return WiredCommandDeps(
      bridge: bridge,
      toastController: JsBridgeToastController(),
      promptInjection: promptInjection,
      triggerHandler: triggerHandler,
    );
  }

  group('wired registry setup', () {
    test('registers all five MVP commands', () {
      final registry = buildWiredCommandRegistry(buildDeps());
      final names = registry.list().map((c) => c.name).toSet();
      expect(names, {'/trigger', '/getvar', '/setvar', '/inject', '/toast'});
    });
  });

  group('/getvar and /setvar route through the bridge', () {
    test('/getvar returns the stored value', () async {
      final registry = buildWiredCommandRegistry(buildDeps());
      // Pre-populate the character variables.
      await characterRepo.put(
        Character(
          id: 'c1',
          name: 'Alice',
          extensions: {
            'glaze_variables': {'flag': true},
          },
        ),
      );
      final result = await registry.run('/getvar', {
        'scope': 'character',
        'path': 'flag',
      }, context: const CommandContext(charId: 'c1'));
      expect(result.ok, isTrue);
      expect(result.data, isTrue);
    });

    test('/getvar returns an error for unsupported scope', () async {
      final registry = buildWiredCommandRegistry(buildDeps());
      final result = await registry.run('/getvar', {
        'scope': 'unknown',
        'path': 'x',
      }, context: const CommandContext(charId: 'c1'));
      expect(result.ok, isFalse);
      expect(result.message, isNotEmpty);
    });

    test(
      '/setvar writes to the requested scope and /getvar reads it back',
      () async {
        final registry = buildWiredCommandRegistry(buildDeps());
        final setResult = await registry.run('/setvar', {
          'scope': 'character',
          'path': 'greeting',
          'value': 'hi',
        }, context: const CommandContext(charId: 'c1'));
        expect(setResult.ok, isTrue);

        final getResult = await registry.run('/getvar', {
          'scope': 'character',
          'path': 'greeting',
        }, context: const CommandContext(charId: 'c1'));
        expect(getResult.ok, isTrue);
        expect(getResult.data, 'hi');
      },
    );
  });

  group('/inject validation', () {
    test('rejects missing id', () async {
      final registry = buildWiredCommandRegistry(buildDeps());
      final result = await registry.run('/inject', {
        'content': 'hi',
      }, context: const CommandContext(charId: 'c1'));
      expect(result.ok, isFalse);
      expect(result.message, contains('id'));
    });

    test('rejects missing content', () async {
      final registry = buildWiredCommandRegistry(buildDeps());
      final result = await registry.run('/inject', {
        'id': 'mood',
      }, context: const CommandContext(charId: 'c1'));
      expect(result.ok, isFalse);
      expect(result.message, contains('content'));
    });

    test('rejects missing charId in context', () async {
      final registry = buildWiredCommandRegistry(buildDeps());
      final result = await registry.run('/inject', {
        'id': 'mood',
        'content': 'hi',
      }, context: const CommandContext());
      expect(result.ok, isFalse);
      expect(result.message, contains('charId'));
    });

    test('successful inject echoes the result payload', () async {
      final registry = buildWiredCommandRegistry(buildDeps());
      final result = await registry.run('/inject', {
        'id': 'mood',
        'content': 'tense',
        'depth': 1,
        'role': 'system',
      }, context: const CommandContext(charId: 'c1'));
      expect(result.ok, isTrue);
      expect(result.message, 'inject ok');
      expect(result.data, isA<Map<String, dynamic>>());
      expect((result.data as Map)['id'], 'mood');
      expect((result.data as Map)['depth'], 1);
      expect((result.data as Map)['role'], 'system');
    });
  });

  group('/toast validation', () {
    test('rejects non-string message', () async {
      final registry = buildWiredCommandRegistry(buildDeps());
      final result = await registry.run('/toast', {
        'message': 7,
      }, context: const CommandContext());
      expect(result.ok, isFalse);
      expect(result.message, contains('message'));
    });

    test('successful toast resolves ok', () async {
      final registry = buildWiredCommandRegistry(buildDeps());
      final result = await registry.run('/toast', {
        'message': 'hi',
        'severity': 'success',
        'action': 'open',
      }, context: const CommandContext());
      expect(result.ok, isTrue);
    });
  });

  group('/trigger validation', () {
    test('rejects missing charId in context', () async {
      final registry = buildWiredCommandRegistry(buildDeps());
      final result = await registry.run('/trigger', const {
        'mode': 'auto',
      }, context: const CommandContext());
      expect(result.ok, isFalse);
      expect(result.message, contains('charId'));
    });

    test('rejects non-string mode', () async {
      final registry = buildWiredCommandRegistry(buildDeps());
      final result = await registry.run('/trigger', {
        'mode': 5,
      }, context: const CommandContext(charId: 'c1'));
      expect(result.ok, isFalse);
    });
  });
}
