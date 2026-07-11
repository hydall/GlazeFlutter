import 'package:drift/native.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:glaze_flutter/core/db/app_db.dart';
import 'package:glaze_flutter/core/llm/aux_llm_client.dart' show AuxApiConfig;
import 'package:glaze_flutter/core/models/character.dart';
import 'package:glaze_flutter/core/models/chat_message.dart';
import 'package:glaze_flutter/core/state/db_provider.dart';
import 'package:glaze_flutter/features/chat/abort_handler.dart';
import 'package:glaze_flutter/features/chat/chat_state.dart';
import 'package:glaze_flutter/features/chat/services/stages/cleaner_stage.dart';
import 'package:glaze_flutter/features/chat/services/stages/ext_blocks_stage.dart';
import 'package:glaze_flutter/features/chat/services/stages/ledger_stage.dart';
import 'package:glaze_flutter/features/chat/services/stages/stage_context.dart';

class _RecordingExtBlocksStage extends ExtBlocksStage {
  _RecordingExtBlocksStage(super.ctx);

  int calls = 0;
  int? agentSwipeId;

  @override
  Future<void> launchForSwipe({
    required ChatSession session,
    required Character character,
    required int agentSwipeId,
  }) async {
    calls++;
    this.agentSwipeId = agentSwipeId;
  }
}

class _RecordingLedgerStage extends LedgerStage {
  _RecordingLedgerStage(super.ctx);

  int calls = 0;
  String? finalAssistantText;

  @override
  Future<void> run({
    required String sessionId,
    required List<ChatMessage> messages,
    required int genId,
    required String finalAssistantText,
    required ChatMessage targetMessage,
    bool isManualRerun = false,
    AuxApiConfig? resolvedConfig,
    CancelToken? cancelToken,
  }) async {
    calls++;
    this.finalAssistantText = finalAssistantText;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'disabled cleaner still runs ExtBlocks and Ledger without a MemoryBook',
    () async {
      SharedPreferences.setMockInitialValues({});
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final container = ProviderContainer(
        overrides: [appDbProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);
      addTearDown(db.close);

      await container
          .read(pipelineSettingsProvider.notifier)
          .save(
            container
                .read(pipelineSettingsProvider)
                .copyWith(
                  cleaner: container
                      .read(pipelineSettingsProvider)
                      .cleaner
                      .copyWith(postCleanerEnabled: false),
                ),
          );

      const assistant = ChatMessage(
        id: 'm1',
        role: 'assistant',
        content: 'Raw direct response',
        timestamp: 1,
      );
      const session = ChatSession(
        id: 's1',
        characterId: 'c1',
        sessionIndex: 0,
        sessionVars: {},
        messages: [assistant],
      );
      await container.read(chatRepoProvider).put(session);

      late AsyncValue<ChatState> state = const AsyncData(
        ChatState(session: session),
      );
      late _RecordingExtBlocksStage extBlocks;
      late _RecordingLedgerStage ledger;
      late AbortHandler abortHandler;
      final stageProvider = Provider<CleanerStage>((ref) {
        abortHandler = AbortHandler(
          ref: ref,
          charId: 'c1',
          setState: (next) => state = next,
          getState: () => state,
          persistSession: (_) {},
        );
        final ctx = StageContext(
          ref: ref,
          charId: 'c1',
          abortHandler: abortHandler,
          setState: (next) => state = next,
          getState: () => state,
        );
        extBlocks = _RecordingExtBlocksStage(ctx);
        ledger = _RecordingLedgerStage(ctx);
        return CleanerStage(ctx, extBlocks: extBlocks, ledger: ledger);
      });
      final stage = container.read(stageProvider);
      final genId = abortHandler.nextGenId();

      await stage.run(
        sessionId: session.id,
        messages: session.messages,
        genId: genId,
        character: Character(id: 'c1', name: 'Alice'),
      );

      expect(extBlocks.calls, 1);
      expect(extBlocks.agentSwipeId, -1);
      expect(ledger.calls, 1);
      expect(ledger.finalAssistantText, assistant.content);
    },
  );
}
