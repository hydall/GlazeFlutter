import 'dart:async';

import 'package:collection/collection.dart';
import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/llm/sse_client.dart';
import '../../../core/state/db_provider.dart';
import '../../extensions/models/connection_profiles.dart';
import '../../extensions/models/preset_permissions.dart';
import '../../extensions/models/trigger_mode.dart';
import '../../extensions/models/trigger_result.dart';
import '../../extensions/providers/extension_presets_provider.dart';
import '../../extensions/providers/extensions_settings_provider.dart';
import '../../extensions/providers/global_variables_repo_provider.dart';
import '../../extensions/providers/preset_permissions_provider.dart';
import '../../extensions/services/audio_bridge_service.dart';
import '../../extensions/services/command_registry.dart';
import '../../extensions/services/connection_profile_resolver.dart';
import '../../extensions/services/generation_dispatcher.dart';
import '../../extensions/services/js_bridge_service.dart';
import '../../extensions/services/js_bridge_toast_controller.dart';
import '../../extensions/services/runtime_prompt_injection_service.dart';
import '../../extensions/services/trigger_generation_handler.dart';
import '../../extensions/state/message_variables_notifier.dart';
import '../../settings/api_list_provider.dart';

/// Owns the chat WebView's bridge-side dependencies: the [JsBridgeService]
/// handler implementations (generateText / injectPrompt / uninjectPrompt /
/// triggerGeneration / playAudio / showToast / executeCommand), the
/// permission gate, and the long-lived helper instances
/// (audio bridge, toast controller, command registry, trigger handler,
/// prompt injection notifier).
///
/// Extracted from [ChatWebViewWidget] so the widget only has to call
/// [buildJsBridgeService] in `onWebViewCreated` and [dispose] on teardown.
/// All Riverpod reads still happen through the [WidgetRef] provided at
/// construction time, so the host follows the widget's lifecycle
/// (ref → widget) one-to-one.
class ChatWebViewBridgeHost {
  ChatWebViewBridgeHost({
    required this.ref,
    required this.overlayContextResolver,
    required this.currentSessionId,
    required this.currentCharacterId,
  });

  final WidgetRef ref;
  final BuildContext? Function() overlayContextResolver;
  final String? Function() currentSessionId;
  final String? Function() currentCharacterId;

  static const ConnectionProfileResolver _profileResolver =
      ConnectionProfileResolver();

  final AudioBridgeService _audioBridge = AudioBridgeService();

  final JsBridgeToastController _toastController = JsBridgeToastController();

  late final TriggerGenerationHandler _triggerHandler = TriggerGenerationHandler(
    dispatcher: ref.read(generationDispatcherProvider),
    log: (line) => debugPrint(line),
  );

  late final RuntimePromptInjectionNotifier _promptInjection =
      ref.read(runtimePromptInjectionProvider.notifier);

  late final CommandRegistry _commandRegistry = _buildWiredCommandRegistry();

  /// Resolves the preset permissions for the current preset, returning
  /// `false` (default-deny) if the lookup fails. Mirrors the previous
  /// in-widget `_bridgePermissionCheck`.
  bool _bridgePermissionCheck(String capabilityId) {
    try {
      final permissions = ref.read(activePresetPermissionsProvider);
      return permissions.isGrantedById(capabilityId);
    } catch (_) {
      return false;
    }
  }

  /// Slash-command registry. The wired registry routes `/trigger`,
  /// `/getvar`, `/setvar`, `/inject`, and `/toast` to the same services
  /// as the dedicated bridge methods (so permissions / scope / JSON
  /// validation are preserved end-to-end).
  CommandRegistry _buildWiredCommandRegistry() {
    return buildWiredCommandRegistry(
      WiredCommandDeps(
        bridge: JsBridgeService(
          chatRepo: ref.read(chatRepoProvider),
          characterRepo: ref.read(characterRepoProvider),
          currentSessionId: currentSessionId,
          currentCharacterId: currentCharacterId,
          permissionCheck: _bridgePermissionCheck,
          messageVariables: () => ref.read(messageVariablesProvider.notifier),
        ),
        toastController: _toastController,
        promptInjection: _promptInjection,
        triggerHandler: _triggerHandler,
      ),
    );
  }

  /// Build a fresh [JsBridgeService] wired to the current widget state.
  /// Called from `onWebViewCreated` and from any code path that needs to
  /// (re)create the bridge service (e.g. the wired `/getvar`/``/setvar``
  /// registry which only needs the deps subset).
  Future<JsBridgeService> buildJsBridgeService() async {
    final globalRepo = await ref.read(globalVariablesRepoProvider.future);
    return JsBridgeService(
      chatRepo: ref.read(chatRepoProvider),
      characterRepo: ref.read(characterRepoProvider),
      globalVariablesRepo: globalRepo,
      messageVariables: () => ref.read(messageVariablesProvider.notifier),
      currentSessionId: currentSessionId,
      currentCharacterId: currentCharacterId,
      generateText: _generateBridgeText,
      injectPrompt: _injectBridgePrompt,
      uninjectPrompt: _uninjectBridgePrompt,
      triggerGeneration: _triggerBridgeGeneration,
      permissionCheck: _bridgePermissionCheck,
      playAudio: _playBridgeAudio,
      executeCommand: _executeBridgeCommand,
      showToast: _showBridgeToast,
    );
  }

  Future<String> _generateBridgeText(
    String prompt,
    Map<String, dynamic> options,
    Map<String, dynamic> bridgeContext,
  ) async {
    await ref.read(apiListProvider.future);
    final configs = ref.read(apiListProvider).valueOrNull ?? const [];
    final activeApiConfig = ref.read(activeApiConfigProvider);
    final profile = ConnectionProfileX.parse(options['preset']) ??
        ConnectionProfile.medium;
    final activePresetId =
        ref.read(extensionsSettingsProvider).activePresetId;
    final preset = activePresetId == null
        ? null
        : ref
            .read(extensionPresetsProvider)
            .where((p) => p.id == activePresetId)
            .firstOrNull;
    final apiConfig = _profileResolver.resolve(
      preset,
      profile,
      activeApiConfig,
      configs,
    );
    if (apiConfig == null) {
      throw StateError('No active API config available');
    }
    if (apiConfig.endpoint.isEmpty || apiConfig.model.isEmpty) {
      throw StateError('Active API config is incomplete');
    }

    final cancelToken = CancelToken();
    final completer = Completer<String>();
    unawaited(
      SseClient().streamChatCompletion(
        endpoint: apiConfig.endpoint,
        apiKey: apiConfig.apiKey,
        model: apiConfig.model,
        messages: [
          {'role': 'user', 'content': prompt},
        ],
        maxTokens: apiConfig.maxTokens,
        temperature: apiConfig.temperature,
        topP: apiConfig.topP,
        stream: false,
        cancelToken: cancelToken,
        requestReasoning: apiConfig.requestReasoning,
        reasoningEffort: apiConfig.reasoningEffort,
        omitTemperature: apiConfig.omitTemperature,
        omitTopP: apiConfig.omitTopP,
        omitReasoning: apiConfig.omitReasoning,
        omitReasoningEffort: apiConfig.omitReasoningEffort,
        sessionId: currentSessionId(),
        cacheControlTtl: apiConfig.cacheControlTtl,
        onComplete: (text, _, {rawResponseJson}) {
          if (!completer.isCompleted) completer.complete(text);
        },
        onError: (error) {
          if (!completer.isCompleted) completer.completeError(error);
        },
      ),
    );
    return completer.future.timeout(
      const Duration(seconds: 55),
      onTimeout: () {
        cancelToken.cancel('glaze.generateText timed out');
        throw TimeoutException('glaze.generateText timed out');
      },
    );
  }

  Map<String, dynamic> _injectBridgePrompt(
    String id,
    String content,
    Map<String, dynamic> options,
    Map<String, dynamic> bridgeContext,
  ) {
    final sessionId =
        (bridgeContext['sessionId'] as String?) ?? currentSessionId();
    if (sessionId == null || sessionId.isEmpty) {
      throw StateError('Chat session context is not available');
    }
    final rawDepth = options['depth'];
    final depth = rawDepth == null
        ? 0
        : rawDepth is int
        ? rawDepth
        : throw ArgumentError('injectPrompt depth must be an integer');
    final rawRole = options['role'];
    if (rawRole != null && rawRole is! String) {
      throw ArgumentError('injectPrompt role must be a string');
    }
    final role = rawRole as String? ?? 'system';
    final injected = ref
        .read(runtimePromptInjectionProvider.notifier)
        .inject(
          sessionId: sessionId,
          id: id,
          content: content,
          depth: depth,
          role: role,
        );
    return {'id': injected.id, 'depth': injected.depth, 'role': injected.role};
  }

  Map<String, dynamic> _uninjectBridgePrompt(
    String id,
    Map<String, dynamic> bridgeContext,
  ) {
    final sessionId =
        (bridgeContext['sessionId'] as String?) ?? currentSessionId();
    if (sessionId == null || sessionId.isEmpty) {
      throw StateError('Chat session context is not available');
    }
    final removed = ref
        .read(runtimePromptInjectionProvider.notifier)
        .uninject(sessionId: sessionId, id: id);
    return {'id': id.trim(), 'removed': removed};
  }

  Future<Map<String, dynamic>> _triggerBridgeGeneration(
    String? charId,
    Map<String, dynamic> params,
  ) async {
    final resolvedCharId =
        (params['characterId'] as String?) ??
        (charId) ??
        currentCharacterId();
    if (resolvedCharId == null || resolvedCharId.isEmpty) {
      return TriggerNoSession(mode: TriggerMode.auto).toMap();
    }
    final dispatcher = ref.read(generationDispatcherProvider);
    final handler = TriggerGenerationHandler(
      dispatcher: dispatcher,
      log: (line) => debugPrint(line),
    );
    return handler.handle(charId: resolvedCharId, params: params);
  }

  Future<void> _playBridgeAudio(
    String? source,
    Map<String, dynamic> options,
  ) {
    return _audioBridge.play(source, options);
  }

  void _showBridgeToast(String? message, Map<String, dynamic> options) {
    final severity = GlazeToastSeverity.parse(options['severity'] as String?);
    // Re-resolve the BuildContext on every call so the toast surfaces
    // from the currently mounted screen, not the snapshot at bridge init.
    _toastController.overlayResolver = overlayContextResolver;
    _toastController.show(
      message,
      severity: severity,
      actionLabel: options['action'] as String?,
    );
  }

  Future<Map<String, dynamic>> _executeBridgeCommand(
    String command,
    Map<String, dynamic> args,
    Map<String, dynamic> context,
  ) async {
    final result = await _commandRegistry.run(
      command,
      args,
      context: CommandContext(
        charId: currentCharacterId(),
        presetId: ref.read(extensionsSettingsProvider).activePresetId,
      ),
    );
    return result.toMap();
  }

  /// Release long-lived resources owned by this host. Called from the
  /// widget's [State.dispose]. Mirrors the previous in-widget disposal
  /// path: drop the audio player.
  Future<void> dispose() async {
    await _audioBridge.dispose();
  }
}
