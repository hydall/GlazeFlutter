import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:glaze_flutter/core/models/chat_message.dart';
import 'package:glaze_flutter/features/chat/abort_handler.dart';
import 'package:glaze_flutter/features/chat/chat_state.dart';
import 'package:glaze_flutter/features/extensions/services/extension_post_gen_service.dart';

class _RecordingExtensionPostGenService extends ExtensionPostGenService {
  _RecordingExtensionPostGenService(super.ref);

  int cancelBlocksCalls = 0;

  @override
  void cancelBlocks() {
    cancelBlocksCalls++;
  }
}

class _AbortHarness {
  _AbortHarness(Ref ref, ChatState initialState)
    : state = AsyncData(initialState) {
    handler = AbortHandler(
      ref: ref,
      charId: 'char-1',
      setState: (next) {
        state = next;
        final value = next.value;
        if (value != null) stateHistory.add(value);
      },
      getState: () => state,
      persistSession: persistedSessions.add,
    );
  }

  late final AbortHandler handler;
  AsyncValue<ChatState> state;
  final List<ChatState> stateHistory = [];
  final List<ChatSession> persistedSessions = [];
}

Provider<_AbortHarness> _abortHarnessProvider(ChatState initialState) =>
    Provider((ref) => _AbortHarness(ref, initialState));

ChatSession _session(List<ChatMessage> messages) => ChatSession(
  id: 'session-1',
  characterId: 'char-1',
  sessionIndex: 0,
  messages: messages,
);

void _expectAllGenerationFlagsCleared(Iterable<ChatState> states) {
  expect(states, isNotEmpty);
  for (final state in states) {
    expect(state.isGenerating, isFalse);
    expect(state.isGeneratingImage, isFalse);
    expect(state.isPostGenRunning, isFalse);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Stop clears all generation flags through deferred no-partial abort cleanup',
    () async {
      final initialState = ChatState(
        session: _session([
          const ChatMessage(id: 'user-1', role: 'user', content: 'Hello'),
        ]),
        isGeneratingImage: true,
        isPostGenRunning: true,
      );
      final harnessProvider = _abortHarnessProvider(initialState);
      final container = ProviderContainer(
        overrides: [
          extensionPostGenServiceProvider.overrideWith(
            (ref) => _RecordingExtensionPostGenService(ref),
          ),
        ],
      );
      addTearDown(container.dispose);
      final harness = container.read(harnessProvider);

      harness.handler.abortGeneration();

      _expectAllGenerationFlagsCleared([harness.state.requireValue]);
      await Future<void>.delayed(Duration.zero);
      _expectAllGenerationFlagsCleared(harness.stateHistory);
      expect(harness.state.requireValue.session, same(initialState.session));
    },
  );

  test(
    'post-gen Stop restores the snapshot without re-enabling generation flags',
    () async {
      final initialState = ChatState(
        session: _session([
          const ChatMessage(id: 'user-1', role: 'user', content: 'Hello'),
        ]),
        isGeneratingImage: true,
        isPostGenRunning: true,
      );
      final harnessProvider = _abortHarnessProvider(initialState);
      final container = ProviderContainer(
        overrides: [
          extensionPostGenServiceProvider.overrideWith(
            (ref) => _RecordingExtensionPostGenService(ref),
          ),
        ],
      );
      addTearDown(container.dispose);
      final harness = container.read(harnessProvider);
      harness.handler.restorationMessage = const ChatMessage(
        id: 'assistant-1',
        role: 'assistant',
        content: 'Restored response',
      );

      harness.handler.abortGeneration();

      _expectAllGenerationFlagsCleared([harness.state.requireValue]);
      await Future<void>.delayed(Duration.zero);

      _expectAllGenerationFlagsCleared(harness.stateHistory);
      expect(
        harness.state.requireValue.session?.messages.map(
          (message) => message.id,
        ),
        ['user-1', 'assistant-1'],
      );
      expect(harness.persistedSessions, hasLength(1));
    },
  );

  test('main Stop cancels active extension post-generation blocks', () {
    final harnessProvider = _abortHarnessProvider(
      const ChatState(isPostGenRunning: true),
    );
    final container = ProviderContainer(
      overrides: [
        extensionPostGenServiceProvider.overrideWith(
          (ref) => _RecordingExtensionPostGenService(ref),
        ),
      ],
    );
    addTearDown(container.dispose);
    final harness = container.read(harnessProvider);
    final postGenService =
        container.read(extensionPostGenServiceProvider)
            as _RecordingExtensionPostGenService;

    harness.handler.abortGeneration();

    expect(postGenService.cancelBlocksCalls, 1);
  });
}
