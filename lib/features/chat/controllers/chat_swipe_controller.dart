import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/state/db_provider.dart';
import '../chat_message_service.dart';
import '../chat_session_service.dart';
import '../chat_state.dart';
import '../initial_message_builder.dart';

class ChatSwipeController {
  final Ref _ref;
  final String _charId;
  final void Function(AsyncValue<ChatState>) _setState;
  final AsyncValue<ChatState> Function() _getState;
  final void Function() _invalidateHistory;

  ChatSwipeController({
    required this._ref,
    required this._charId,
    required this._setState,
    required this._getState,
    required this._invalidateHistory,
  });

  ChatMessageService get _messageSvc => ChatMessageService(_ref);

  void setSwipe(int messageIndex, int swipeId) {
    final current = _getState().value;
    if (current == null || current.session == null) return;
    final updated = _messageSvc.setSwipe(current.session!, messageIndex, swipeId);
    _invalidateHistory();
    _setState(AsyncData(current.copyWith(session: updated)));
  }

  Future<void> changeSwipe(int messageIndex, int dir, {bool fromSwipe = false}) async {
    final current = _getState().value;
    if (current == null || current.session == null || current.isGenerating) return;
    if (messageIndex < 0 || messageIndex >= current.messages.length) return;

    final isLast = messageIndex == current.messages.length - 1;
    final result = _messageSvc.changeSwipe(
      current.session!,
      messageIndex,
      dir,
      fromSwipe: fromSwipe,
      isLastMessage: isLast,
    );

    if (result.needsRegen) {
      // This will be handled by the parent provider calling regenerateLastAssistant
      return;
    }
    if (result.isUpdated) {
      _invalidateHistory();
      _setState(AsyncData(current.copyWith(session: result.session)));
    }
  }

  Future<void> setGreeting(int messageIndex, int direction) async {
    final current = _getState().value;
    if (current == null || current.session == null || current.isGenerating) return;
    if (messageIndex != 0) return;
    if (messageIndex >= current.messages.length) return;
    final msg = current.messages[messageIndex];
    if (msg.role != 'assistant') return;

    final character = await _ref.read(characterRepoProvider).getById(_charId);
    if (character == null) return;
    final persona = await ChatSessionService(_ref).resolvePersona(_charId);
    final greetings = InitialMessageBuilder.resolveGreetings(
      character: character,
      persona: persona,
      sessionId: current.session!.id,
    );
    if (greetings.length <= 1) return;

    final currentIdx = msg.greetingIndex ?? 0;
    final updated = _messageSvc.setGreeting(
      current.session!,
      messageIndex,
      currentIdx + direction,
      greetings,
    );
    _invalidateHistory();
    _setState(AsyncData(current.copyWith(session: updated)));
  }
}
