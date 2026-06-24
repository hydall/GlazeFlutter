import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/state/db_provider.dart';
import '../chat_session_service.dart';
import '../chat_state.dart';

class ChatDraftController {
  final Ref _ref;
  final void Function(AsyncValue<ChatState>) _setState;
  final AsyncValue<ChatState> Function() _getState;

  ChatDraftController({
    required this._ref,
    required this._setState,
    required this._getState,
  });

  Future<void> saveDraft(String draftText) async {
    if (!_ref.mounted) return;
    final current = _getState().value;
    if (current == null || current.session == null) return;
    if (current.session!.draft == draftText) return;

    final updatedSession = current.session!.copyWith(draft: draftText);
    await _ref.read(chatRepoProvider).put(updatedSession);
    if (!_ref.mounted) return;
    ChatSessionService.updateCache(updatedSession);
    _setState(AsyncData(ChatState(
      session: updatedSession,
      isGenerating: current.isGenerating,
      generationStartTime: current.generationStartTime,
      error: current.error,
    )));
  }
}
