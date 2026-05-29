import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../chat_state.dart';

class ChatImageRecoveryController {
  final Ref _ref;
  final String _charId;
  final void Function(AsyncValue<ChatState>) _setState;
  final AsyncValue<ChatState> Function() _getState;

  ChatImageRecoveryController({
    required Ref ref,
    required String charId,
    required void Function(AsyncValue<ChatState>) setState,
    required AsyncValue<ChatState> Function() getState,
  })  : _ref = ref,
        _charId = charId,
        _setState = setState,
        _getState = getState;

  // Image recovery methods will be implemented here
  // For now, these are placeholders that delegate to the existing ImageRecoveryService
}
