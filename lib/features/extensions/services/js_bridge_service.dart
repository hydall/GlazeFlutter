import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../core/db/repositories/character_repo.dart';
import '../../../core/db/repositories/chat_repo.dart';
import '../../../core/db/repositories/global_variables_repo.dart';
import '../state/message_variables_notifier.dart';

typedef GenerateTextHandler =
    Future<String> Function(
      String prompt,
      Map<String, dynamic> options,
      Map<String, dynamic> context,
    );

typedef InjectPromptHandler =
    FutureOr<Map<String, dynamic>> Function(
      String id,
      String content,
      Map<String, dynamic> options,
      Map<String, dynamic> context,
    );

typedef UninjectPromptHandler =
    FutureOr<Map<String, dynamic>> Function(
      String id,
      Map<String, dynamic> context,
    );

/// Optional handler for `glaze.triggerGeneration({ mode, reason })`.
///
/// `charId` is the resolved character id from the JS bridge context
/// (`context.characterId` first, then the [_currentCharIdForTrigger]
/// fallback, then null). Returns a structured result the JS SDK can
/// inspect — see [TriggerGenerationHandler].
typedef TriggerGenerationHandlerFn =
    FutureOr<Map<String, dynamic>> Function(
      String? charId,
      Map<String, dynamic> params,
    );

/// Permission lookup. Returns `true` when the current context is
/// allowed to call the glaze capability identified by [capabilityId]
/// (see [GlazeCapability.id]).
typedef PermissionCheck = bool Function(String capabilityId);

/// Snapshot accessor for the [MessageVariablesNotifier]. The bridge
/// never holds onto the notifier directly — the notifier is a Riverpod
/// state notifier and the bridge service is intentionally Riverpod-free
/// for testability. Production code in `ChatWebViewWidget` injects a
/// function that reads from `ref.read(messageVariablesProvider.notifier)`.
typedef MessageVariablesAccessor = MessageVariablesNotifier Function();

/// Audio facade for `glaze.playAudio(source, options)`. Returns when
/// the cue has been handed off to the platform. See [AudioBridgeService].
typedef PlayAudioHandler =
    FutureOr<void> Function(String? source, Map<String, dynamic> options);

/// Slash-command dispatcher. The bridge serializes the result back to
/// the JS SDK as a plain map (`{ ok, message, data }`).
typedef ExecuteCommandHandler =
    FutureOr<Map<String, dynamic>> Function(
      String command,
      Map<String, dynamic> args,
      Map<String, dynamic> context,
    );

/// Toast surface. The MVP `JsBridgeToastController` logs when no
/// overlay is available and calls `GlazeToast.show` when one is.
typedef ShowToastHandler = void Function(
  String? message,
  Map<String, dynamic> options,
);

class JsBridgeService {
  static const _chatVarsKey = '__glaze_variables';
  static const _characterVarsKey = 'glaze_variables';
  static const _maxJsonBytes = 64 * 1024;

  final ChatRepo? _chatRepo;
  final CharacterRepo? _characterRepo;
  final GlobalVariablesRepo? _globalVariablesRepo;
  final MessageVariablesAccessor? _messageVariables;
  final String? Function()? _currentSessionId;
  final String? Function()? _currentCharacterId;
  final GenerateTextHandler? _generateText;
  final InjectPromptHandler? _injectPrompt;
  final UninjectPromptHandler? _uninjectPrompt;
  final TriggerGenerationHandlerFn? _triggerGeneration;
  final PermissionCheck? _permissionCheck;
  final PlayAudioHandler? _playAudio;
  final ExecuteCommandHandler? _executeCommand;
  final ShowToastHandler? _showToast;

  JsBridgeService({
    ChatRepo? chatRepo,
    CharacterRepo? characterRepo,
    GlobalVariablesRepo? globalVariablesRepo,
    MessageVariablesAccessor? messageVariables,
    String? Function()? currentSessionId,
    String? Function()? currentCharacterId,
    GenerateTextHandler? generateText,
    InjectPromptHandler? injectPrompt,
    UninjectPromptHandler? uninjectPrompt,
    TriggerGenerationHandlerFn? triggerGeneration,
    PermissionCheck? permissionCheck,
    PlayAudioHandler? playAudio,
    ExecuteCommandHandler? executeCommand,
    ShowToastHandler? showToast,
  }) : this._(
         chatRepo,
         characterRepo,
         globalVariablesRepo,
         messageVariables,
         currentSessionId,
         currentCharacterId,
         generateText,
         injectPrompt,
         uninjectPrompt,
         triggerGeneration,
         permissionCheck,
         playAudio,
         executeCommand,
         showToast,
       );

  const JsBridgeService._(
    this._chatRepo,
    this._characterRepo,
    this._globalVariablesRepo,
    this._messageVariables,
    this._currentSessionId,
    this._currentCharacterId,
    this._generateText,
    this._injectPrompt,
    this._uninjectPrompt,
    this._triggerGeneration,
    this._permissionCheck,
    this._playAudio,
    this._executeCommand,
    this._showToast,
  );

  Future<Map<String, dynamic>> dispatch(Map<String, dynamic> request) async {
    final method = request['method'] as String? ?? '';
    final params = _asMap(request['params']);

    try {
      final result = await _handle(method, params, _asMap(request['context']));
      return {'ok': true, 'result': result};
    } catch (e, st) {
      debugPrint('[JsBridge] $method failed: $e\n$st');
      return {
        'ok': false,
        'error': {
          'code': e is UnsupportedError
              ? 'unsupported_method'
              : e is ArgumentError
              ? 'invalid_request'
              : 'bridge_error',
          'message': e.toString(),
        },
      };
    }
  }

  FutureOr<dynamic> _handle(
    String method,
    Map<String, dynamic> params,
    Map<String, dynamic> context,
  ) {
    switch (method) {
      case 'showToast':
        _requireCapability('show_toast');
        _handleShowToast(params, context);
        return true;
      case 'getVariables':
        return _handleGetVariables(params, context);
      case 'setVariables':
        return _handleSetVariables(params, context);
      case 'deleteVariable':
        return _handleDeleteVariable(params, context);
      case 'executeCommand':
        _requireCapability('execute_command');
        return _handleExecuteCommand(params, context);
      case 'triggerGeneration':
        _requireCapability('trigger_generation');
        return _handleTriggerGeneration(params, context);
      case 'playAudio':
        _requireCapability('play_audio');
        return _handlePlayAudio(params, context);
      case 'injectPrompt':
        _requireCapability('inject_prompt');
        return _handleInjectPrompt(params, context);
      case 'uninjectPrompt':
        _requireCapability('uninject_prompt');
        return _handleUninjectPrompt(params, context);
      case 'generateText':
        _requireCapability('generate_text');
        return _handleGenerateText(params, context);
      default:
        throw UnsupportedError('Unknown glaze method "$method"');
    }
  }

  void _requireCapability(String capabilityId) {
    final check = _permissionCheck;
    if (check == null) {
      // No permission check registered — treat as deny. The default
      // production path always registers one (see ChatWebViewWidget),
      // so this is a safe fallback for tests.
      throw StateError('Permission denied: $capabilityId (no check)');
    }
    if (!check(capabilityId)) {
      throw StateError('Permission denied: $capabilityId');
    }
  }

  Future<dynamic> _handleGetVariables(
    Map<String, dynamic> params,
    Map<String, dynamic> context,
  ) {
    final scope = _scope(params);
    _requireCapability(_readCapabilityForScope(scope));
    return _getVariables(params, context);
  }

  Future<Map<String, dynamic>> _handleSetVariables(
    Map<String, dynamic> params,
    Map<String, dynamic> context,
  ) {
    final scope = _scope(params);
    _requireCapability(_writeCapabilityForScope(scope));
    return _setVariables(params, context);
  }

  Future<Map<String, dynamic>> _handleDeleteVariable(
    Map<String, dynamic> params,
    Map<String, dynamic> context,
  ) {
    final scope = _scope(params);
    _requireCapability(_deleteCapabilityForScope(scope));
    return _deleteVariable(params, context);
  }

  String _readCapabilityForScope(String scope) {
    switch (scope) {
      case 'chat':
        return 'read_chat_vars';
      case 'character':
        return 'read_character_vars';
      case 'global':
        return 'read_global_vars';
      case 'message':
        return 'read_message_vars';
      default:
        return 'read_chat_vars';
    }
  }

  String _writeCapabilityForScope(String scope) {
    switch (scope) {
      case 'chat':
        return 'write_chat_vars';
      case 'character':
        return 'write_character_vars';
      case 'global':
        return 'write_global_vars';
      case 'message':
        return 'write_message_vars';
      default:
        return 'write_chat_vars';
    }
  }

  String _deleteCapabilityForScope(String scope) {
    switch (scope) {
      case 'chat':
        return 'delete_chat_vars';
      case 'character':
        return 'delete_character_vars';
      case 'global':
        return 'delete_global_vars';
      case 'message':
        return 'delete_message_vars';
      default:
        return 'delete_chat_vars';
    }
  }

  Map<String, dynamic> _asMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  Future<dynamic> _getVariables(
    Map<String, dynamic> params,
    Map<String, dynamic> context,
  ) async {
    final root = await _readScope(_scope(params), context);
    final path = _path(params['path']);
    return _cloneJson(path.isEmpty ? root : _getAtPath(root, path));
  }

  Future<Map<String, dynamic>> _setVariables(
    Map<String, dynamic> params,
    Map<String, dynamic> context,
  ) {
    final path = _path(params['path']);
    final hasValue = params.containsKey('value');
    final value = hasValue ? params['value'] : params['values'];
    _validateJsonValue(value);

    return _updateScope(_scope(params), context, (root) {
      if (path.isEmpty) {
        final values = _asMap(value);
        if (values.isEmpty && value is! Map) {
          throw ArgumentError('setVariables without path requires an object');
        }
        root.addAll(Map<String, dynamic>.from(values));
      } else {
        _setAtPath(root, path, value);
      }
      _validateJsonValue(root);
      return root;
    });
  }

  Future<Map<String, dynamic>> _deleteVariable(
    Map<String, dynamic> params,
    Map<String, dynamic> context,
  ) {
    final path = _path(params['path']);
    if (path.isEmpty) throw ArgumentError('deleteVariable path is required');

    return _updateScope(_scope(params), context, (root) {
      _deleteAtPath(root, path);
      return root;
    });
  }

  FutureOr<Map<String, dynamic>> _handleTriggerGeneration(
    Map<String, dynamic> params,
    Map<String, dynamic> context,
  ) {
    final handler =
        _triggerGeneration ??
        (throw UnsupportedError(
          'glaze.triggerGeneration is not available in this context',
        ));
    final charId = _characterIdOrNull(context);
    return handler(charId, params);
  }

  String? _characterIdOrNull(Map<String, dynamic> context) {
    final raw = context['characterId'];
    if (raw is String && raw.isNotEmpty) return raw;
    final fallback = _currentCharacterId?.call();
    if (fallback == null || fallback.isEmpty) return null;
    return fallback;
  }

  FutureOr<void> _handlePlayAudio(
    Map<String, dynamic> params,
    Map<String, dynamic> context,
  ) {
    final source = params['source'];
    if (source != null && source is! String) {
      throw ArgumentError('playAudio source must be a string');
    }
    final handler =
        _playAudio ??
        (throw UnsupportedError(
          'glaze.playAudio is not available in this context',
        ));
    return handler(source as String?, _asMap(params['options']));
  }

  FutureOr<Map<String, dynamic>> _handleExecuteCommand(
    Map<String, dynamic> params,
    Map<String, dynamic> context,
  ) {
    final command = params['command'];
    if (command is! String || command.isEmpty) {
      throw ArgumentError('executeCommand requires a non-empty string command');
    }
    final handler =
        _executeCommand ??
        (throw UnsupportedError(
          'glaze.executeCommand is not available in this context',
        ));
    return handler(command, _asMap(params['args']), context);
  }

  void _handleShowToast(
    Map<String, dynamic> params,
    Map<String, dynamic> context,
  ) {
    final message = params['message'];
    if (message != null && message is! String) {
      throw ArgumentError('showToast message must be a string');
    }
    final options = _asMap(params['options']);
    final handler =
        _showToast ??
        (msg, _) => debugPrint('[JsBridge] toast: ${msg ?? ''}');
    handler(message as String?, {...options, '_context': context});
  }

  Future<String> _handleGenerateText(
    Map<String, dynamic> params,
    Map<String, dynamic> context,
  ) {
    final prompt = params['prompt'];
    if (prompt is! String || prompt.trim().isEmpty) {
      throw ArgumentError('generateText prompt is required');
    }
    final options = _asMap(params['options']);
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
        _generateText ??
        (throw UnsupportedError(
          'glaze.generateText is not available in this context',
        ));
    return handler(prompt, options, context);
  }

  FutureOr<Map<String, dynamic>> _handleInjectPrompt(
    Map<String, dynamic> params,
    Map<String, dynamic> context,
  ) {
    final id = params['id'];
    if (id is! String || id.trim().isEmpty) {
      throw ArgumentError('injectPrompt id is required');
    }
    final content = params['content'];
    if (content is! String || content.trim().isEmpty) {
      throw ArgumentError('injectPrompt content is required');
    }
    final handler =
        _injectPrompt ??
        (throw UnsupportedError(
          'glaze.injectPrompt is not available in this context',
        ));
    return handler(id, content, _asMap(params['options']), context);
  }

  FutureOr<Map<String, dynamic>> _handleUninjectPrompt(
    Map<String, dynamic> params,
    Map<String, dynamic> context,
  ) {
    final id = params['id'];
    if (id is! String || id.trim().isEmpty) {
      throw ArgumentError('uninjectPrompt id is required');
    }
    final handler =
        _uninjectPrompt ??
        (throw UnsupportedError(
          'glaze.uninjectPrompt is not available in this context',
        ));
    return handler(id, context);
  }

  Future<Map<String, dynamic>> _readScope(
    String scope,
    Map<String, dynamic> context,
  ) async {
    switch (scope) {
      case 'chat':
        final sessionId = _sessionId(context);
        final repo =
            _chatRepo ?? (throw StateError('Chat repo is not available'));
        final session = await repo.getById(sessionId);
        if (session == null) {
          throw StateError('Chat session "$sessionId" was not found');
        }
        return _decodeChatVars(session.sessionVars);
      case 'character':
        final charId = _characterId(context);
        final repo =
            _characterRepo ??
            (throw StateError('Character repo is not available'));
        final character = await repo.getById(charId);
        if (character == null) {
          throw StateError('Character "$charId" was not found');
        }
        return _decodeCharacterVars(character.extensions);
      case 'global':
        final repo = _globalVariablesRepo ??
            (throw StateError('Global variables repo is not available'));
        return await repo.read();
      case 'message':
        return _readMessageScope(context);
      default:
        throw ArgumentError('Unsupported variable scope "$scope"');
    }
  }

  Future<Map<String, dynamic>> _updateScope(
    String scope,
    Map<String, dynamic> context,
    Map<String, dynamic> Function(Map<String, dynamic> root) update,
  ) async {
    switch (scope) {
      case 'chat':
        final sessionId = _sessionId(context);
        final repo =
            _chatRepo ?? (throw StateError('Chat repo is not available'));
        Map<String, dynamic> nextRoot = const {};
        await repo.updateSessionVarsJson(sessionId, (vars) {
          nextRoot = update(_decodeChatVars(vars));
          if (nextRoot.isEmpty) {
            vars.remove(_chatVarsKey);
          } else {
            vars[_chatVarsKey] = jsonEncode(nextRoot);
          }
          return vars;
        });
        return Map<String, dynamic>.from(nextRoot);
      case 'character':
        final charId = _characterId(context);
        final repo =
            _characterRepo ??
            (throw StateError('Character repo is not available'));
        Map<String, dynamic> nextRoot = const {};
        await repo.updateExtensionsJson(charId, (extensions) {
          nextRoot = update(_decodeCharacterVars(extensions));
          if (nextRoot.isEmpty) {
            extensions.remove(_characterVarsKey);
          } else {
            extensions[_characterVarsKey] = nextRoot;
          }
          return extensions;
        });
        return Map<String, dynamic>.from(nextRoot);
      case 'global':
        final repo = _globalVariablesRepo ??
            (throw StateError('Global variables repo is not available'));
        return await repo.update(update);
      case 'message':
        return _updateMessageScope(context, update);
      default:
        throw ArgumentError('Unsupported variable scope "$scope"');
    }
  }

  Map<String, dynamic> _readMessageScope(Map<String, dynamic> context) {
    final accessor = _messageVariables ??
        (throw StateError('Message variables accessor is not available'));
    final sessionId = _sessionId(context);
    final messageId = _messageId(context);
    return accessor().read(sessionId, messageId);
  }

  Map<String, dynamic> _updateMessageScope(
    Map<String, dynamic> context,
    Map<String, dynamic> Function(Map<String, dynamic> root) update,
  ) {
    final accessor = _messageVariables ??
        (throw StateError('Message variables accessor is not available'));
    final sessionId = _sessionId(context);
    final messageId = _messageId(context);
    return accessor().update(sessionId, messageId, update);
  }

  String _messageId(Map<String, dynamic> context) {
    final value = context['messageId'] as String?;
    if (value == null || value.isEmpty) {
      throw StateError('Message id context is not available');
    }
    return value;
  }

  String _scope(Map<String, dynamic> params) {
    final scope = (params['scope'] as String? ?? 'chat').trim().toLowerCase();
    return scope.isEmpty ? 'chat' : scope;
  }

  String _sessionId(Map<String, dynamic> context) {
    final value =
        (context['sessionId'] as String?) ?? _currentSessionId?.call();
    if (value == null || value.isEmpty) {
      throw StateError('Chat session context is not available');
    }
    return value;
  }

  String _characterId(Map<String, dynamic> context) {
    final value =
        (context['characterId'] as String?) ?? _currentCharacterId?.call();
    if (value == null || value.isEmpty) {
      throw StateError('Character context is not available');
    }
    return value;
  }

  List<String> _path(Object? value) {
    if (value == null) return const [];
    if (value is! String) throw ArgumentError('Variable path must be a string');
    final trimmed = value.trim();
    if (trimmed.isEmpty) return const [];
    final parts = trimmed.split('.');
    if (parts.any((p) => p.isEmpty)) {
      throw ArgumentError('Variable path contains an empty segment');
    }
    return parts;
  }

  dynamic _getAtPath(Map<String, dynamic> root, List<String> path) {
    dynamic current = root;
    for (final part in path) {
      if (current is! Map || !current.containsKey(part)) return null;
      current = current[part];
    }
    return current;
  }

  void _setAtPath(Map<String, dynamic> root, List<String> path, Object? value) {
    var current = root;
    for (final part in path.take(path.length - 1)) {
      final existing = current[part];
      final child = existing is Map
          ? Map<String, dynamic>.from(existing)
          : <String, dynamic>{};
      current[part] = child;
      current = child;
    }
    current[path.last] = value;
  }

  void _deleteAtPath(Map<String, dynamic> root, List<String> path) {
    dynamic current = root;
    for (final part in path.take(path.length - 1)) {
      if (current is! Map) return;
      current = current[part];
    }
    if (current is Map) current.remove(path.last);
  }

  Map<String, dynamic> _decodeChatVars(Map<String, dynamic> vars) {
    final raw = vars[_chatVarsKey];
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return <String, dynamic>{};
  }

  Map<String, dynamic> _decodeCharacterVars(Map<String, dynamic> extensions) {
    final raw = extensions[_characterVarsKey];
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return <String, dynamic>{};
  }

  dynamic _cloneJson(Object? value) {
    if (value == null) return null;
    return jsonDecode(jsonEncode(value));
  }

  void _validateJsonValue(Object? value) {
    void visit(Object? current) {
      if (current == null || current is bool || current is String) return;
      if (current is num) {
        if (!current.isFinite) {
          throw ArgumentError('JSON numbers must be finite');
        }
        return;
      }
      if (current is List) {
        for (final item in current) {
          visit(item);
        }
        return;
      }
      if (current is Map) {
        for (final entry in current.entries) {
          if (entry.key is! String) {
            throw ArgumentError('JSON object keys must be strings');
          }
          visit(entry.value);
        }
        return;
      }
      throw ArgumentError('Value is not JSON-compatible');
    }

    visit(value);
    if (utf8.encode(jsonEncode(value)).length > _maxJsonBytes) {
      throw ArgumentError('Variable payload exceeds $_maxJsonBytes bytes');
    }
  }
}
