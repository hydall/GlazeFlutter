import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/chat_message.dart';
import '../../../core/state/db_provider.dart';
import '../chat_state.dart';

class ChatDraftController {
  final Ref _ref;
  final void Function(AsyncValue<ChatState>) _setState;
  final AsyncValue<ChatState> Function() _getState;

  ChatDraftController({
    required Ref ref,
    required void Function(AsyncValue<ChatState>) setState,
    required AsyncValue<ChatState> Function() getState,
  })  : _ref = ref,
        _setState = setState,
        _getState = getState;

  Future<void> saveDraft(String draftText) async {
    final current = _getState().value;
    if (current == null || current.session == null) return;
    if (current.session!.draft == draftText) return;

    final updatedSession = current.session!.copyWith(draft: draftText);
    await _ref.read(chatRepoProvider).put(updatedSession);
    _setState(AsyncData(ChatState(
      session: updatedSession,
      isGenerating: current.isGenerating,
      generationStartTime: current.generationStartTime,
      error: current.error,
    )));
  }
}
