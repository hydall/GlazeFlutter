import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/db/repositories/info_blocks_repository.dart';
import '../../../core/models/chat_message.dart';
import '../../../core/models/character.dart';
import '../../../core/models/persona.dart';
import '../../../core/state/db_provider.dart';
import '../../../core/utils/id_generator.dart';
import '../../image_gen/image_gen_provider.dart';
import '../models/block_config.dart';
import '../models/block_run_status.dart';
import '../models/extension_preset.dart';
import '../models/info_block.dart';
import '../providers/extension_presets_provider.dart';
import '../providers/extensions_settings_provider.dart';
import '../providers/info_blocks_provider.dart';
import 'info_block_service.dart';

final extensionPostGenServiceProvider = Provider<ExtensionPostGenService>(
  (ref) => ExtensionPostGenService(ref),
);

/// Orchestrates extension block generation after chat response.
/// Blocks are run in `order` sequence; blocks with [BlockConfig.dependsOnPrevious]
/// wait for the previous block to finish (done or error) before starting.
/// Independently-configured blocks start in parallel with the previous one.
class ExtensionPostGenService {
  ExtensionPostGenService(this._ref);

  final Ref _ref;

  /// Active cancel token for the current block run. Cancelling this stops
  /// all in-flight block LLM/image calls without touching the main gen token.
  CancelToken? _blocksCancelToken;

  InfoBlocksRepository get _repo =>
      InfoBlocksRepository(_ref.read(appDbProvider));

  // ─────────────────────────────────────────────────────────────────────────
  // Public API
  // ─────────────────────────────────────────────────────────────────────────

  /// Called by GenerationPipeline after assistant message is finalised.
  Future<void> processAfterGeneration({
    required String charId,
    required ChatSession session,
    required Character character,
    required Persona? persona,
  }) async {
    final settings = _ref.read(extensionsSettingsProvider);
    if (!settings.enabled) return;
    final presetId = settings.activePresetId;
    if (presetId == null || presetId.isEmpty) return;

    final presets = _ref.read(extensionPresetsProvider);
    final preset = presets.where((pr) => pr.id == presetId).firstOrNull;
    if (preset == null) return;

    final sessionId = session.id;
    if (sessionId.isEmpty) return;

    final messages = session.messages;
    if (messages.isEmpty) return;

    final lastMessage = messages.last;
    if (lastMessage.role == 'user') return;

    // Fresh cancel token for this run.
    _blocksCancelToken = CancelToken();

    await _runChain(
      sessionId: sessionId,
      messageId: lastMessage.id,
      messages: messages,
      preset: preset,
      character: character,
      persona: persona,
      cancelToken: _blocksCancelToken!,
    );
  }

  /// Re-runs a single block for an already-existing message.
  Future<void> rerunBlock({
    required String blockId,
    required String messageId,
    required String sessionId,
    required List<ChatMessage> messages,
    required Character character,
    required Persona? persona,
  }) async {
    final settings = _ref.read(extensionsSettingsProvider);
    if (!settings.enabled) return;
    final presetId = settings.activePresetId;
    if (presetId == null || presetId.isEmpty) return;

    final presets = _ref.read(extensionPresetsProvider);
    final preset = presets.where((pr) => pr.id == presetId).firstOrNull;
    if (preset == null) return;

    final blockConfig = preset.blocks.where((b) => b.id == blockId).firstOrNull;
    if (blockConfig == null) return;

    // Delete existing block result for this message+block before re-running.
    final existing = await _repo.getByMessageId(sessionId, messageId);
    for (final b in existing.where((b) => b.blockId == blockId)) {
      await _repo.deleteInfoBlock(b.id);
    }
    _ref.read(infoBlocksProvider(sessionId).notifier).removeByBlockId(
      messageId: messageId,
      blockId: blockId,
    );

    final cancelToken = CancelToken();
    _blocksCancelToken = cancelToken;

    final block = await _runSingleBlock(
      sessionId: sessionId,
      messageId: messageId,
      messages: messages,
      blockConfig: blockConfig,
      preset: preset,
      character: character,
      persona: persona,
      previousOutput: null,
      cancelToken: cancelToken,
    );

    if (block != null) {
      _ref.read(infoBlocksProvider(sessionId).notifier).addOrReplace(block);
    }
  }

  /// Cancels any in-flight block generation for the current session.
  void cancelBlocks() {
    _blocksCancelToken?.cancel();
    _blocksCancelToken = null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Chain execution
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _runChain({
    required String sessionId,
    required String messageId,
    required List<ChatMessage> messages,
    required ExtensionPreset preset,
    required Character character,
    required Persona? persona,
    required CancelToken cancelToken,
  }) async {
    final blocks = preset.blocks
        .where((b) => b.enabled)
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));

    String? previousOutput;
    Future<InfoBlock?>? previousFuture;

    for (final blockConfig in blocks) {
      if (cancelToken.isCancelled) break;

      final Future<InfoBlock?> blockFuture;

      if (blockConfig.dependsOnPrevious && previousFuture != null) {
        // Sequential: wait for previous block's result, pass its output.
        blockFuture = previousFuture.then((prev) async {
          if (cancelToken.isCancelled) return null;
          final output = prev?.content;
          return _runSingleBlock(
            sessionId: sessionId,
            messageId: messageId,
            messages: messages,
            blockConfig: blockConfig,
            preset: preset,
            character: character,
            persona: persona,
            previousOutput: output,
            cancelToken: cancelToken,
          );
        });
      } else {
        // Parallel: start immediately with last known previousOutput.
        final capturedPrev = previousOutput;
        blockFuture = _runSingleBlock(
          sessionId: sessionId,
          messageId: messageId,
          messages: messages,
          blockConfig: blockConfig,
          preset: preset,
          character: character,
          persona: persona,
          previousOutput: capturedPrev,
          cancelToken: cancelToken,
        );
      }

      // If this is a sequential gate we need to await in the loop so the
      // next block can decide whether to wait or not.
      if (blockConfig.dependsOnPrevious) {
        final result = await blockFuture;
        if (result != null) {
          previousOutput = result.content;
          _ref.read(infoBlocksProvider(sessionId).notifier).addOrReplace(result);
        }
        previousFuture = null;
      } else {
        previousFuture = blockFuture;
        // Don't await — let it run in parallel. Chain completion via
        // side-effect in _runSingleBlock (notifier.addOrReplace).
        unawaited(blockFuture.then((result) {
          if (result != null) {
            _ref.read(infoBlocksProvider(sessionId).notifier).addOrReplace(result);
          }
        }));
      }
    }

    // Await last dangling parallel future so the function doesn't return
    // before all blocks have settled.
    if (previousFuture != null) {
      await previousFuture;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Single block dispatch
  // ─────────────────────────────────────────────────────────────────────────

  Future<InfoBlock?> _runSingleBlock({
    required String sessionId,
    required String messageId,
    required List<ChatMessage> messages,
    required BlockConfig blockConfig,
    required ExtensionPreset preset,
    required Character character,
    required Persona? persona,
    required String? previousOutput,
    required CancelToken cancelToken,
  }) async {
    if (cancelToken.isCancelled) return null;

    // Insert a running placeholder so the badge updates immediately.
    final placeholderId = generateId();
    final placeholder = InfoBlock(
      id: placeholderId,
      sessionId: sessionId,
      messageId: messageId,
      blockId: blockConfig.id,
      blockName: blockConfig.name,
      blockType: blockConfig.type.name,
      content: '',
      createdAt: DateTime.now().millisecondsSinceEpoch,
      order: blockConfig.order,
      status: BlockRunStatus.running,
    );
    await _repo.insert(placeholder);
    _ref.read(infoBlocksProvider(sessionId).notifier).addOrReplace(placeholder);

    try {
      InfoBlock? result;

      switch (blockConfig.type) {
        case BlockType.infoblock:
          result = await _runInfoblock(
            sessionId: sessionId,
            messageId: messageId,
            messages: messages,
            blockConfig: blockConfig,
            preset: preset,
            character: character,
            persona: persona,
            previousOutput: previousOutput,
            cancelToken: cancelToken,
            placeholderId: placeholderId,
          );
        case BlockType.imageGen:
          result = await _runImageGen(
            sessionId: sessionId,
            messageId: messageId,
            messages: messages,
            blockConfig: blockConfig,
            character: character,
            persona: persona,
            previousOutput: previousOutput,
            cancelToken: cancelToken,
            placeholderId: placeholderId,
          );
        case BlockType.jsRunner:
          // Placeholder — JS runner not yet implemented.
          debugPrint('[ExtPostGen] jsRunner block "${blockConfig.name}" — not implemented yet');
          await _repo.updateStatus(placeholderId, BlockRunStatus.done);
          return placeholder.copyWith(status: BlockRunStatus.done);
      }

      return result;
    } catch (e) {
      if (!cancelToken.isCancelled) {
        debugPrint('[ExtPostGen] Error in block "${blockConfig.name}": $e');
      }
      await _repo.updateStatus(placeholderId, BlockRunStatus.error);
      final errored = placeholder.copyWith(status: BlockRunStatus.error);
      _ref.read(infoBlocksProvider(sessionId).notifier).addOrReplace(errored);
      return errored;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Infoblock
  // ─────────────────────────────────────────────────────────────────────────

  Future<InfoBlock?> _runInfoblock({
    required String sessionId,
    required String messageId,
    required List<ChatMessage> messages,
    required BlockConfig blockConfig,
    required ExtensionPreset preset,
    required Character character,
    required Persona? persona,
    required String? previousOutput,
    required CancelToken cancelToken,
    required String placeholderId,
  }) async {
    final infoBlockService = _ref.read(infoBlockServiceProvider);
    final content = await infoBlockService.generateSingleBlockContent(
      sessionId: sessionId,
      messageId: messageId,
      messages: messages,
      blockConfig: blockConfig,
      character: character,
      persona: persona?.name,
      previousOutput: previousOutput,
      cancelToken: cancelToken,
    );

    if (cancelToken.isCancelled) {
      await _repo.updateStatus(placeholderId, BlockRunStatus.stopped);
      final stopped = InfoBlock(
        id: placeholderId,
        sessionId: sessionId,
        messageId: messageId,
        blockId: blockConfig.id,
        blockName: blockConfig.name,
        blockType: blockConfig.type.name,
        content: '',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        order: blockConfig.order,
        status: BlockRunStatus.stopped,
      );
      _ref.read(infoBlocksProvider(sessionId).notifier).addOrReplace(stopped);
      return stopped;
    }

    if (content == null || content.isEmpty) {
      await _repo.updateStatus(placeholderId, BlockRunStatus.error);
      final errored = InfoBlock(
        id: placeholderId,
        sessionId: sessionId,
        messageId: messageId,
        blockId: blockConfig.id,
        blockName: blockConfig.name,
        blockType: blockConfig.type.name,
        content: '',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        order: blockConfig.order,
        status: BlockRunStatus.error,
      );
      _ref.read(infoBlocksProvider(sessionId).notifier).addOrReplace(errored);
      return errored;
    }

    // Update placeholder in DB with final content + done status.
    await _repo.updateContent(placeholderId, content);
    await _repo.updateStatus(placeholderId, BlockRunStatus.done);

    final done = InfoBlock(
      id: placeholderId,
      sessionId: sessionId,
      messageId: messageId,
      blockId: blockConfig.id,
      blockName: blockConfig.name,
      blockType: blockConfig.type.name,
      content: content,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      order: blockConfig.order,
      status: BlockRunStatus.done,
    );
    _ref.read(infoBlocksProvider(sessionId).notifier).addOrReplace(done);
    return done;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Image gen
  // ─────────────────────────────────────────────────────────────────────────

  Future<InfoBlock?> _runImageGen({
    required String sessionId,
    required String messageId,
    required List<ChatMessage> messages,
    required BlockConfig blockConfig,
    required Character character,
    required Persona? persona,
    required String? previousOutput,
    required CancelToken cancelToken,
    required String placeholderId,
  }) async {
    final imgGenSettingsAsync = _ref.read(imageGenSettingsProvider);
    final imgGenSettings = imgGenSettingsAsync.value;
    if (imgGenSettings == null || !imgGenSettings.enabled) {
      await _repo.updateStatus(placeholderId, BlockRunStatus.done);
      return null;
    }

    // Build image prompt: use previousOutput (infoblock) if available,
    // otherwise fall back to last assistant message content.
    final lastAssistant = messages.lastWhere(
      (m) => m.role == 'assistant',
      orElse: () => messages.last,
    );
    final promptSource = previousOutput?.isNotEmpty == true
        ? previousOutput!
        : lastAssistant.content;

    // Extract [img gen:...] tag from the source text.
    final imageService = await _ref.read(imageGenSettingsProvider.notifier).getServiceAsync();
    if (!imageService.hasImageGenTags(promptSource)) {
      // No tag — nothing to generate.
      await _repo.updateStatus(placeholderId, BlockRunStatus.done);
      return null;
    }

    final instructions = imageService.extractImageGenInstructions(promptSource);
    if (instructions.isEmpty) {
      await _repo.updateStatus(placeholderId, BlockRunStatus.done);
      return null;
    }

    final instruction = instructions.first;
    final rawPrompt = instruction['prompt'] as String? ?? '';
    if (rawPrompt.isEmpty) {
      await _repo.updateStatus(placeholderId, BlockRunStatus.done);
      return null;
    }

    try {
      final imageBytes = await imageService.generateImage(
        settings: imgGenSettings,
        prompt: rawPrompt,
        llmEndpoint: '',
        llmApiKey: '',
        llmModel: '',
        character: character,
        persona: persona,
        cancelToken: cancelToken,
      );

      if (cancelToken.isCancelled) {
        await _repo.updateStatus(placeholderId, BlockRunStatus.stopped);
        return null;
      }

      // Save to disk using the same path convention as inline image gen.
      final storage = await _ref.read(imageStorageProvider.future);
      final dir = Directory(p.join(storage.baseDir, 'generated'));
      if (!await dir.exists()) await dir.create(recursive: true);
      final filename = 'extblock_${DateTime.now().millisecondsSinceEpoch}.png';
      final filePath = p.join(dir.path, filename);
      await File(filePath).writeAsBytes(imageBytes);

      final content = '[IMG:RESULT:$filePath]';
      await _repo.updateContent(placeholderId, content);
      await _repo.updateStatus(placeholderId, BlockRunStatus.done);

      final done = InfoBlock(
        id: placeholderId,
        sessionId: sessionId,
        messageId: messageId,
        blockId: blockConfig.id,
        blockName: blockConfig.name,
        blockType: blockConfig.type.name,
        content: content,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        order: blockConfig.order,
        status: BlockRunStatus.done,
      );
      _ref.read(infoBlocksProvider(sessionId).notifier).addOrReplace(done);
      return done;
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        await _repo.updateStatus(placeholderId, BlockRunStatus.stopped);
        return null;
      }
      rethrow;
    }
  }
}
