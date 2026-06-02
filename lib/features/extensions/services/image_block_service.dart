import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/api_config.dart';
import '../../../core/models/chat_message.dart';
import '../../../core/models/character.dart';
import '../../../core/state/active_selection_provider.dart';
import '../../../core/state/db_provider.dart';
import '../../image_gen/image_gen_provider.dart';
import '../../image_gen/services/image_gen_service.dart';
import '../../settings/api_list_provider.dart';
import '../models/info_block.dart';

final imageBlockServiceProvider = Provider<ImageBlockService>(
  (ref) => ImageBlockService(ref),
);

class ImageBlockService {
  ImageBlockService(this._ref);

  final Ref _ref;

  /// Generates images based on infoblocks after they are created
  Future<void> generateImages({
    required String sessionId,
    required List<InfoBlock> infoblocks,
    required List<ChatMessage> messages,
    required Character character,
    required String? persona,
  }) async {
    // Check if image generation is enabled
    final imgGenSettingsAsync = _ref.read(imageGenSettingsProvider);
    if (imgGenSettingsAsync.isLoading) {
      final imgGenSettings = await _ref.read(imageGenSettingsProvider.future);
      if (!imgGenSettings.enabled) return;
    } else {
      final imgGenSettings = imgGenSettingsAsync.value;
      if (imgGenSettings == null || !imgGenSettings.enabled) return;
    }
    final imgGenSettings = await _ref.read(imageGenSettingsProvider.future);

    if (infoblocks.isEmpty || messages.isEmpty) return;

    final lastMessage = messages.last;
    if (lastMessage.role == 'user') return; // Should be assistant message

    // Build image prompt from last assistant message + recent infoblocks
    final imagePrompt = _buildImagePrompt(
      lastMessage: lastMessage,
      infoblocks: infoblocks.take(3).toList(),
      character: character,
      persona: persona,
    );

    // Get API config for LLM endpoint
    final apiConfigSync = _ref.read(activeApiConfigProvider);
    final ApiConfig apiConfig;
    if (apiConfigSync != null) {
      apiConfig = apiConfigSync;
    } else {
      final apiList = await _ref.read(apiListProvider.future);
      if (apiList.isEmpty) {
        debugPrint('[ImageBlockService] No API configs available');
        return;
      }
      final activeId = _ref.read(activeApiPresetIdProvider);
      apiConfig = activeId != null
          ? apiList.firstWhere((c) => c.id == activeId, orElse: () => apiList.first)
          : apiList.first;
    }

    // Get persona object
    final personaRepo = _ref.read(personaRepoProvider);
    final personas = await personaRepo.getAll();
    final connections = _ref.read(personaConnectionsProvider);
    final activePersonaId = _ref.read(activePersonaIdProvider);
    final personaObj = getEffectivePersona(
      personas, character.id, sessionId, activePersonaId, connections,
    );

    // Call image generation service
    try {
      final imageStorage = await _ref.read(imageStorageProvider.future);
      final imageGenService = ImageGenService(imageStorage);
      
      await imageGenService.generateImage(
        settings: imgGenSettings,
        prompt: imagePrompt,
        llmEndpoint: apiConfig.endpoint,
        llmApiKey: apiConfig.apiKey,
        llmModel: apiConfig.model,
        character: character,
        persona: personaObj,
      );
      
      debugPrint('[ImageBlockService] Image generated successfully');
    } catch (e) {
      debugPrint('[ImageBlockService] Error generating image: $e');
    }
  }

  String _buildImagePrompt({
    required ChatMessage lastMessage,
    required List<InfoBlock> infoblocks,
    required Character character,
    required String? persona,
  }) {
    final buffer = StringBuffer();

    buffer.writeln('Generate an image that illustrates the following scene:');
    buffer.writeln();

    // Character info
    buffer.writeln('Character: ${character.name}');
    if (character.description != null && character.description!.isNotEmpty) {
      buffer.writeln('Appearance: ${character.description}');
    }
    buffer.writeln();

    // Last message context
    buffer.writeln('Scene context:');
    buffer.writeln(lastMessage.content);
    buffer.writeln();

    // Infoblocks for additional context
    if (infoblocks.isNotEmpty) {
      buffer.writeln('Additional details:');
      for (final block in infoblocks) {
        buffer.writeln(block.content);
      }
    }

    return buffer.toString();
  }
}
