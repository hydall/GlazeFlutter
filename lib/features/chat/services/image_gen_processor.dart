import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/api_config.dart';
import '../../../core/models/chat_message.dart';
import '../../../core/state/active_selection_provider.dart';
import '../../../core/state/db_provider.dart';
import '../../../core/utils/time_helpers.dart';
import '../../../shared/widgets/glaze_toast.dart';
import '../../image_gen/image_gen_provider.dart';
import '../../settings/api_list_provider.dart';
import '../../image_gen/services/image_tag_markup.dart';
import '../chat_session_service.dart';
import '../chat_state.dart';

class ImageGenProcessor {
  final Ref _ref;
  final String _charId;
  final CancelToken? _cancelToken;
  final bool Function()? isCurrentOperation;
  final void Function(ChatState) _onStateUpdate;

  ImageGenProcessor({
    required this._ref,
    required this._charId,
    this._cancelToken,
    this.isCurrentOperation,
    required this._onStateUpdate,
  });

  Future<void> process(ChatState currentState) async {
    final session = currentState.session;
    if (session == null) return;

    final imgGenSettingsAsync = _ref.read(imageGenSettingsProvider);
    if (imgGenSettingsAsync.isLoading) {
      final imgGenSettings = await _ref.read(imageGenSettingsProvider.future);
      if (!imgGenSettings.enabled) return;
    } else {
      final imgGenSettings = imgGenSettingsAsync.value;
      if (imgGenSettings == null || !imgGenSettings.enabled) return;
    }
    final imgGenSettings = await _ref.read(imageGenSettingsProvider.future);

    final lastIdx = session.messages.length - 1;
    if (lastIdx < 0) return;
    final lastMsg = session.messages[lastIdx];
    if (lastMsg.role != 'assistant') return;

    final notifier = _ref.read(imageGenSettingsProvider.notifier);
    final service = await notifier.getServiceAsync();
    if (!ImageTagMarkup.hasImageGenTags(lastMsg.content)) return;

    final apiConfigSync = _ref.read(activeApiConfigProvider);
    final ApiConfig apiConfig;
    if (apiConfigSync != null) {
      apiConfig = apiConfigSync;
    } else {
      final apiList = await _ref.read(apiListProvider.future);
      if (apiList.isEmpty) return;
      final activeId = _ref.read(activeApiPresetIdProvider);
      apiConfig = activeId != null
          ? apiList.firstWhere(
              (c) => c.id == activeId,
              orElse: () => apiList.first,
            )
          : apiList.first;
    }

    final charRepo = _ref.read(characterRepoProvider);
    final character = await charRepo.getById(_charId);

    final personaRepo = _ref.read(personaRepoProvider);
    final personas = await personaRepo.getAll();
    final connections = _ref.read(personaConnectionsProvider);
    final activePersonaId = _ref.read(activePersonaIdProvider);
    final persona = getEffectivePersona(
      personas,
      _charId,
      session.id,
      activePersonaId,
      connections,
    );

    final recentContexts = _collectRecentImageContexts(session.messages);
    var latestSession = session;
    if (!_ownsOperation) return;

    debugPrint('[IMGGEN] → setting isGeneratingImage=true');
    _onStateUpdate(
      currentState.copyWith(session: latestSession, isGeneratingImage: true),
    );

    try {
      final updatedContent = await service.processMessageImages(
        text: lastMsg.content,
        settings: imgGenSettings,
        llmEndpoint: apiConfig.endpoint,
        llmApiKey: apiConfig.apiKey,
        llmModel: apiConfig.model,
        character: character,
        persona: persona,
        recentImageContexts: recentContexts,
        cancelToken: _cancelToken,
        onUpdate: (updatedText) {
          // A cancellation may race an image provider's progress callback.
          // Ownership checks at the caller prevent callbacks from an old
          // operation from reaching a replacement generation.
          if (!_ownsOperation) return;
          latestSession = _replaceLastMessage(
            session,
            lastIdx,
            lastMsg,
            updatedText,
          );
          _onStateUpdate(
            currentState.copyWith(
              session: latestSession,
              isGeneratingImage: true,
            ),
          );
        },
        onError: (error) {
          debugPrint('[IMGGEN] onError: $error');
          GlazeToast.showWithoutContext(
            'Image gen: $error',
            isError: true,
            duration: 4000,
          );
        },
      );

      if (!_ownsOperation) return;

      if (_cancelToken?.isCancelled == true) {
        var cancelContent = updatedContent;
        int idx = 0;
        while (ImageTagMarkup.hasImageGenTags(cancelContent)) {
          cancelContent = ImageTagMarkup.replaceTagWithError(
            cancelContent,
            idx,
            'Cancelled by user',
          );
          idx++;
        }
        latestSession = _replaceLastMessage(
          session,
          lastIdx,
          lastMsg,
          cancelContent,
        );
        return;
      }

      latestSession = _replaceLastMessage(
        session,
        lastIdx,
        lastMsg,
        updatedContent,
      );
      await _ref.read(chatRepoProvider).put(latestSession);
      ChatSessionService.updateCache(latestSession);
    } on DioException catch (e) {
      if (!CancelToken.isCancel(e)) rethrow;
    } finally {
      // This must run even when the final repository write fails. The caller
      // accepts this update only while the originating operation still owns
      // the active generation/session.
      if (_ownsOperation) {
        _onStateUpdate(
          currentState.copyWith(
            session: latestSession,
            isGeneratingImage: false,
          ),
        );
      }
    }
  }

  static ChatState? mergeOwnedStateUpdate({
    required ChatState? liveState,
    required ChatState update,
    required String sessionId,
    required bool ownsOperation,
  }) {
    if (!ownsOperation ||
        liveState == null ||
        liveState.session?.id != sessionId ||
        update.session?.id != sessionId) {
      return null;
    }

    return liveState.copyWith(
      session: update.session,
      isGeneratingImage: update.isGeneratingImage,
    );
  }

  ChatSession _replaceLastMessage(
    ChatSession session,
    int lastIdx,
    ChatMessage lastMsg,
    String content,
  ) {
    final newMessages = List<ChatMessage>.from(session.messages);
    final swipeIdx = lastMsg.swipeId;
    final updatedSwipes =
        lastMsg.swipes.isNotEmpty &&
            swipeIdx >= 0 &&
            swipeIdx < lastMsg.swipes.length
        ? (List<String>.from(lastMsg.swipes)..[swipeIdx] = content)
        : lastMsg.swipes;
    newMessages[lastIdx] = lastMsg.copyWith(
      content: content,
      swipes: updatedSwipes,
    );
    return session.copyWith(
      messages: newMessages,
      updatedAt: currentTimestampSeconds(),
    );
  }

  bool get _ownsOperation =>
      isCurrentOperation?.call() ?? !(_cancelToken?.isCancelled ?? false);

  List<String> _collectRecentImageContexts(List<ChatMessage> messages) {
    final contexts = <String>[];
    for (int i = messages.length - 1; i >= 0 && contexts.length < 3; i--) {
      final paths = ImageTagMarkup.extractImageResultPaths(messages[i].content);
      contexts.addAll(paths);
    }
    return contexts.reversed.toList();
  }
}
