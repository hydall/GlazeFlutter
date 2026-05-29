import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/chat_message.dart';
import '../../../core/state/db_provider.dart';
import '../chat_session_service.dart';
import '../chat_state.dart';

class ChatSessionController {
  final Ref _ref;
  final String _charId;
  final void Function(AsyncValue<ChatState>) _setState;
  final AsyncValue<ChatState> Function() _getState;
  final void Function() _invalidateHistory;
  final ChatSession Function(ChatSession) _fixupSwipesWithImageResults;

  ChatSessionController({
    required Ref ref,
    required String charId,
    required void Function(AsyncValue<ChatState>) setState,
    required AsyncValue<ChatState> Function() getState,
    required void Function() invalidateHistory,
    required ChatSession Function(ChatSession) fixupSwipesWithImageResults,
  })  : _ref = ref,
        _charId = charId,
        _setState = setState,
        _getState = getState,
        _invalidateHistory = invalidateHistory,
        _fixupSwipesWithImageResults = fixupSwipesWithImageResults;

  ChatSessionService get _sessionSvc => ChatSessionService(_ref);

  Future<void> switchSession(int sessionIndex) async {
    try {
      final raw = await _sessionSvc.switchToSession(_charId, sessionIndex);
      final session = _fixupSwipesWithImageResults(raw);
      if (!identical(session, raw)) {
        await _ref.read(chatRepoProvider).put(session);
        ChatSessionService.updateCache(session);
      }
      final start = session.messages.length > ChatState.initialPageSize
          ? session.messages.length - ChatState.initialPageSize
          : 0;
      _setState(AsyncData(ChatState(session: session, visibleStartIndex: start)));
    } catch (_) {
      final current = _getState().value;
      if (current != null) {
        _setState(AsyncData(current));
      }
    }
  }

  Future<void> createNewSession() async {
    final session = await _sessionSvc.createNewSession(_charId);
    _invalidateHistory();
    _setState(AsyncData(ChatState(session: session)));
  }

  Future<List<ChatSession>> getSessions() => _sessionSvc.getSessions(_charId);

  Future<void> branchSession(int index) async {
    final current = _getState().value;
    if (current == null || current.session == null) return;
    if (index < 0 || index >= current.messages.length) return;
    final session = await _sessionSvc.branchSession(_charId, current.session!, index);
    _invalidateHistory();
    final start = session.messages.length > ChatState.initialPageSize
        ? session.messages.length - ChatState.initialPageSize
        : 0;
    _setState(AsyncData(ChatState(session: session, visibleStartIndex: start)));
  }
}
