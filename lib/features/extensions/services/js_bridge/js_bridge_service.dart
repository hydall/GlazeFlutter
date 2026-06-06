import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../core/db/repositories/character_repo.dart';
import '../../../../core/db/repositories/chat_repo.dart';
import '../../../../core/db/repositories/global_variables_repo.dart';
import 'handlers/audio_handler.dart';
import 'handlers/command_handler.dart';
import 'handlers/generation_handler.dart';
import 'handlers/prompt_injection_handler.dart';
import 'handlers/toast_handler.dart';
import 'handlers/variables_handler.dart';
import 'js_bridge_context.dart';

export 'js_bridge_context.dart'
    show
        ExecuteCommandHandler,
        GenerateTextHandler,
        InjectPromptHandler,
        MessageVariablesAccessor,
        PermissionCheck,
        PlayAudioHandler,
        ShowToastHandler,
        TriggerGenerationHandlerFn,
        UninjectPromptHandler;

class JsBridgeService {
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

  final VariablesHandler _variablesHandler;
  final GenerationHandler _generationHandler;
  final PromptInjectionHandler _promptInjectionHandler;
  final AudioHandler _audioHandler;
  final CommandHandler _commandHandler;
  final ToastHandler _toastHandler;

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
         const VariablesHandler(),
         const GenerationHandler(),
         const PromptInjectionHandler(),
         const AudioHandler(),
         const CommandHandler(),
         const ToastHandler(),
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
    this._variablesHandler,
    this._generationHandler,
    this._promptInjectionHandler,
    this._audioHandler,
    this._commandHandler,
    this._toastHandler,
  );

  Future<Map<String, dynamic>> dispatch(Map<String, dynamic> request) async {
    final method = request['method'] as String? ?? '';
    final params = asBridgeMap(request['params']);

    try {
      final result = await _handle(
        method,
        params,
        asBridgeMap(request['context']),
      );
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
    final bridge = JsBridgeContext(
      params: params,
      context: context,
      chatRepo: _chatRepo,
      characterRepo: _characterRepo,
      globalVariablesRepo: _globalVariablesRepo,
      messageVariables: _messageVariables,
      currentSessionId: _currentSessionId,
      currentCharacterId: _currentCharacterId,
      generateText: _generateText,
      injectPrompt: _injectPrompt,
      uninjectPrompt: _uninjectPrompt,
      triggerGeneration: _triggerGeneration,
      permissionCheck: _permissionCheck,
      playAudio: _playAudio,
      executeCommand: _executeCommand,
      showToast: _showToast,
    );

    switch (method) {
      case 'showToast':
        return _toastHandler.showToast(bridge);
      case 'getVariables':
        return _variablesHandler.getVariables(bridge);
      case 'setVariables':
        return _variablesHandler.setVariables(bridge);
      case 'deleteVariable':
        return _variablesHandler.deleteVariable(bridge);
      case 'executeCommand':
        return _commandHandler.executeCommand(bridge);
      case 'triggerGeneration':
        return _generationHandler.triggerGeneration(bridge);
      case 'playAudio':
        return _audioHandler.playAudio(bridge);
      case 'injectPrompt':
        return _promptInjectionHandler.injectPrompt(bridge);
      case 'uninjectPrompt':
        return _promptInjectionHandler.uninjectPrompt(bridge);
      case 'generateText':
        return _generationHandler.generateText(bridge);
      default:
        throw UnsupportedError('Unknown glaze method "$method"');
    }
  }
}
