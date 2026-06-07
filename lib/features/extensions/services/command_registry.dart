import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/trigger_mode.dart';
import 'js_bridge_service.dart';
import 'js_bridge_toast_controller.dart';
import 'runtime_prompt_injection_service.dart';
import 'trigger_generation_handler.dart';

/// One executable glaze slash-command. Commands are the audit-friendly
/// alternative to direct method calls — they show up clearly in
/// `CommandRegistry.list()`, can be tested in isolation, and can be
/// re-used by features other than the JS bridge (e.g. the chat input
/// bar could accept `/command` invocations in the future).
///
/// The MVP command set is intentionally small: `/trigger`, `/getvar`,
/// `/setvar`, `/inject`, `/toast`. Full STScript compatibility is out of
/// scope per the plan.
class GlazeCommand {
  const GlazeCommand({
    required this.name,
    required this.summary,
    required this.handler,
  });

  /// The slash-prefixed name (e.g. `'/trigger'`). Always starts with `/`.
  final String name;

  /// Short human-readable description for the editor / docs.
  final String summary;

  /// Async handler. `args` is whatever the caller passed — for the JS
  /// bridge it's the JS `params.args` object. The handler must NEVER
  /// throw — it must return a [CommandResult] describing success or
  /// failure so the bridge can serialize the result back to JS.
  final FutureOr<CommandResult> Function(
    Map<String, dynamic> args,
    CommandContext context,
  ) handler;
}

/// Per-call context. The dispatcher fills in `charId` and `presetId`
/// from the caller. The handler can use it to address the right
/// character/preset.
class CommandContext {
  const CommandContext({this.charId, this.presetId});

  final String? charId;
  final String? presetId;
}

/// Result of a `/command` invocation. The bridge serializes this back
/// to the JS SDK. `ok: true` makes the promise resolve, `ok: false`
/// makes the SDK throw.
class CommandResult {
  const CommandResult({required this.ok, this.message, this.data});

  const CommandResult.ok({String? message, Object? data})
      : this(ok: true, message: message, data: data);

  const CommandResult.error(String message)
      : this(ok: false, message: message);

  final bool ok;
  final String? message;
  final Object? data;

  Map<String, dynamic> toMap() => {
    'ok': ok,
    if (message != null) 'message': message,
    if (data != null) 'data': data,
  };
}

/// Lookup-based command registry. The MVP ships with five commands
/// (`/trigger`, `/getvar`, `/setvar`, `/inject`, `/toast`). The
/// registry is a plain `Map<String, GlazeCommand>` exposed via
/// `list()` for the UI.
class CommandRegistry {
  CommandRegistry();

  final Map<String, GlazeCommand> _commands = {};

  /// Register or replace a command. Returns `this` for chaining.
  CommandRegistry register(GlazeCommand command) {
    if (!command.name.startsWith('/')) {
      throw ArgumentError(
        'Command name must start with "/" (got "${command.name}")',
      );
    }
    _commands[command.name] = command;
    return this;
  }

  /// Run a command. Unknown commands return a `CommandResult.error`
  /// with the available-command list appended.
  Future<CommandResult> run(
    String name,
    Map<String, dynamic> args, {
    CommandContext context = const CommandContext(),
  }) async {
    final cmd = _commands[name];
    if (cmd == null) {
      return CommandResult.error(
        'Unknown command "$name". Available: ${_commands.keys.join(", ")}',
      );
    }
    try {
      return await cmd.handler(args, context);
    } catch (e) {
      if (kDebugMode) debugPrint('[CommandRegistry] $name failed: $e');
      return CommandResult.error(e.toString());
    }
  }

  /// Returns the registered commands. Used by the editor UI and by
  /// the bridge's help text.
  List<GlazeCommand> list() => _commands.values.toList(growable: false);
}

/// Dependencies for [WiredCommandRegistry] — the production path that
/// dispatches `/trigger`, `/getvar`, `/setvar`, `/inject`, `/toast`
/// to the same services the dedicated bridge methods use.
class WiredCommandDeps {
  const WiredCommandDeps({
    required this.bridge,
    required this.toastController,
    required this.promptInjection,
    required this.triggerHandler,
  });

  /// The live [JsBridgeService] to delegate `/getvar` and `/setvar` to.
  /// We re-use the existing dispatcher so scope, permission, and JSON
  /// validation are identical to the dedicated `glaze.getVariables` /
  /// `glaze.setVariables` paths.
  final JsBridgeService bridge;

  /// Toast surface for `/toast`. Mirrors the dedicated `glaze.showToast`
  /// bridge.
  final JsBridgeToastController toastController;

  /// Runtime prompt injection service for `/inject`.
  final RuntimePromptInjectionNotifier promptInjection;

  /// Trigger handler for `/trigger`. Mirrors the dedicated
  /// `glaze.triggerGeneration` bridge.
  final TriggerGenerationHandler triggerHandler;
}

/// Builds a [CommandRegistry] whose handlers are wired to the real
/// services. The MVP commands route to the same code paths as the
/// dedicated bridge methods so the bridge's permission / scope / JSON
/// invariants are preserved end-to-end.
CommandRegistry buildWiredCommandRegistry(WiredCommandDeps deps) {
  final registry = CommandRegistry();

  registry.register(
    GlazeCommand(
      name: '/trigger',
      summary: 'Trigger a chat generation. Args: { mode?: "continue" | "regenerate" | "auto", reason?: string }',
      handler: (args, context) async {
        final charId = context.charId;
        if (charId == null || charId.isEmpty) {
          return const CommandResult.error(
            '/trigger: charId is required',
          );
        }
        final result = await deps.triggerHandler.handle(
          charId: charId,
          params: args,
        );
        return CommandResult.ok(
          message: 'trigger dispatched',
          data: result,
        );
      },
    ),
  );

  registry.register(
    GlazeCommand(
      name: '/getvar',
      summary: 'Read a JS variable. Args: { scope: "chat"|"character"|"global"|"message", path?: string }',
      handler: (args, context) async {
        // `/getvar` is the same as the dedicated `glaze.getVariables`
        // method, routed through the bridge's own dispatcher. We
        // forward the call so the same JSON-validity / permission /
        // path semantics apply.
        final path = args['path'];
        final params = <String, dynamic>{
          'scope': args['scope'] ?? 'chat',
          'path': ?path,
        };
        final response = await deps.bridge.dispatch({
          'method': 'getVariables',
          'params': params,
          'context': {
            if (context.charId != null) 'characterId': context.charId,
          },
        });
        if (response['ok'] != true) {
          return CommandResult.error(
            (response['error']?['message'] as String?) ?? 'getvar failed',
          );
        }
        return CommandResult.ok(
          message: 'getvar ok',
          data: response['result'],
        );
      },
    ),
  );

  registry.register(
    GlazeCommand(
      name: '/setvar',
      summary: 'Write a JS variable. Args: { scope, path?, value? | values? }',
      handler: (args, context) async {
        final params = <String, dynamic>{
          'scope': args['scope'] ?? 'chat',
        };
        if (args.containsKey('path')) {
          params['path'] = args['path'];
        }
        if (args.containsKey('value')) {
          params['value'] = args['value'];
        } else if (args.containsKey('values')) {
          params['values'] = args['values'];
        }
        final response = await deps.bridge.dispatch({
          'method': 'setVariables',
          'params': params,
          'context': {
            if (context.charId != null) 'characterId': context.charId,
          },
        });
        if (response['ok'] != true) {
          return CommandResult.error(
            (response['error']?['message'] as String?) ?? 'setvar failed',
          );
        }
        return CommandResult.ok(message: 'setvar ok', data: response['result']);
      },
    ),
  );

  registry.register(
    GlazeCommand(
      name: '/inject',
      summary: 'Inject a runtime prompt block. Args: { id, content, depth?, role? }',
      handler: (args, context) async {
        final charId = context.charId;
        if (charId == null || charId.isEmpty) {
          return const CommandResult.error('/inject: charId is required');
        }
        final id = args['id'];
        final content = args['content'];
        if (id is! String || id.trim().isEmpty) {
          return const CommandResult.error('/inject: id is required');
        }
        if (content is! String || content.trim().isEmpty) {
          return const CommandResult.error('/inject: content is required');
        }
        final rawDepth = args['depth'];
        final depth = rawDepth is int
            ? rawDepth
            : (rawDepth is num ? rawDepth.toInt() : 0);
        final role = (args['role'] as String?) ?? 'system';
        // The injected block is session-scoped; we use a derived
        // sessionId from the charId. Production code stores this on
        // the active chat session; here we rely on the chat notifier
        // having already established a session for this charId. The
        // handler does NOT need a sessionId at the call site — the
        // notifier resolves it lazily from the chat state.
        // The `id` doubles as the persistence key.
        final result = deps.promptInjection.inject(
          sessionId: charId,
          id: id,
          content: content,
          depth: depth,
          role: role,
        );
        return CommandResult.ok(
          message: 'inject ok',
          data: {'id': result.id, 'depth': result.depth, 'role': result.role},
        );
      },
    ),
  );

  registry.register(
    GlazeCommand(
      name: '/toast',
      summary: 'Show a toast. Args: { message, severity?: "info"|"success"|"warning"|"error", action?: string }',
      handler: (args, context) async {
        final message = args['message'];
        if (message is! String) {
          return const CommandResult.error('/toast: message is required');
        }
        final severity = GlazeToastSeverity.parse(args['severity'] as String?);
        final action = args['action'] as String?;
        deps.toastController.show(
          message,
          severity: severity,
          actionLabel: action,
        );
        return CommandResult.ok(message: 'toast shown');
      },
    ),
  );

  return registry;
}

/// Convenience builder that wires up the MVP commands with the default
/// echo behaviour. **The echo registry is for unit tests, CMS, and
/// discovery tooling only** — production wiring should use
/// [buildWiredCommandRegistry] so the `/trigger`, `/getvar`, `/setvar`,
/// `/inject`, and `/toast` commands actually do something.
CommandRegistry buildDefaultCommandRegistry() {
  final registry = CommandRegistry();
  registry.register(
    GlazeCommand(
      name: '/trigger',
      summary: 'Trigger a chat generation. Args: { mode?: "continue" | "regenerate" | "auto" }',
      handler: (args, context) async {
        return CommandResult.ok(
          message: 'trigger ${args['mode'] ?? TriggerMode.auto.name} '
              'for charId=${context.charId ?? '(none)'}',
        );
      },
    ),
  );
  registry.register(
    GlazeCommand(
      name: '/getvar',
      summary: 'Read a JS variable. Args: { scope: "chat"|"character"|"global"|"message", path: string }',
      handler: (args, context) async {
        return CommandResult.ok(
          message: 'getvar scope=${args['scope']} path=${args['path']}',
        );
      },
    ),
  );
  registry.register(
    GlazeCommand(
      name: '/setvar',
      summary: 'Write a JS variable. Args: { scope, path?, values? }',
      handler: (args, context) async {
        return CommandResult.ok(
          message: 'setvar scope=${args['scope']}',
        );
      },
    ),
  );
  registry.register(
    GlazeCommand(
      name: '/inject',
      summary: 'Inject a runtime prompt block. Args: { id, content, depth?, role? }',
      handler: (args, context) async {
        return CommandResult.ok(message: 'inject id=${args['id']}');
      },
    ),
  );
  registry.register(
    GlazeCommand(
      name: '/toast',
      summary: 'Show a toast. Args: { message, severity? }',
      handler: (args, context) async {
        return CommandResult.ok(message: 'toast: ${args['message']}');
      },
    ),
  );
  return registry;
}
