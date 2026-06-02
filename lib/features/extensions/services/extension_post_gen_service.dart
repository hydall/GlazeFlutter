import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/chat_message.dart';
import '../../../core/models/character.dart';
import '../providers/extension_presets_provider.dart';
import '../providers/extensions_settings_provider.dart';
import '../providers/info_blocks_provider.dart';
import 'image_block_service.dart';
import 'info_block_service.dart';

final extensionPostGenServiceProvider = Provider<ExtensionPostGenService>(
  (ref) => ExtensionPostGenService(ref),
);

/// Service that orchestrates extension generation after chat response
class ExtensionPostGenService {
  ExtensionPostGenService(this._ref);

  final Ref _ref;

  /// Called after assistant message is generated
  /// Generates infoblocks and optionally images based on them
  Future<void> processAfterGeneration({
    required String charId,
    required ChatSession session,
    required Character character,
  }) async {
    // Get active preset - extensions are active when a preset is selected
    final settings = _ref.read(extensionsSettingsProvider);
    if (!settings.enabled) return;
    final presetId = settings.activePresetId;
    if (presetId == null || presetId.isEmpty) return;

    // Get the preset configuration
    final presets = _ref.read(extensionPresetsProvider);
    final preset = presets.where((p) => p.id == presetId).firstOrNull;
    if (preset == null) return;

    // Get sessionId
    final sessionId = session.id;
    if (sessionId.isEmpty) return;

    // Get the last message (should be assistant message)
    final messages = session.messages;
    if (messages.isEmpty) return;
    
    final lastMessage = messages.last;
    if (lastMessage.role == 'user') return; // Should be assistant message, not user

    // Step 1: Generate infoblocks
    final infoBlockService = _ref.read(infoBlockServiceProvider);
    final generatedBlocks = await infoBlockService.generateBlocks(
      sessionId: sessionId,
      messageId: lastMessage.id,
      messages: messages,
      preset: preset,
      character: character,
      persona: null, // TODO: get persona from session
    );

    // Update provider state
    if (generatedBlocks.isNotEmpty) {
      final infoBlocksNotifier = _ref.read(infoBlocksProvider(sessionId).notifier);
      for (final block in generatedBlocks) {
        await infoBlocksNotifier.add(block);
      }

      // Step 2: Generate images based on infoblocks (if enabled)
      final imageBlockService = _ref.read(imageBlockServiceProvider);
      await imageBlockService.generateImages(
        sessionId: sessionId,
        infoblocks: generatedBlocks,
        messages: messages,
        character: character,
        persona: null,
      );
    }
  }
}
