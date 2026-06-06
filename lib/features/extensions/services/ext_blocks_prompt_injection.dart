import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/repositories/info_blocks_repository.dart';
import '../../../core/models/chat_message.dart';
import '../../../core/state/db_provider.dart';
import '../models/extension_preset.dart';
import '../models/info_block.dart';
import '../providers/extension_presets_provider.dart';
import '../providers/extensions_settings_provider.dart';
import 'info_block_injector.dart';

final extBlocksPromptInjectionProvider =
    Provider<ExtBlocksPromptInjection>((ref) => ExtBlocksPromptInjection(ref));

/// Injects ext-block outputs into chat history for main prompt assembly.
class ExtBlocksPromptInjection {
  ExtBlocksPromptInjection(this._ref);

  final Ref _ref;

  ExtensionPreset? _resolveActivePreset() {
    final settings = _ref.read(extensionsSettingsProvider);
    if (!settings.enabled) return null;
    final presetId = settings.activePresetId;
    if (presetId == null || presetId.isEmpty) return null;
    return _ref
        .read(extensionPresetsProvider)
        .where((p) => p.id == presetId)
        .firstOrNull;
  }

  Future<List<ChatMessage>> injectIntoHistory({
    required String sessionId,
    required List<ChatMessage> messages,
  }) async {
    final preset = _resolveActivePreset();
    if (preset == null || messages.isEmpty) return messages;

    final repo = InfoBlocksRepository(_ref.read(appDbProvider));
    final injector = InfoBlockInjector(_InfoBlocksRepoReader(repo));
    return injector.injectBlocks(
      messages: messages,
      sessionId: sessionId,
      preset: preset,
    );
  }
}

class _InfoBlocksRepoReader implements InfoBlockReader {
  _InfoBlocksRepoReader(this._repo);

  final InfoBlocksRepository _repo;

  @override
  Future<List<InfoBlock>> getByMessageId(
    String sessionId,
    String messageId,
  ) =>
      _repo.getByMessageId(sessionId, messageId);
}
