import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/repositories/info_blocks_repository.dart';
import '../../../core/models/chat_message.dart';
import '../../../core/models/character.dart';
import '../../../core/models/persona.dart';
import '../../../core/state/db_provider.dart';
import '../models/block_config.dart';
import '../models/extension_preset.dart';
import '../models/info_block.dart';
import '../providers/extension_presets_provider.dart';
import '../providers/extensions_settings_provider.dart';
import '../providers/info_blocks_provider.dart';
import 'info_block_service.dart';
import 'blocks/block_processor.dart';
import 'blocks/block_context.dart';
import 'blocks/block_handler.dart';
import 'blocks/block_panel_updater.dart';
import 'blocks/image_gen_block_handler.dart';
import 'blocks/image_only_rerunner.dart';
import 'blocks/image_pixel_renderer.dart';
import 'blocks/interactive_block_handler.dart';
import 'blocks/js_block_executor.dart';
import 'blocks/js_runner_block_handler.dart';
import 'blocks/infoblock_handler.dart';
import 'blocks/block_status_tracker.dart';
import 'blocks/periodic_js_block_runner.dart';
import 'blocks/single_block_runner.dart';

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
    int swipeId,
  ) {
    _panelUpdater.refreshForMessage(charId, sessionId, messageId, swipeId);
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

  // ─────────────────────────────────────────────────────────────────────────
  // Public API
  // ─────────────────────────────────────────────────────────────────────────

  /// Runs all enabled preset blocks for [messageId]. Used after chat
  /// generation and from the manual "Запустить блоки" control.
  Future<void> runBlocksForMessage({
    required String charId,
    required String sessionId,
    required String messageId,
    required int swipeId,
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
          .deleteByMessageId(messageId, swipeId: swipeId);
    }

    _refreshPanelForMessage(charId, sessionId, messageId, swipeId);

    _blocksCancelToken = CancelToken();
    await _runChain(
      charId: charId,
      sessionId: sessionId,
      messageId: messageId,
      swipeId: swipeId,
      messages: messages,
      preset: preset,
      character: character,
      persona: persona,
      cancelToken: _blocksCancelToken!,
      trigger: BlockTrigger.afterAssistant,
    );
    _refreshPanelForMessage(charId, sessionId, messageId, swipeId);
  }

  ExtensionPreset? _resolveActivePreset() {
    final settings = _ref.read(extensionsSettingsProvider);
    if (!settings.enabled) {
      return null;
    }
    final presetId = settings.activePresetId;
    if (presetId == null || presetId.isEmpty) {
      return null;
    }
    final preset = _ref
        .read(extensionPresetsProvider)
        .where((pr) => pr.id == presetId)
        .firstOrNull;
    if (preset == null) {
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
    if (session.id.isEmpty || session.messages.isEmpty) return;

    final lastMessage = session.messages.last;
    if (lastMessage.role == 'user') {
      return;
    }

    await runBlocksForMessage(
      charId: charId,
      sessionId: session.id,
      messageId: lastMessage.id,
      swipeId: lastMessage.swipeId,
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
      return;
    }
    _blocksCancelToken = CancelToken();
    await _runChain(
      charId: charId,
      sessionId: session.id,
      messageId: lastMessage.id,
      swipeId: lastMessage.swipeId,
      messages: session.messages,
      preset: preset,
      character: character,
      persona: persona,
      cancelToken: _blocksCancelToken!,
      trigger: BlockTrigger.afterUser,
    );
    _refreshPanelForMessage(
      charId,
      session.id,
      lastMessage.id,
      lastMessage.swipeId,
    );
  }

  /// Re-runs a single block for an already-existing message.
  Future<void> rerunBlock({
    required String blockId,
    required String messageId,
    required int swipeId,
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
      swipeId: swipeId,
      blockId: blockId,
    );

    final block = await _runSingleBlock(
      charId: charId,
      sessionId: sessionId,
      messageId: messageId,
      swipeId: swipeId,
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
    _refreshPanelForMessage(charId, sessionId, messageId, swipeId);
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
    required int swipeId,
    required String sessionId,
    required String charId,
    required Character character,
    required Persona? persona,
  }) async {
    final preset = _resolveActivePreset();
    if (preset == null) return;

    final cancelToken = CancelToken();
    _blocksCancelToken = cancelToken;

    await ImageOnlyRerunner(
      ref: _ref,
      repo: _repo,
      refreshPanelForMessage: _refreshPanelForMessage,
      renderImagePixels: _renderImagePixels,
    ).rerun(
      blockId: blockId,
      charId: charId,
      sessionId: sessionId,
      messageId: messageId,
      swipeId: swipeId,
      character: character,
      persona: persona,
      blocks: preset.blocks,
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
    required int swipeId,
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
          swipeId: swipeId,
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
    required int swipeId,
    required List<ChatMessage> messages,
    required BlockConfig blockConfig,
    required ExtensionPreset preset,
    required Character character,
    required Persona? persona,
    required String? previousOutput,
    required CancelToken cancelToken,
    String? reuseBlockId,
  }) =>
      SingleBlockRunner(
        statusTracker: _statusTracker,
        refreshPanelForMessage: _refreshPanelForMessage,
        handlerFor: _handlerFor,
      ).run(
        charId: charId,
        sessionId: sessionId,
        messageId: messageId,
        swipeId: swipeId,
        messages: messages,
        blockConfig: blockConfig,
        preset: preset,
        character: character,
        persona: persona,
        previousOutput: previousOutput,
        cancelToken: cancelToken,
        reuseBlockId: reuseBlockId,
      );

  BlockHandler _handlerFor(BlockType type) {
    switch (type) {
      case BlockType.infoblock:
        return InfoblockHandler(
          ref: _ref,
          repo: _repo,
          markBlockError: _markContextBlockError,
          refreshPanelForMessage: _refreshPanelForMessage,
          makeStreamHandler: _makeStreamHandler,
        );
      case BlockType.imageGen:
        return ImageGenBlockHandler(
          ref: _ref,
          repo: _repo,
          markBlockError: _markContextBlockError,
          makeStreamHandler: _makeStreamHandler,
          publishStreamingBlockContent: _publishStreamingBlockContent,
          renderImagePixels: _renderContextImagePixels,
        );
      case BlockType.jsRunner:
        return JsRunnerBlockHandler(
          repo: _repo,
          infoBlockService: _ref.read(infoBlockServiceProvider),
          markBlockError: _markContextBlockError,
          refreshPanelForMessage: _refreshPanelForMessage,
          makeStreamHandler: _makeStreamHandler,
          publishStreamingBlockContent: _publishStreamingBlockContent,
          executeJsScript: _executeContextJsScript,
        );
      case BlockType.interactive:
        return InteractiveBlockHandler(
          ref: _ref,
          repo: _repo,
          markBlockError: _markContextBlockError,
          refreshPanelForMessage: _refreshPanelForMessage,
          publishStreamingBlockContent: _publishStreamingBlockContent,
        );
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Image gen
  // ─────────────────────────────────────────────────────────────────────────

  Future<InfoBlock?> _renderContextImagePixels({
    required BlockContext context,
    required String sourceContent,
  }) {
    return _renderImagePixels(
      charId: context.charId,
      sessionId: context.sessionId,
      messageId: context.messageId,
      swipeId: context.swipeId,
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
    required int swipeId,
    required BlockConfig blockConfig,
    required Character character,
    required Persona? persona,
    required String sourceContent,
    required String placeholderId,
    required InfoBlock placeholder,
    required CancelToken cancelToken,
  }) {
    return ImagePixelRenderer(
      ref: _ref,
      repo: _repo,
      markBlockError: _markContextBlockError,
      refreshPanelForMessage: _refreshPanelForMessage,
      publishStreamingBlockContent: _publishStreamingBlockContent,
    ).render(
      charId: charId,
      sessionId: sessionId,
      messageId: messageId,
      swipeId: swipeId,
      blockConfig: blockConfig,
      character: character,
      persona: persona,
      sourceContent: sourceContent,
      placeholderId: placeholderId,
      placeholder: placeholder,
      cancelToken: cancelToken,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // JS Runner
  // ─────────────────────────────────────────────────────────────────────────

  Future<InfoBlock?> _executeContextJsScript({
    required BlockContext context,
    required String script,
    String Function(String result)? panelContentBuilder,
  }) {
    return JsBlockExecutor(
      ref: _ref,
      repo: _repo,
      markBlockError: _markContextBlockError,
      refreshPanelForMessage: _refreshPanelForMessage,
    ).executeMessageScript(
      context: context,
      script: script,
      panelContentBuilder: panelContentBuilder,
    );
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
  }) => PeriodicJsBlockRunner(
    ref: _ref,
  ).run(charId: charId, block: block, contextMessages: contextMessages);
}
