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
import '../../chat/bridge/chat_bridge_controller.dart';
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
import 'info_block_service.dart';
import 'js_engine_service.dart';
import 'blocks/block_processor.dart';
import 'blocks/block_context.dart';
import 'blocks/block_panel_updater.dart';
import 'blocks/image_gen_block_handler.dart';
import 'blocks/interactive_block_handler.dart';
import 'blocks/js_runner_block_handler.dart';
import 'blocks/infoblock_handler.dart';
import 'blocks/block_status_tracker.dart';

final extensionPostGenServiceProvider = Provider<ExtensionPostGenService>(
  (ref) => ExtensionPostGenService(ref),
);

/// Orchestrates extension block generation after chat response.
/// Blocks are run in `order` sequence; blocks with [BlockConfig.dependsOnPrevious]
/// wait for the previous block to finish (done or error) before starting.
/// Independently-configured blocks start in parallel with the previous one.
class ExtensionPostGenService {
  ExtensionPostGenService(this._ref) : _panelUpdater = BlockPanelUpdater(_ref);

  final Ref _ref;
  final BlockPanelUpdater _panelUpdater;

  /// Active cancel token for the current block run. Cancelling this stops
  /// all in-flight block LLM/image calls without touching the main gen token.
  CancelToken? _blocksCancelToken;

  final BlockProcessor _blockProcessor = const BlockProcessor();

  InfoBlocksRepository get _repo =>
      InfoBlocksRepository(_ref.read(appDbProvider));

  BlockStatusTracker get _statusTracker => BlockStatusTracker(
    ref: _ref,
    repo: _repo,
    refreshPanelForMessage: _refreshPanelForMessage,
  );

  void _refreshPanelForMessage(
    String charId,
    String sessionId,
    String messageId,
  ) {
    _panelUpdater.refreshForMessage(charId, sessionId, messageId);
  }

  Future<InfoBlock> _markContextBlockError({
    required BlockContext context,
    required String errorMessage,
  }) {
    return _statusTracker.markError(
      context: context,
      errorMessage: errorMessage,
    );
  }

  Future<InfoBlock> _markBlockError({
    required String charId,
    required String sessionId,
    required String messageId,
    required String placeholderId,
    required InfoBlock placeholder,
    required String errorMessage,
  }) {
    return _statusTracker.markErrorForPlaceholder(
      charId: charId,
      sessionId: sessionId,
      messageId: messageId,
      placeholderId: placeholderId,
      placeholder: placeholder,
      errorMessage: errorMessage,
    );
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
      trigger: BlockTrigger.afterAssistant,
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
    final preset = _ref
        .read(extensionPresetsProvider)
        .where((pr) => pr.id == presetId)
        .firstOrNull;
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

  /// Called by [ChatNotifier.sendMessage] right after a user message is
  /// persisted. Runs every enabled `BlockTrigger.afterUser` block.
  Future<void> runAfterUserBlocks({
    required String charId,
    required ChatSession session,
    required Character character,
    required Persona? persona,
  }) async {
    final preset = _resolveActivePreset();
    if (preset == null) return;
    if (session.id.isEmpty || session.messages.isEmpty) return;
    final lastMessage = session.messages.last;
    if (lastMessage.role != 'user') {
      debugPrint(
        '[ExtPostGen] runAfterUserBlocks: last message is not user, skipping',
      );
      return;
    }
    debugPrint('[ExtPostGen] runAfterUserBlocks: msg=${lastMessage.id}');
    _blocksCancelToken = CancelToken();
    await _runChain(
      charId: charId,
      sessionId: session.id,
      messageId: lastMessage.id,
      messages: session.messages,
      preset: preset,
      character: character,
      persona: persona,
      cancelToken: _blocksCancelToken!,
      trigger: BlockTrigger.afterUser,
    );
    _refreshPanelForMessage(charId, session.id, lastMessage.id);
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

    final reuseBlockId = await _statusTracker.dedupeForConfig(
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

  void _publishStreamingBlockContent({
    required String charId,
    required String sessionId,
    required String messageId,
    required InfoBlock placeholder,
    required String content,
    bool force = false,
  }) {
    _panelUpdater.publishStreamingContent(
      charId: charId,
      sessionId: sessionId,
      messageId: messageId,
      placeholder: placeholder,
      content: content,
      force: force,
    );
  }

  void Function(String)? _makeStreamHandler({
    required BlockConfig blockConfig,
    required String charId,
    required String sessionId,
    required String messageId,
    required InfoBlock placeholder,
  }) {
    return _panelUpdater.makeStreamHandler(
      blockConfig: blockConfig,
      charId: charId,
      sessionId: sessionId,
      messageId: messageId,
      placeholder: placeholder,
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

    final imageService = await _ref
        .read(imageGenSettingsProvider.notifier)
        .getServiceAsync();
    if (imageService
        .extractInstructionsFromImageContent(existing.content)
        .isEmpty) {
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
    BlockTrigger trigger = BlockTrigger.afterAssistant,
  }) async {
    await _blockProcessor.run(
      preset: preset,
      trigger: trigger,
      cancelToken: cancelToken,
      runBlock: ({required blockConfig, required previousOutput}) {
        return _runSingleBlock(
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
        );
      },
      onBlockComplete: (result) {
        _ref.read(infoBlocksProvider(sessionId).notifier).addOrReplace(result);
      },
    );
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

    debugPrint(
      '[ExtPostGen] _runSingleBlock START: name="${blockConfig.name}" type=${blockConfig.type.name} order=${blockConfig.order} reuse=${reuseBlockId ?? "new"}',
    );

    final prepared = await _statusTracker.prepare(
      charId: charId,
      sessionId: sessionId,
      messageId: messageId,
      blockConfig: blockConfig,
      reuseBlockId: reuseBlockId,
    );
    final placeholderId = prepared.placeholderId;
    final placeholder = prepared.placeholder;

    _refreshPanelForMessage(charId, sessionId, messageId);

    try {
      InfoBlock? result;

      switch (blockConfig.type) {
        case BlockType.infoblock:
          result = await _runInfoblock(
            BlockContext(
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
            ),
          );
        case BlockType.imageGen:
          result = await _runImageGen(
            BlockContext(
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
            ),
          );
        case BlockType.jsRunner:
          result = await _runJsRunner(
            BlockContext(
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
            ),
          );
        case BlockType.interactive:
          result = await _runInteractive(
            BlockContext(
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
            ),
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

  Future<InfoBlock?> _runInfoblock(BlockContext context) {
    return InfoblockHandler(
      ref: _ref,
      repo: _repo,
      markBlockError: _markContextBlockError,
      refreshPanelForMessage: _refreshPanelForMessage,
      makeStreamHandler: _makeStreamHandler,
    ).handle(context);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Image gen
  // ─────────────────────────────────────────────────────────────────────────

  Future<InfoBlock?> _runImageGen(BlockContext context) {
    return ImageGenBlockHandler(
      ref: _ref,
      repo: _repo,
      markBlockError: _markContextBlockError,
      makeStreamHandler: _makeStreamHandler,
      publishStreamingBlockContent: _publishStreamingBlockContent,
      renderImagePixels: _renderContextImagePixels,
    ).handle(context);
  }

  Future<InfoBlock?> _renderContextImagePixels({
    required BlockContext context,
    required String sourceContent,
  }) {
    return _renderImagePixels(
      charId: context.charId,
      sessionId: context.sessionId,
      messageId: context.messageId,
      blockConfig: context.blockConfig,
      character: context.character,
      persona: context.persona,
      sourceContent: sourceContent,
      placeholderId: context.placeholderId,
      placeholder: context.placeholder,
      cancelToken: context.cancelToken,
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
      final done = placeholder.copyWith(
        content: sourceContent,
        status: BlockRunStatus.done,
      );
      _ref.read(infoBlocksProvider(sessionId).notifier).addOrReplace(done);
      _refreshPanelForMessage(charId, sessionId, messageId);
      return done;
    }

    final imageService = await _ref
        .read(imageGenSettingsProvider.notifier)
        .getServiceAsync();
    final instructions = imageService.extractInstructionsFromImageContent(
      sourceContent,
    );
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
      content:
          '$sourceContent\n<p class="ext-block-image-pending">⏳ Генерация изображения…</p>',
      force: true,
    );

    try {
      List<String>? recentImageContexts;
      if (imgGenSettings.imageContextEnabled) {
        final sessionBlocks = await _repo.getBySessionId(sessionId);
        final imageContents =
            sessionBlocks
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
      var cleanPrompt = rawPrompt.replaceFirst(
        RegExp(r'^SCENE_PROMPT:\s*'),
        '',
      );
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

      final hasResultToken = ImgGenPatterns.imgResultRegex.hasMatch(
        sourceContent,
      );
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
  // Interactive panel
  // ─────────────────────────────────────────────────────────────────────────

  Future<InfoBlock?> _runInteractive(BlockContext context) {
    return InteractiveBlockHandler(
      ref: _ref,
      repo: _repo,
      markBlockError: _markContextBlockError,
      refreshPanelForMessage: _refreshPanelForMessage,
      publishStreamingBlockContent: _publishStreamingBlockContent,
    ).handle(context);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // JS Runner
  // ─────────────────────────────────────────────────────────────────────────

  Future<InfoBlock?> _runJsRunner(BlockContext context) {
    return JsRunnerBlockHandler(
      repo: _repo,
      infoBlockService: _ref.read(infoBlockServiceProvider),
      markBlockError: _markContextBlockError,
      refreshPanelForMessage: _refreshPanelForMessage,
      makeStreamHandler: _makeStreamHandler,
      publishStreamingBlockContent: _publishStreamingBlockContent,
      executeJsScript: _executeContextJsScript,
    ).handle(context);
  }

  Future<InfoBlock?> _executeContextJsScript({
    required BlockContext context,
    required String script,
    String Function(String result)? panelContentBuilder,
  }) {
    return _executeJsScript(
      charId: context.charId,
      sessionId: context.sessionId,
      messageId: context.messageId,
      messages: context.messages,
      blockConfig: context.blockConfig,
      character: context.character,
      previousOutput: context.previousOutput,
      cancelToken: context.cancelToken,
      placeholderId: context.placeholderId,
      placeholder: context.placeholder,
      script: script,
      panelContentBuilder: panelContentBuilder,
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
    final engine = JsEngineService.instance;
    if (!engine.isReady && bridge == null) {
      debugPrint(
        '[ExtPostGen] jsRunner "${blockConfig.name}" — no JS engine or bridge',
      );
      return _markBlockError(
        charId: charId,
        sessionId: sessionId,
        messageId: messageId,
        placeholderId: placeholderId,
        placeholder: placeholder,
        errorMessage:
            'JS engine not ready and WebView bridge not available (jsRunner needs at least one of them)',
      );
    }

    try {
      final contextMessages = buildContextMessages(
        messages: messages,
        anchorMessageId: messageId,
        count: blockConfig.contextMessageCount,
      );
      final result = await _runJsWithFallback(
        engine: engine,
        bridge: bridge,
        script: script,
        contextMessages: contextMessages,
        character: character,
        sessionId: sessionId,
        previousOutput: previousOutput,
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

  /// Runs [script] preferring the headless [engine] and falling back to
  /// the visual chat WebView [bridge] when the engine is not ready or
  /// raises [HeadlessUnavailableError]. Returns the script's string output.
  Future<String> _runJsWithFallback({
    required JsEngineService engine,
    required ChatBridgeController? bridge,
    required String script,
    required List<ChatMessage> contextMessages,
    required Character character,
    required String sessionId,
    required String? previousOutput,
    required CancelToken cancelToken,
  }) async {
    if (engine.isReady) {
      try {
        final contextMap = _jsContextMap(
          messages: contextMessages
              .map((m) => {'role': m.role, 'text': m.content})
              .toList(),
          character: character,
          sessionId: sessionId,
          previousOutput: previousOutput,
        );
        return await engine.runScript(
          script: script,
          context: contextMap,
          cancelToken: cancelToken,
        );
      } on HeadlessUnavailableError catch (e) {
        debugPrint(
          '[ExtPostGen] headless engine unavailable, falling back: $e',
        );
      } catch (e) {
        // Non-fatal: fall through to visual bridge. Bridge will record the
        // error in its own logs.
        debugPrint('[ExtPostGen] headless engine run failed: $e');
      }
    }
    final visualBridge = bridge;
    if (visualBridge == null) {
      throw StateError(
        'JS engine is not ready and visual WebView bridge is not available',
      );
    }
    return visualBridge.runJsBlock(
      script: script,
      messages: contextMessages,
      character: character,
      sessionId: sessionId,
      previousOutput: previousOutput,
      contextMessageCount: -1,
      cancelToken: cancelToken,
    );
  }

  Map<String, dynamic> _jsContextMap({
    required List<Map<String, String>> messages,
    required Character? character,
    required String sessionId,
    required String? previousOutput,
  }) {
    return {
      'messages': messages,
      'sessionId': sessionId,
      'characterId': character?.id,
      'character': character == null
          ? null
          : {
              'name': character.name,
              'description': character.description ?? '',
              'personality': character.personality ?? '',
              'scenario': character.scenario ?? '',
            },
      'previousOutput': previousOutput,
    };
  }

  /// Public entry point for periodic ticks (no `InfoBlock` is created —
  /// periodic scripts are side-effect-only: write to `glaze.variables`,
  /// play audio, call `triggerGeneration`, etc.). Uses the headless
  /// engine when available; falls back to the visual bridge for the
  /// currently open chat. Returns the script result string or `null`
  /// when nothing was run.
  ///
  /// `contextMessages` is the message history to pass to the script.
  /// For periodic ticks this is typically the empty list — the script
  /// does not need the chat history, it just runs on a timer.
  Future<String?> runJsBlock({
    required String charId,
    required BlockConfig block,
    required List<ChatMessage> contextMessages,
  }) async {
    if (block.type != BlockType.jsRunner) {
      throw ArgumentError(
        'runJsBlock only supports BlockType.jsRunner (got ${block.type.name})',
      );
    }
    final script = block.prompt.isNotEmpty ? block.prompt : block.script;
    if (script.isEmpty) {
      return null;
    }
    final engine = JsEngineService.instance;
    final bridge = _ref.read(chatBridgeRegistryProvider(charId));
    if (!engine.isReady && bridge == null) {
      debugPrint(
        '[ExtPostGen] runJsBlock: no engine or bridge (block "${block.name}")',
      );
      return null;
    }
    final cancelToken = CancelToken();
    try {
      if (engine.isReady) {
        try {
          final contextMap = _jsContextMap(
            messages: contextMessages
                .map((m) => {'role': m.role, 'text': m.content})
                .toList(),
            character: null, // no character payload for periodic
            sessionId: '',
            previousOutput: null,
          );
          // Periodic ticks have no character/session payload; the script
          // can still read `messages` from the context (empty list by
          // default).
          final patchedContext = Map<String, dynamic>.from(contextMap)
            ..['characterId'] = charId
            ..['sessionId'] = '';
          return await engine.runScript(
            script: script,
            context: patchedContext,
            cancelToken: cancelToken,
          );
        } on HeadlessUnavailableError catch (_) {
          // Fall through to visual bridge.
        }
      }
      final visualBridge = bridge;
      if (visualBridge == null) {
        return null;
      }
      return await visualBridge.runJsBlock(
        script: script,
        messages: contextMessages,
        character: null,
        sessionId: '',
        previousOutput: null,
        contextMessageCount: -1,
        cancelToken: cancelToken,
      );
    } catch (e) {
      debugPrint('[ExtPostGen] runJsBlock failed: $e');
      return null;
    }
  }
}
