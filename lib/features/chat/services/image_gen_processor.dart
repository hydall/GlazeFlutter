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
import '../../image_gen/services/image_gen_service.dart';
import '../chat_state.dart';

class ImageGenProcessor {
  final Ref _ref;
  final String _charId;
  final CancelToken? _cancelToken;
  final void Function(ChatState) _onStateUpdate;

  ImageGenProcessor({
    required Ref ref,
    required String charId,
    CancelToken? cancelToken,
    required void Function(ChatState) onStateUpdate,
  })  : _ref = ref,
        _charId = charId,
        _cancelToken = cancelToken,
        _onStateUpdate = onStateUpdate;

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
    if (!service.hasImageGenTags(lastMsg.content)) return;

    final apiConfigSync = _ref.read(activeApiConfigProvider);
    final ApiConfig apiConfig;
    if (apiConfigSync != null) {
      apiConfig = apiConfigSync;
    } else {
      final apiList = await _ref.read(apiListProvider.future);
      if (apiList.isEmpty) return;
      final activeId = _ref.read(activeApiPresetIdProvider);
      apiConfig = activeId != null
          ? apiList.firstWhere((c) => c.id == activeId, orElse: () => apiList.first)
          : apiList.first;
    }

    final charRepo = _ref.read(characterRepoProvider);
    final character = await charRepo.getById(_charId);

    final personaRepo = _ref.read(personaRepoProvider);
    final personas = await personaRepo.getAll();
    final connections = _ref.read(personaConnectionsProvider);
    final activePersonaId = _ref.read(activePersonaIdProvider);
    final persona = getEffectivePersona(
      personas, _charId, session.id, activePersonaId, connections,
    );

    final recentContexts = _collectRecentImageContexts(session.messages);

    debugPrint('[IMGGEN] → setting isGeneratingImage=true');
    _onStateUpdate(currentState.copyWith(session: session, isGeneratingImage: true));

    String updatedContent;
    try {
      updatedContent = await service.processMessageImages(
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
          final newMessages = List<ChatMessage>.from(session.messages);
          final swipeIdx = lastMsg.swipeId;
          final updatedSwipes = lastMsg.swipes.isNotEmpty && swipeIdx >= 0 && swipeIdx < lastMsg.swipes.length
              ? (List<String>.from(lastMsg.swipes)..[swipeIdx] = updatedText)
              : lastMsg.swipes;
          newMessages[lastIdx] = lastMsg.copyWith(content: updatedText, swipes: updatedSwipes);
          final updatedSession = session.copyWith(
            messages: newMessages,
            updatedAt: currentTimestampSeconds(),
          );
          _onStateUpdate(currentState.copyWith(session: updatedSession));
        },
        onError: (error) {
          debugPrint('[IMGGEN] onError: $error');
          GlazeToast.showWithoutContext('Image gen: $error', isError: true, duration: 4000);
        },
      );
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        _onStateUpdate(currentState.copyWith(session: session, isGeneratingImage: false));
        return;
      }
      _onStateUpdate(currentState.copyWith(session: session, isGeneratingImage: false));
      rethrow;
    } catch (e) {
      _onStateUpdate(currentState.copyWith(session: session, isGeneratingImage: false));
      rethrow;
    }

    if (_cancelToken?.isCancelled == true) {
      var cancelContent = updatedContent;
      int idx = 0;
      while (service.hasImageGenTags(cancelContent)) {
        cancelContent = service.replaceTagWithError(cancelContent, idx, 'Cancelled by user');
        idx++;
      }
      final newMessages = List<ChatMessage>.from(session.messages);
      final cancelSwipeIdx = lastMsg.swipeId;
      final cancelSwipes = lastMsg.swipes.isNotEmpty && cancelSwipeIdx >= 0 && cancelSwipeIdx < lastMsg.swipes.length
          ? (List<String>.from(lastMsg.swipes)..[cancelSwipeIdx] = cancelContent)
          : lastMsg.swipes;
      newMessages[lastIdx] = lastMsg.copyWith(content: cancelContent, swipes: cancelSwipes);
      final finalSession = session.copyWith(messages: newMessages, updatedAt: currentTimestampSeconds());
      _onStateUpdate(currentState.copyWith(session: finalSession, isGeneratingImage: false));
      return;
    }

    final newMessages = List<ChatMessage>.from(session.messages);
    final finalSwipeIdx = lastMsg.swipeId;
    final finalSwipes = lastMsg.swipes.isNotEmpty && finalSwipeIdx >= 0 && finalSwipeIdx < lastMsg.swipes.length
        ? (List<String>.from(lastMsg.swipes)..[finalSwipeIdx] = updatedContent)
        : lastMsg.swipes;
    newMessages[lastIdx] = lastMsg.copyWith(content: updatedContent, swipes: finalSwipes);
    final finalSession = session.copyWith(
      messages: newMessages,
      updatedAt: currentTimestampSeconds(),
    );
    await _ref.read(chatRepoProvider).put(finalSession);
    _onStateUpdate(currentState.copyWith(session: finalSession, isGeneratingImage: false));
  }

  List<String> _collectRecentImageContexts(List<ChatMessage> messages) {
    final contexts = <String>[];
    for (int i = messages.length - 1; i >= 0 && contexts.length < 3; i--) {
      final paths = ImageGenService.extractImageResultPaths(messages[i].content);
      contexts.addAll(paths);
    }
    return contexts.reversed.toList();
  }
}
