import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:glaze_flutter/core/models/chat_message.dart';
import 'package:glaze_flutter/features/chat/abort_handler.dart';
import 'package:glaze_flutter/features/chat/chat_state.dart';
import 'package:glaze_flutter/features/chat/services/stages/regen_resolver.dart';
import 'package:glaze_flutter/features/chat/services/stages/stage_context.dart';

final _resolverProvider = Provider<RegenResolver>((ref) {
  late AsyncValue<ChatState> state = const AsyncData(ChatState());
  final abortHandler = AbortHandler(
    ref: ref,
    charId: 'c1',
    setState: (next) => state = next,
    getState: () => state,
    persistSession: (_) {},
  );
  return RegenResolver(
    StageContext(
      ref: ref,
      charId: 'c1',
      abortHandler: abortHandler,
      setState: (next) => state = next,
      getState: () => state,
    ),
  );
});

void main() {
  test('matching regenerate error settles the streaming flag', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    const session = ChatSession(
      id: 's1',
      characterId: 'c1',
      sessionIndex: 0,
      sessionVars: {},
      messages: [
        ChatMessage(
          id: 'm1',
          role: 'assistant',
          content: 'Request failed',
          timestamp: 1,
          isError: true,
        ),
      ],
    );

    final outcome = container
        .read(_resolverProvider)
        .resolve(
          result: const ChatState(
            session: session,
            isGenerating: true,
            regenTargetId: 'm1',
          ),
          regenTargetId: 'm1',
          saveSession: null,
          session: session,
        );

    expect(outcome, isNotNull);
    expect(outcome!.state.isGenerating, isFalse);
    expect(outcome.state.regenTargetId, isNull);
  });
}
