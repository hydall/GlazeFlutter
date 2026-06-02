import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../chat_state.dart';

class ChatImageRecoveryController {
  // ignore: unused_field
  final Ref _ref;
  // ignore: unused_field
  final String _charId;
  // ignore: unused_field
  final void Function(AsyncValue<ChatState>) _setState;
  // ignore: unused_field
  final AsyncValue<ChatState> Function() _getState;

  ChatImageRecoveryController({
    required this._ref,
    required this._charId,
    required this._setState,
    required this._getState,
  });

  // Image recovery methods will be implemented here
  // For now, these are placeholders that delegate to the existing ImageRecoveryService
}
