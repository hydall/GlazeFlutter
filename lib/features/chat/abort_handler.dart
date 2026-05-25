import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/chat_message.dart';
import '../../core/services/generation_notification_service.dart';
import '../../core/utils/id_generator.dart';
import '../../core/utils/time_helpers.dart';
import 'chat_provider.dart' show streamingStateProvider;
import 'chat_session_service.dart';
import 'chat_state.dart';

class AbortHandler {
  final Ref _ref;
  final String _charId;
  final void Function(AsyncValue<ChatState>) _setState;
  final AsyncValue<ChatState> Function() _getState;
  final void Function(ChatSession) _persistSession;

  CancelToken? _cancelToken;
  CancelToken? _imgGenCancelToken;
  ChatMessage? _restorationMessage;
  int _activeGenId = 0;

  AbortHandler({
    required Ref ref,
    required String charId,
    required void Function(AsyncValue<ChatState>) setState,
    required AsyncValue<ChatState> Function() getState,
    required void Function(ChatSession) persistSession,
  }) : _ref = ref, _charId = charId, _setState = setState,
       _getState = getState, _persistSession = persistSession;

  int nextGenId() => ++_activeGenId;
  bool isCurrentGen(int genId) => _activeGenId == genId;

  ChatMessage? get restorationMessage => _restorationMessage;
  set restorationMessage(ChatMessage? msg) => _restorationMessage = msg;

  CancelToken? get imgGenCancelToken => _imgGenCancelToken;
  set imgGenCancelToken(CancelToken? t) => _imgGenCancelToken = t;

  bool get isGeneratingImage =>
      _imgGenCancelToken != null && !(_imgGenCancelToken!.isCancelled);

  void setCancelToken(CancelToken token, {required int genId}) {
    if (_activeGenId != genId) {
      token.cancel();
      return;
    }
    _cancelToken = token;
  }

  void abortImageGeneration() {
    _imgGenCancelToken?.cancel();
    _imgGenCancelToken = null;
    final current = _getState().value;
    if (current != null && current.isGeneratingImage) {
      _setState(AsyncData(current.copyWith(isGeneratingImage: false)));
    }
  }

  void cancelImageGeneration() {
    _imgGenCancelToken?.cancel();
    _imgGenCancelToken = null;
    final current = _getState().value;
    if (current != null && current.isGeneratingImage) {
      _setState(AsyncData(current.copyWith(isGeneratingImage: false)));
    }
  }

  void clearStreaming() {
    _ref.read(streamingStateProvider(_charId).notifier).state =
        const StreamingState();
  }

  void abortGeneration() {
    _activeGenId++;
    final StreamingState partialStreaming = _ref.read(streamingStateProvider(_charId));
    _cancelToken?.cancel();
    _cancelToken = null;
    _imgGenCancelToken?.cancel();
    _imgGenCancelToken = null;
    clearStreaming();

    final current = _getState().value;
    if (current != null && current.isGenerating) {
      final restoration = _restorationMessage;
      final regenId = current.regenTargetId;

      if (regenId != null && restoration != null) {
        final idx = current.messages.indexWhere((m) => m.id == regenId);
        if (idx >= 0) {
          final String partialText = partialStreaming.text;
          final keptSwipes = List<String>.from(restoration.swipes.isNotEmpty ? restoration.swipes : [restoration.content]);
          final keptSwipesMeta = List<Map<String, dynamic>>.from(restoration.swipesMeta.isNotEmpty ? restoration.swipesMeta : [<String, dynamic>{'genTime': restoration.genTime, 'reasoning': restoration.reasoning, 'tokens': restoration.tokens}]);
          if (partialText.isNotEmpty) {
            keptSwipes.add(partialText);
            keptSwipesMeta.add(<String, dynamic>{});
          }
          final newSwipeId = keptSwipes.length - 1;
          final updated = current.messages[idx].copyWith(
            content: partialText.isNotEmpty ? partialText : restoration.content,
            swipeId: partialText.isNotEmpty ? newSwipeId : restoration.swipeId,
            swipes: keptSwipes,
            swipesMeta: keptSwipesMeta,
            reasoning: partialText.isNotEmpty ? partialStreaming.reasoning : restoration.reasoning,
            genTime: partialText.isNotEmpty ? null : restoration.genTime,
            tokens: partialText.isNotEmpty ? null : restoration.tokens,
            isTyping: false,
            isError: false,
            swipeDirection: partialText.isNotEmpty ? 'right' : restoration.swipeDirection,
          );
          final updatedMessages = [...current.messages];
          updatedMessages[idx] = updated;
          final updatedSession = current.session?.copyWith(
            messages: updatedMessages,
            updatedAt: currentTimestampSeconds(),
          );
          if (updatedSession != null) {
            _persistSession(updatedSession);
            ChatSessionService.updateCache(updatedSession);
          }
          _setState(AsyncData(ChatState(
            session: updatedSession ?? current.session,
            isGenerating: false,
            isGeneratingImage: false,
            regenTargetId: null,
          )));
        } else {
          _setState(AsyncData(ChatState(
            session: current.session,
            isGenerating: false,
            isGeneratingImage: false,
            regenTargetId: null,
          )));
        }
      } else if (restoration != null) {
        final restoredMessages = <ChatMessage>[...(current.session?.messages ?? const <ChatMessage>[]), restoration];
        final restoredSession = current.session?.copyWith(
          messages: restoredMessages,
          updatedAt: currentTimestampSeconds(),
        );
        if (restoredSession != null) {
          _persistSession(restoredSession);
          ChatSessionService.updateCache(restoredSession);
        }
        _setState(AsyncData(current.copyWith(
          session: restoredSession ?? current.session,
          isGenerating: false,
          isGeneratingImage: false,
        )));
      } else {
        final String partialText = partialStreaming.text;
        final String? partialReasoning = partialStreaming.reasoning;
        final bool hasPartial = partialText.isNotEmpty || (partialReasoning != null && partialReasoning.isNotEmpty);

        final currentMessages = current.session?.messages ?? const <ChatMessage>[];
        final lastMsg = currentMessages.isNotEmpty ? currentMessages.last : null;
        final bool lastIsEmptyAssistant = lastMsg != null &&
            lastMsg.role == 'assistant' &&
            lastMsg.content.isEmpty &&
            (lastMsg.reasoning == null || lastMsg.reasoning!.isEmpty);

        if (hasPartial) {
          final partialMsg = ChatMessage(
            id: generateId(),
            role: 'assistant',
            content: partialText,
            reasoning: partialReasoning,
            isTyping: false,
            timestamp: DateTime.now().millisecondsSinceEpoch,
            swipes: [partialText],
            swipeId: 0,
            swipesMeta: [<String, dynamic>{}],
          );
          final baseMessages = lastIsEmptyAssistant
              ? currentMessages.sublist(0, currentMessages.length - 1)
              : currentMessages;
          final updatedMessages = [...baseMessages, partialMsg];
          final updatedSession = current.session?.copyWith(
            messages: updatedMessages,
            updatedAt: currentTimestampSeconds(),
          );
          if (updatedSession != null) {
            _persistSession(updatedSession);
            ChatSessionService.updateCache(updatedSession);
          }
          _setState(AsyncData(current.copyWith(
            session: updatedSession ?? current.session,
            isGenerating: false,
            isGeneratingImage: false,
          )));
        } else if (lastIsEmptyAssistant) {
          final trimmedMessages = currentMessages.sublist(0, currentMessages.length - 1);
          final trimmedSession = current.session?.copyWith(
            messages: trimmedMessages,
            updatedAt: currentTimestampSeconds(),
          );
          if (trimmedSession != null) {
            _persistSession(trimmedSession);
            ChatSessionService.updateCache(trimmedSession);
          }
          _setState(AsyncData(current.copyWith(
            session: trimmedSession ?? current.session,
            isGenerating: false,
            isGeneratingImage: false,
          )));
        } else {
          _setState(AsyncData(current.copyWith(isGenerating: false, isGeneratingImage: false)));
        }
      }
    } else if (current != null && current.isGeneratingImage) {
      _setState(AsyncData(current.copyWith(isGeneratingImage: false)));
    }
    _restorationMessage = null;

    GenerationNotificationService.instance.onGenerationAborted();
  }
}