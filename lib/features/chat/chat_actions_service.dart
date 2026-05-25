import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../settings/api_list_provider.dart';

import '../../core/models/chat_message.dart';
import '../../core/services/chat_import_export.dart';
import '../../core/llm/summary_service.dart';
import '../../core/state/db_provider.dart';
import '../../core/utils/time_helpers.dart';
import '../../shared/widgets/glaze_toast.dart';
import '../chat_history/chat_history_provider.dart';
import 'chat_provider.dart';

final chatActionsServiceProvider = Provider<ChatActionsService>((ref) {
  return ChatActionsService(ref);
});

class ChatActionsService {
  final Ref _ref;

  ChatActionsService(this._ref);

  Future<String> generateSummary(String charId) async {
    final chatState = _ref.read(chatProvider(charId)).value;
    if (chatState == null || chatState.session == null) {
      throw StateError('No active chat session');
    }

    await _ref.read(apiListProvider.future);
    final apiConfig = _ref.read(activeApiConfigProvider);
    if (apiConfig == null) {
      throw StateError('No API config found');
    }

    final summaryService = _ref.read(summaryServiceProvider);
    return summaryService.generateSummary(
      sessionId: chatState.session!.id,
      history: chatState.session!.messages,
      apiConfig: apiConfig,
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

    final outputDir = await getTemporaryDirectory();

    final result = await exportChatAsJsonl(
      session: chatState.session!,
      character: character,
      outputDir: outputDir.path,
    );

    await Share.shareXFiles([XFile(result.filePath)],
        text: 'Chat with ${character.name}');
    return result.filePath;
  }

  Future<void> exportSessionUI(
    BuildContext context, {
    required String charId,
    required String sessionId,
  }) async {
    final notifier = _ref.read(chatProvider(charId).notifier);
    final currentSessionId = _ref.read(chatProvider(charId)).value?.session?.id;
    final needsSwitch = currentSessionId != sessionId;

    if (needsSwitch) {
      final sessions = await notifier.getSessions();
      final target = sessions.where((s) => s.id == sessionId).firstOrNull;
      if (target != null) {
        await notifier.switchSession(target.sessionIndex);
      }
    }

    try {
      final filePath = await exportChat(charId);
      if (context.mounted) {
        GlazeToast.show(context, 'Chat exported to $filePath');
      }
    } on StateError catch (e) {
      if (context.mounted) GlazeToast.show(context, e.message);
    } catch (e) {
      if (context.mounted) GlazeToast.error(context, 'Export failed: ', e);
    }
  }

  Future<int> importChat(String charId, String filePath) async {
    final importResult = await importChatFromJsonl(filePath);
    return importChatFromResult(charId, importResult);
  }

  Future<int> importChatFromResult(
      String charId, ChatImportResult importResult) async {
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
