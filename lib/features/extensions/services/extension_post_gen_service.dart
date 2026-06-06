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
import '../../../core/constants/image_gen_patterns.dart';
import '../../../core/utils/id_generator.dart';
import '../../chat/bridge/chat_bridge_registry.dart';
import '../../image_gen/image_gen_provider.dart';
import '../models/block_config.dart';
import '../../image_gen/services/image_gen_service.dart';
import '../models/block_run_status.dart';
import '../models/extension_preset.dart';
import '../models/info_block.dart';
import '../providers/extension_presets_provider.dart';
import '../providers/extensions_settings_provider.dart';
import '../providers/info_blocks_provider.dart';
import 'block_context_builder.dart';
import 'ext_blocks_panel_builder.dart';
import 'info_block_service.dart';
import 'js_script_extractor.dart';

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

  /// Serializes WebView panel JS calls so stream patches render in order.
  Future<void>? _panelJsChain;

  InfoBlocksRepository get _repo =>
      InfoBlocksRepository(_ref.read(appDbProvider));

  void _enqueuePanelJs(Future<void> Function() work) {
    _panelJsChain = (_panelJsChain ?? Future.value()).then((_) async {
      try {
        await work();
      } catch (e, st) {
        debugPrint('[ExtPostGen] panel JS update failed: $e\n$st');
      }
    });
  }

  void _refreshPanelForMessage(
    String charId,
    String sessionId,
    String messageId,
  ) {
    _enqueuePanelJs(() async {
      final bridge = _ref.read(chatBridgeRegistryProvider(charId));
      if (bridge == null) return;
      final blocks = ExtBlocksPanelBuilder.build(
        _ref,
        sessionId: sessionId,
        messageId: messageId,
      );
      if (blocks.isEmpty) {
        await bridge.hideExtBlocksPanel(messageId);
        return;
      }
      await bridge.showExtBlocksPanel(
        messageId,
        blocks,
        canRunAll: ExtBlocksPanelBuilder.canRunAll(blocks),
      );
    });
  }

  Future<void> _patchOrRefreshPanel({
    required String charId,
    required String sessionId,
    required String messageId,
    required String blockId,
    required String content,
    required String status,
  }) async {
    final bridge = _ref.read(chatBridgeRegistryProvider(charId));
    if (bridge == null) return;
    final patched = await bridge.patchExtBlockContent(
      messageId: messageId,
      blockId: blockId,
      content: content,
      status: status,
    );
    if (patched) return;
    _refreshPanelForMessage(charId, sessionId, messageId);
  }

  String _formatBlockErrorContent(String message) {
    final escaped = message
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
    return '<p class="ext-block-error"><strong>Ошибка:</strong> $escaped</p>';
  }

  Future<InfoBlock> _markBlockError({
    required String charId,
    required String sessionId,
    required String messageId,
    required String placeholderId,
    required InfoBlock placeholder,
    required String errorMessage,
  }) async {
    final content = _formatBlockErrorContent(errorMessage);
    await _repo.updateContent(placeholderId, content);
    await _repo.updateStatus(placeholderId, BlockRunStatus.error);
    final errored = placeholder.copyWith(content: content, status: BlockRunStatus.error);
    _ref.read(infoBlocksProvider(sessionId).notifier).addOrReplace(errored);
    _refreshPanelForMessage(charId, sessionId, messageId);
    return errored;
  }

  /// Removes duplicate DB rows for the same preset block on one message.
  Future<String?> _dedupeBlocksForConfig({
    required String sessionId,
    required String messageId,
    required String blockId,
  }) async {
    final existing = await _repo.getByMessageId(sessionId, messageId);
    final matching =
        existing.where((b) => b.blockId == blockId).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (matching.isEmpty) return null;
    final keep = matching.first;
    for (final dup in matching.skip(1)) {
      await _repo.deleteInfoBlock(dup.id);
      await _ref.read(infoBlocksProvider(sessionId).notifier).delete(dup.id);
    }
    return keep.id;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Public API
  // ─────────────────────────────────────────────────────────────────────────

  /// Runs all enabled preset blocks for [messageId]. Used after chat
  /// generation and from the manual "Запустить блоки" control.
  Future<void> runBlocksForMessage({
    required String charId,
    required String sessionId,
    required String messageId,
    required List<ChatMessage> messages,
    required Character character,
    required Persona? persona,
    bool clearExisting = true,
  }) async {
    final preset = _resolveActivePreset();
    if (preset == null) return;

    if (clearExisting) {
      await _ref
          .read(infoBlocksProvider(sessionId).notifier)
          .deleteByMessageId(messageId);
    }

    _refreshPanelForMessage(charId, sessionId, messageId);

    _blocksCancelToken = CancelToken();
    await _runChain(
      charId: charId,
      sessionId: sessionId,
      messageId: messageId,
      messages: messages,
      preset: preset,
      character: character,
      persona: persona,
      cancelToken: _blocksCancelToken!,
    );
    _refreshPanelForMessage(charId, sessionId, messageId);
  }

  ExtensionPreset? _resolveActivePreset() {
    final settings = _ref.read(extensionsSettingsProvider);
    if (!settings.enabled) {
      debugPrint('[ExtPostGen] SKIP: settings.enabled=false');
      return null;
    }
    final presetId = settings.activePresetId;
    if (presetId == null || presetId.isEmpty) {
      debugPrint('[ExtPostGen] SKIP: presetId is null/empty');
      return null;
    }
    final preset =
        _ref.read(extensionPresetsProvider).where((pr) => pr.id == presetId).firstOrNull;
    if (preset == null) {
      debugPrint('[ExtPostGen] SKIP: preset not found');
      return null;
    }
    return preset;
  }

  /// Called by GenerationPipeline after assistant message is finalised.
  Future<void> processAfterGeneration({
    required String charId,
    required ChatSession session,
    required Character character,
    required Persona? persona,
  }) async {
    debugPrint('[ExtPostGen] processAfterGeneration: session=${session.id}');
    if (session.id.isEmpty || session.messages.isEmpty) return;

    final lastMessage = session.messages.last;
    if (lastMessage.role == 'user') {
      debugPrint('[ExtPostGen] SKIP: last message is user');
      return;
    }

    await runBlocksForMessage(
      charId: charId,
      sessionId: session.id,
      messageId: lastMessage.id,
      messages: session.messages,
      character: character,
      persona: persona,
    );
  }

  /// Re-runs a single block for an already-existing message.
  Future<void> rerunBlock({
    required String blockId,
    required String messageId,
    required String sessionId,
    required String charId,
    required List<ChatMessage> messages,
    required Character character,
    required Persona? persona,
  }) async {
    final preset = _resolveActivePreset();
    if (preset == null) return;

    final blockConfig = preset.blocks.where((b) => b.id == blockId).firstOrNull;
    if (blockConfig == null) return;

    final cancelToken = CancelToken();
    _blocksCancelToken = cancelToken;

    final reuseBlockId = await _dedupeBlocksForConfig(
      sessionId: sessionId,
      messageId: messageId,
      blockId: blockId,
    );

    final block = await _runSingleBlock(
      charId: charId,
      sessionId: sessionId,
      messageId: messageId,
      messages: messages,
      blockConfig: blockConfig,
      preset: preset,
      character: character,
      persona: persona,
      previousOutput: null,
      cancelToken: cancelToken,
      reuseBlockId: reuseBlockId,
    );

    if (block != null) {
      _ref.read(infoBlocksProvider(sessionId).notifier).addOrReplace(block);
    }
    _refreshPanelForMessage(charId, sessionId, messageId);
  }

  /// Cancels any in-flight block generation for the current session.
  void cancelBlocks() {
    _blocksCancelToken?.cancel();
    _blocksCancelToken = null;
  }

  DateTime? _lastStreamPanelAt;

  void _publishStreamingBlockContent({
    required String charId,
    required String sessionId,
    required String messageId,
    required InfoBlock placeholder,
    required String content,
    bool force = false,
  }) {
    final now = DateTime.now();
    if (!force &&
        _lastStreamPanelAt != null &&
        now.difference(_lastStreamPanelAt!) <
            const Duration(milliseconds: 80)) {
      return;
    }
    _lastStreamPanelAt = now;
    final updated =
        placeholder.copyWith(content: content, status: BlockRunStatus.running);
    _ref.read(infoBlocksProvider(sessionId).notifier).addOrReplace(updated);
    _enqueuePanelJs(() => _patchOrRefreshPanel(
          charId: charId,
          sessionId: sessionId,
          messageId: messageId,
          blockId: placeholder.blockId,
          content: content,
          status: BlockRunStatus.running.name,
        ));
  }

  void Function(String)? _makeStreamHandler({
    required BlockConfig blockConfig,
    required String charId,
    required String sessionId,
    required String messageId,
    required InfoBlock placeholder,
  }) {
    if (!blockConfig.streamToPanel) return null;
    return (partial) => _publishStreamingBlockContent(
          charId: charId,
          sessionId: sessionId,
          messageId: messageId,
          placeholder: placeholder,
          content: partial,
        );
  }

  /// Re-runs only the Image Gen step for an existing image ext block (keeps agent HTML).
  Future<void> rerunImageOnly({
    required String blockId,
    required String messageId,
    required String sessionId,
    required String charId,
    required Character character,
    required Persona? persona,
  }) async {
    final preset = _resolveActivePreset();
    if (preset == null) return;

    final blockConfig = preset.blocks.where((b) => b.id == blockId).firstOrNull;
    if (blockConfig == null || blockConfig.type != BlockType.imageGen) return;

    final rows = await _repo.getByMessageId(sessionId, messageId);
    final existing = rows.where((b) => b.blockId == blockId).firstOrNull;
    if (existing == null || existing.content.isEmpty) return;

    final imageService =
        await _ref.read(imageGenSettingsProvider.notifier).getServiceAsync();
    if (imageService.extractInstructionsFromImageContent(existing.content).isEmpty) {
      return;
    }

    final cancelToken = CancelToken();
    _blocksCancelToken = cancelToken;

    await _repo.updateStatus(existing.id, BlockRunStatus.running);
    _ref
        .read(infoBlocksProvider(sessionId).notifier)
        .addOrReplace(existing.copyWith(status: BlockRunStatus.running));
    _refreshPanelForMessage(charId, sessionId, messageId);

    await _renderImagePixels(
      charId: charId,
      sessionId: sessionId,
      messageId: messageId,
      blockConfig: blockConfig,
      character: character,
      persona: persona,
      sourceContent: existing.content,
      placeholderId: existing.id,
      placeholder: existing,
      cancelToken: cancelToken,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Chain execution
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _runChain({
    required String charId,
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

    debugPrint('[ExtPostGen] _runChain: enabledBlocks=${blocks.length} (of ${preset.blocks.length})');
    if (blocks.isEmpty) {
      debugPrint('[ExtPostGen] SKIP: no enabled blocks in preset');
      return;
    }

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
            charId: charId,
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
          charId: charId,
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
    required String charId,
    required String sessionId,
    required String messageId,
    required List<ChatMessage> messages,
    required BlockConfig blockConfig,
    required ExtensionPreset preset,
    required Character character,
    required Persona? persona,
    required String? previousOutput,
    required CancelToken cancelToken,
    String? reuseBlockId,
  }) async {
    if (cancelToken.isCancelled) return null;

    debugPrint('[ExtPostGen] _runSingleBlock START: name="${blockConfig.name}" type=${blockConfig.type.name} order=${blockConfig.order} reuse=${reuseBlockId ?? "new"}');

    final String placeholderId;
    final InfoBlock placeholder;

    if (reuseBlockId != null) {
      placeholderId = reuseBlockId;
      final existing = await _repo.getByMessageId(sessionId, messageId);
      final row = existing.where((b) => b.id == reuseBlockId).firstOrNull;
      placeholder = (row ?? InfoBlock(
        id: reuseBlockId,
        sessionId: sessionId,
        messageId: messageId,
        blockId: blockConfig.id,
        blockName: blockConfig.name,
        blockType: blockConfig.type.name,
        content: '',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        order: blockConfig.order,
        status: BlockRunStatus.running,
      )).copyWith(content: '', status: BlockRunStatus.running);
      await _repo.updateContent(placeholderId, '');
      await _repo.updateStatus(placeholderId, BlockRunStatus.running);
      _ref.read(infoBlocksProvider(sessionId).notifier).addOrReplace(placeholder);
      _refreshPanelForMessage(charId, sessionId, messageId);
      debugPrint('[ExtPostGen] reused block id=$placeholderId messageId=$messageId status=running');
    } else {
      placeholderId = generateId();
      placeholder = InfoBlock(
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
      debugPrint('[ExtPostGen] placeholder inserted: id=$placeholderId messageId=$messageId status=running');
    }

    _refreshPanelForMessage(charId, sessionId, messageId);

    try {
      InfoBlock? result;

      switch (blockConfig.type) {
        case BlockType.infoblock:
          result = await _runInfoblock(
            charId: charId,
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
            placeholder: placeholder,
          );
        case BlockType.imageGen:
          result = await _runImageGen(
            charId: charId,
            sessionId: sessionId,
            messageId: messageId,
            messages: messages,
            blockConfig: blockConfig,
            character: character,
            persona: persona,
            previousOutput: previousOutput,
            cancelToken: cancelToken,
            placeholderId: placeholderId,
            placeholder: placeholder,
          );
        case BlockType.jsRunner:
          result = await _runJsRunner(
            charId: charId,
            sessionId: sessionId,
            messageId: messageId,
            messages: messages,
            blockConfig: blockConfig,
            character: character,
            persona: persona,
            previousOutput: previousOutput,
            cancelToken: cancelToken,
            placeholderId: placeholderId,
            placeholder: placeholder,
          );
      }

      return result;
    } catch (e) {
      if (!cancelToken.isCancelled) {
        debugPrint('[ExtPostGen] Error in block "${blockConfig.name}": $e');
        return _markBlockError(
          charId: charId,
          sessionId: sessionId,
          messageId: messageId,
          placeholderId: placeholderId,
          placeholder: placeholder,
          errorMessage: e.toString(),
        );
      }
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Infoblock
  // ─────────────────────────────────────────────────────────────────────────

  Future<InfoBlock?> _runInfoblock({
    required String charId,
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
    required InfoBlock placeholder,
  }) async {
    debugPrint('[ExtPostGen] _runInfoblock START: name="${blockConfig.name}" promptLen=${blockConfig.prompt.length} apiConfigId="${blockConfig.apiConfigId}" model="${blockConfig.model}"');
    final infoBlockService = _ref.read(infoBlockServiceProvider);
    final generated = await infoBlockService.generateSingleBlockContent(
      sessionId: sessionId,
      messageId: messageId,
      messages: messages,
      blockConfig: blockConfig,
      character: character,
      persona: persona?.name,
      previousOutput: previousOutput,
      cancelToken: cancelToken,
      onStreamUpdate: _makeStreamHandler(
        blockConfig: blockConfig,
        charId: charId,
        sessionId: sessionId,
        messageId: messageId,
        placeholder: placeholder,
      ),
    );
    debugPrint('[ExtPostGen] _runInfoblock DONE: name="${blockConfig.name}" contentLen=${generated.content?.length ?? 0} error=${generated.error}');

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
      _refreshPanelForMessage(charId, sessionId, messageId);
      return stopped;
    }

    if (generated.error != null) {
      return _markBlockError(
        charId: charId,
        sessionId: sessionId,
        messageId: messageId,
        placeholderId: placeholderId,
        placeholder: placeholder,
        errorMessage: generated.error!,
      );
    }

    final content = generated.content;
    if (content == null || content.isEmpty) {
      return _markBlockError(
        charId: charId,
        sessionId: sessionId,
        messageId: messageId,
        placeholderId: placeholderId,
        placeholder: placeholder,
        errorMessage: 'Generation produced empty content',
      );
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
    _refreshPanelForMessage(charId, sessionId, messageId);
    return done;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Image gen
  // ─────────────────────────────────────────────────────────────────────────

  Future<InfoBlock?> _runImageGen({
    required String charId,
    required String sessionId,
    required String messageId,
    required List<ChatMessage> messages,
    required BlockConfig blockConfig,
    required Character character,
    required Persona? persona,
    required String? previousOutput,
    required CancelToken cancelToken,
    required String placeholderId,
    required InfoBlock placeholder,
  }) async {
    debugPrint('[ExtPostGen] _runImageGen START: name="${blockConfig.name}"');

    // Step 1 — LLM image agent (U+A+previous block → HTML with [IMG:GEN]).
    final infoBlockService = _ref.read(infoBlockServiceProvider);
    final generated = await infoBlockService.generateSingleBlockContent(
      sessionId: sessionId,
      messageId: messageId,
      messages: messages,
      blockConfig: blockConfig,
      character: character,
      persona: persona?.name,
      previousOutput: previousOutput,
      cancelToken: cancelToken,
      onStreamUpdate: _makeStreamHandler(
        blockConfig: blockConfig,
        charId: charId,
        sessionId: sessionId,
        messageId: messageId,
        placeholder: placeholder,
      ),
    );

    if (cancelToken.isCancelled) {
      await _repo.updateStatus(placeholderId, BlockRunStatus.stopped);
      return placeholder.copyWith(status: BlockRunStatus.stopped);
    }

    if (generated.error != null || generated.content == null) {
      return _markBlockError(
        charId: charId,
        sessionId: sessionId,
        messageId: messageId,
        placeholderId: placeholderId,
        placeholder: placeholder,
        errorMessage: generated.error ?? 'Image agent returned empty response',
      );
    }

    final agentHtml = generated.content!;
    _publishStreamingBlockContent(
      charId: charId,
      sessionId: sessionId,
      messageId: messageId,
      placeholder: placeholder,
      content: agentHtml,
      force: true,
    );

    return _renderImagePixels(
      charId: charId,
      sessionId: sessionId,
      messageId: messageId,
      blockConfig: blockConfig,
      character: character,
      persona: persona,
      sourceContent: agentHtml,
      placeholderId: placeholderId,
      placeholder: placeholder,
      cancelToken: cancelToken,
    );
  }

  Future<InfoBlock?> _renderImagePixels({
    required String charId,
    required String sessionId,
    required String messageId,
    required BlockConfig blockConfig,
    required Character character,
    required Persona? persona,
    required String sourceContent,
    required String placeholderId,
    required InfoBlock placeholder,
    required CancelToken cancelToken,
  }) async {
    final imgGenSettings = _ref.read(imageGenSettingsProvider).value;
    if (imgGenSettings == null || !imgGenSettings.enabled) {
      await _repo.updateContent(placeholderId, sourceContent);
      await _repo.updateStatus(placeholderId, BlockRunStatus.done);
      final done =
          placeholder.copyWith(content: sourceContent, status: BlockRunStatus.done);
      _ref.read(infoBlocksProvider(sessionId).notifier).addOrReplace(done);
      _refreshPanelForMessage(charId, sessionId, messageId);
      return done;
    }

    final imageService =
        await _ref.read(imageGenSettingsProvider.notifier).getServiceAsync();
    final instructions =
        imageService.extractInstructionsFromImageContent(sourceContent);
    if (instructions.isEmpty) {
      return _markBlockError(
        charId: charId,
        sessionId: sessionId,
        messageId: messageId,
        placeholderId: placeholderId,
        placeholder: placeholder,
        errorMessage:
            'No image instruction found (expected [IMG:GEN] or [IMG:RESULT:…|json])',
      );
    }

    final rawPrompt = instructions.first['prompt'] as String? ?? '';
    if (rawPrompt.isEmpty) {
      return _markBlockError(
        charId: charId,
        sessionId: sessionId,
        messageId: messageId,
        placeholderId: placeholderId,
        placeholder: placeholder,
        errorMessage: 'Image instruction JSON has empty prompt',
      );
    }

    _publishStreamingBlockContent(
      charId: charId,
      sessionId: sessionId,
      messageId: messageId,
      placeholder: placeholder,
      content: '$sourceContent\n<p class="ext-block-image-pending">⏳ Генерация изображения…</p>',
      force: true,
    );

    try {
      List<String>? recentImageContexts;
      if (imgGenSettings.imageContextEnabled) {
        final sessionBlocks = await _repo.getBySessionId(sessionId);
        final imageContents = sessionBlocks
            .where(
              (b) =>
                  b.blockType == BlockType.imageGen.name &&
                  b.status == BlockRunStatus.done &&
                  b.id != placeholderId,
            )
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        recentImageContexts = ImageGenService.collectRecentImageResultPaths(
          imageContents.map((b) => b.content),
          maxPaths: 3,
        );
        if (recentImageContexts.isEmpty) recentImageContexts = null;
      }

      final style = instructions.first['style'] as String? ?? '';
      var cleanPrompt = rawPrompt.replaceFirst(RegExp(r'^SCENE_PROMPT:\s*'), '');
      final prompt = style.isNotEmpty ? '$style, $cleanPrompt' : cleanPrompt;
      final instructionAspectRatio =
          instructions.first['aspect_ratio'] as String?;
      final instructionImageSize = instructions.first['image_size'] as String?;

      final imageBytes = await imageService.generateImage(
        settings: imgGenSettings,
        prompt: prompt,
        llmEndpoint: '',
        llmApiKey: '',
        llmModel: '',
        character: character,
        persona: persona,
        recentImageContexts: recentImageContexts,
        instructionAspectRatio: instructionAspectRatio,
        instructionImageSize: instructionImageSize,
        cancelToken: cancelToken,
      );

      if (cancelToken.isCancelled) {
        await _repo.updateStatus(placeholderId, BlockRunStatus.stopped);
        return placeholder.copyWith(status: BlockRunStatus.stopped);
      }

      final storage = await _ref.read(imageStorageProvider.future);
      final dir = Directory(p.join(storage.baseDir, 'generated'));
      if (!await dir.exists()) await dir.create(recursive: true);
      final filename = 'extblock_${DateTime.now().millisecondsSinceEpoch}.png';
      final filePath = p.join(dir.path, filename);
      await File(filePath).writeAsBytes(imageBytes);

      final hasResultToken =
          ImgGenPatterns.imgResultRegex.hasMatch(sourceContent);
      final content = hasResultToken
          ? imageService.replaceExtBlockImageResult(sourceContent, filePath)
          : imageService.replaceTagWithResult(sourceContent, 0, filePath);
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
      _refreshPanelForMessage(charId, sessionId, messageId);
      return done;
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        await _repo.updateStatus(placeholderId, BlockRunStatus.stopped);
        return placeholder.copyWith(status: BlockRunStatus.stopped);
      }
      return _markBlockError(
        charId: charId,
        sessionId: sessionId,
        messageId: messageId,
        placeholderId: placeholderId,
        placeholder: placeholder,
        errorMessage: e.toString(),
      );
    } catch (e) {
      return _markBlockError(
        charId: charId,
        sessionId: sessionId,
        messageId: messageId,
        placeholderId: placeholderId,
        placeholder: placeholder,
        errorMessage: e.toString(),
      );
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // JS Runner
  // ─────────────────────────────────────────────────────────────────────────

  Future<InfoBlock?> _runJsRunner({
    required String charId,
    required String sessionId,
    required String messageId,
    required List<ChatMessage> messages,
    required BlockConfig blockConfig,
    required Character character,
    required Persona? persona,
    required String? previousOutput,
    required CancelToken cancelToken,
    required String placeholderId,
    required InfoBlock placeholder,
  }) async {
    if (cancelToken.isCancelled) {
      await _repo.updateStatus(placeholderId, BlockRunStatus.stopped);
      return placeholder.copyWith(status: BlockRunStatus.stopped);
    }

    final prompt = blockConfig.prompt.trim();
    final staticScript = blockConfig.script.trim();

    // Legacy: hand-written script without LLM prompt.
    if (prompt.isEmpty && staticScript.isNotEmpty) {
      return _executeJsScript(
        charId: charId,
        sessionId: sessionId,
        messageId: messageId,
        messages: messages,
        blockConfig: blockConfig,
        character: character,
        previousOutput: previousOutput,
        cancelToken: cancelToken,
        placeholderId: placeholderId,
        placeholder: placeholder,
        script: staticScript,
      );
    }

    if (prompt.isEmpty) {
      debugPrint('[ExtPostGen] jsRunner "${blockConfig.name}" — prompt is empty');
      await _repo.updateStatus(placeholderId, BlockRunStatus.done);
      _refreshPanelForMessage(charId, sessionId, messageId);
      return placeholder.copyWith(status: BlockRunStatus.done);
    }

    debugPrint('[ExtPostGen] _runJsRunner START: name="${blockConfig.name}"');

    final infoBlockService = _ref.read(infoBlockServiceProvider);
    final generated = await infoBlockService.generateSingleBlockContent(
      sessionId: sessionId,
      messageId: messageId,
      messages: messages,
      blockConfig: blockConfig,
      character: character,
      persona: persona?.name,
      previousOutput: previousOutput,
      cancelToken: cancelToken,
      onStreamUpdate: _makeStreamHandler(
        blockConfig: blockConfig,
        charId: charId,
        sessionId: sessionId,
        messageId: messageId,
        placeholder: placeholder,
      ),
    );

    if (cancelToken.isCancelled) {
      await _repo.updateStatus(placeholderId, BlockRunStatus.stopped);
      return placeholder.copyWith(status: BlockRunStatus.stopped);
    }

    if (generated.error != null || generated.content == null) {
      return _markBlockError(
        charId: charId,
        sessionId: sessionId,
        messageId: messageId,
        placeholderId: placeholderId,
        placeholder: placeholder,
        errorMessage: generated.error ?? 'JS agent returned empty response',
      );
    }

    final agentOutput = generated.content!;
    _publishStreamingBlockContent(
      charId: charId,
      sessionId: sessionId,
      messageId: messageId,
      placeholder: placeholder,
      content: agentOutput,
      force: true,
    );

    final script = JsScriptExtractor.extractFromLlmResponse(agentOutput);
    if (script == null || script.isEmpty) {
      return _markBlockError(
        charId: charId,
        sessionId: sessionId,
        messageId: messageId,
        placeholderId: placeholderId,
        placeholder: placeholder,
        errorMessage:
            'No JavaScript found in LLM response (expected ```js … ``` fence or raw code)',
      );
    }

    _publishStreamingBlockContent(
      charId: charId,
      sessionId: sessionId,
      messageId: messageId,
      placeholder: placeholder,
      content:
          '$agentOutput\n<p class="ext-block-js-pending">⏳ Выполнение JS…</p>',
      force: true,
    );

    return _executeJsScript(
      charId: charId,
      sessionId: sessionId,
      messageId: messageId,
      messages: messages,
      blockConfig: blockConfig,
      character: character,
      previousOutput: previousOutput,
      cancelToken: cancelToken,
      placeholderId: placeholderId,
      placeholder: placeholder,
      script: script,
      panelContentBuilder: (result) =>
          JsScriptExtractor.formatPanelContent(script: script, result: result),
    );
  }

  Future<InfoBlock?> _executeJsScript({
    required String charId,
    required String sessionId,
    required String messageId,
    required List<ChatMessage> messages,
    required BlockConfig blockConfig,
    required Character character,
    required String? previousOutput,
    required CancelToken cancelToken,
    required String placeholderId,
    required InfoBlock placeholder,
    required String script,
    String Function(String result)? panelContentBuilder,
  }) async {
    final bridge = _ref.read(chatBridgeRegistryProvider(charId));
    if (bridge == null) {
      debugPrint(
        '[ExtPostGen] jsRunner "${blockConfig.name}" — bridge not available',
      );
      return _markBlockError(
        charId: charId,
        sessionId: sessionId,
        messageId: messageId,
        placeholderId: placeholderId,
        placeholder: placeholder,
        errorMessage:
            'WebView bridge not available (JS runner requires open chat)',
      );
    }

    try {
      final contextMessages = buildContextMessages(
        messages: messages,
        anchorMessageId: messageId,
        count: blockConfig.contextMessageCount,
      );
      final result = await bridge.runJsBlock(
        script: script,
        messages: contextMessages,
        character: character,
        previousOutput: previousOutput,
        contextMessageCount: -1,
        cancelToken: cancelToken,
      );

      if (cancelToken.isCancelled) {
        await _repo.updateStatus(placeholderId, BlockRunStatus.stopped);
        final stopped = placeholder.copyWith(status: BlockRunStatus.stopped);
        _ref.read(infoBlocksProvider(sessionId).notifier).addOrReplace(stopped);
        _refreshPanelForMessage(charId, sessionId, messageId);
        return stopped;
      }

      final content = panelContentBuilder?.call(result) ?? result;

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
      _refreshPanelForMessage(charId, sessionId, messageId);
      return done;
    } catch (e) {
      if (cancelToken.isCancelled) {
        await _repo.updateStatus(placeholderId, BlockRunStatus.stopped);
        final stopped = placeholder.copyWith(status: BlockRunStatus.stopped);
        _ref.read(infoBlocksProvider(sessionId).notifier).addOrReplace(stopped);
        _refreshPanelForMessage(charId, sessionId, messageId);
        return stopped;
      }
      debugPrint('[ExtPostGen] jsRunner "${blockConfig.name}" failed: $e');
      return _markBlockError(
        charId: charId,
        sessionId: sessionId,
        messageId: messageId,
        placeholderId: placeholderId,
        placeholder: placeholder,
        errorMessage: e.toString(),
      );
    }
  }
}
