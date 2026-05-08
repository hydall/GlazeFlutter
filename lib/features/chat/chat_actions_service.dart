import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/chat_message.dart';
import '../../core/services/chat_import_export.dart';
import '../../core/llm/summary_service.dart';
import '../../core/state/db_provider.dart';
import '../../core/utils/time_helpers.dart';
import '../chat_history/chat_history_provider.dart';
import 'chat_provider.dart';

class ChatActionsService {
  final WidgetRef _ref;

  ChatActionsService(this._ref);

  Future<String> generateSummary(String charId) async {
    final chatState = _ref.read(chatProvider(charId)).value;
    if (chatState == null || chatState.session == null) {
      throw StateError('No active chat session');
    }

    final apiConfigs = await _ref.read(apiConfigRepoProvider).getAll();
    if (apiConfigs.isEmpty) {
      throw StateError('No API config found');
    }

    final summaryService = _ref.read(summaryServiceProvider);
    return summaryService.generateSummary(
      sessionId: chatState.session!.id,
      history: chatState.session!.messages,
      apiConfig: apiConfigs.first,
    );
  }

  Future<String> exportChat(String charId) async {
    final chatState = _ref.read(chatProvider(charId)).value;
    if (chatState == null || chatState.session == null) {
      throw StateError('No active chat session');
    }

    final charRepo = _ref.read(characterRepoProvider);
    final character = await charRepo.getById(charId);
    if (character == null) {
      throw StateError('Character not found');
    }

    final desktop = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        '.';
    final outputDir = '${desktop}\\Desktop';

    final result = await exportChatAsJsonl(
      session: chatState.session!,
      character: character,
      outputDir: outputDir,
    );
    return result.filePath;
  }

  Future<int> importChat(String charId, String filePath) async {
    final importResult = await importChatFromJsonl(filePath);
    if (importResult.messages.isEmpty) {
      return 0;
    }

    final repo = _ref.read(chatRepoProvider);
    final existingSessions = await repo.getByCharacterId(charId);

    int maxIdx = 0;
    for (final s in existingSessions) {
      if (s.sessionIndex > maxIdx) maxIdx = s.sessionIndex;
    }

    final newIdx = maxIdx + 1;
    final newSession = ChatSession(
      id: '${charId}_$newIdx',
      characterId: charId,
      sessionIndex: newIdx,
      messages: importResult.messages,
      updatedAt: currentTimestampSeconds(),
    );

    await repo.put(newSession);

    final charRepo = _ref.read(characterRepoProvider);
    final character = await charRepo.getById(charId);
    if (character != null) {
      await charRepo.put(character.copyWith(currentSessionIndex: newIdx));
    }

    _ref.invalidate(chatProvider(charId));
    _ref.invalidate(chatHistoryProvider);

    return importResult.messages.length;
  }
}
