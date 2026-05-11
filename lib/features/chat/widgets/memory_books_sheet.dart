import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/llm/lorebook_vector_search.dart';
import '../../../core/llm/memory_embedding_service.dart';
import '../../../core/llm/memory_injection_service.dart';
import '../../../core/models/chat_message.dart';
import '../../../core/models/memory_book.dart';
import '../../../core/state/db_provider.dart';
import '../../../core/state/memory_settings_provider.dart';
import '../../../core/utils/id_generator.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/widgets/glaze_bottom_sheet.dart';
import '../../../shared/widgets/glaze_toast.dart';
import '../chat_provider.dart';
import '../memory_draft_generator.dart';
import 'memory_entry_editor_sheet.dart';
import 'memory_generation_settings_sheet.dart';

class MemoryBooksSheet extends ConsumerStatefulWidget {
  final String sessionId;
  final String charId;

  const MemoryBooksSheet({super.key, required this.sessionId, required this.charId});

  @override
  ConsumerState<MemoryBooksSheet> createState() => _MemoryBooksSheetState();
}

class _MemoryBooksSheetState extends ConsumerState<MemoryBooksSheet> {
  MemoryBook? _book;
  bool _loading = true;
  bool _isReindexing = false;
  final Map<String, bool> _generatingDrafts = {};
  final Map<String, CancelToken> _cancelTokens = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = ref.read(memoryBookRepoProvider);
    final book = await repo.ensureForSession(widget.sessionId);
    if (mounted) setState(() { _book = book; _loading = false; });
  }

  Future<void> _save() async {
    if (_book == null) return;
    final repo = ref.read(memoryBookRepoProvider);
    await repo.put(_book!);
  }

  MemoryGlobalSettings get _gs => ref.read(memoryGlobalSettingsProvider);

  MemoryBookSettings _globalSettingsAsBookSettings() {
    final g = _gs;
    return MemoryBookSettings(
      enabled: g.enabled,
      autoCreateEnabled: g.autoCreateEnabled,
      autoGenerateEnabled: g.autoGenerateEnabled,
      maxInjectedEntries: g.maxInjectedEntries,
      autoCreateInterval: g.autoCreateInterval,
      useDelayedAutomation: g.useDelayedAutomation,
      injectionTarget: g.injectionTarget,
      batchSize: g.batchSize,
      vectorSearchEnabled: g.vectorSearchEnabled,
      keyMatchMode: g.keyMatchMode,
      generationSource: g.generationSource,
      generationModel: g.generationModel,
      generationEndpoint: g.generationEndpoint,
      generationApiKey: g.generationApiKey,
      generationTemperature: g.generationTemperature,
      generationMaxTokens: g.generationMaxTokens,
      promptPreset: g.promptPreset,
    );
  }

  String get _settingsSummary {
    if (_book == null) return '';
    final s = _gs;
    final interval = s.autoCreateInterval;
    final autoCreate = s.autoCreateEnabled ? 'Auto ON' : 'Auto OFF';
    final autoGen = s.autoGenerateEnabled ? 'Auto-gen' : 'Manual';
    final delayed = s.useDelayedAutomation ? 'Delayed' : 'Immediate';
    final target = s.injectionTarget == 'summary_macro' ? '{{summary}}' : 'Summary Block';
    final maxEntries = s.maxInjectedEntries;
    final batchSize = s.batchSize;
    final outTokens = (s.generationMaxTokens != null && s.generationMaxTokens! > 0)
        ? '${s.generationMaxTokens} out'
        : 'Auto out';
    return '$interval msgs • Batch $batchSize • $outTokens • $autoCreate • $autoGen • $delayed • $target • $maxEntries in prompt';
  }

  String get _searchModelLabel {
    final s = _gs;
    if (s == null) return '';
    return s.generationModel.isNotEmpty ? s.generationModel : 'Current LLM model';
  }

  String get _searchTypeLabel {
    final s = _book?.settings;
    if (s == null) return 'Vector';
    if (!s.vectorSearchEnabled) return 'Keys';
    if (s.keyMatchMode == 'both') return 'Vector + Keys';
    return 'Vector';
  }

  void _scanChat() async {
    if (_book == null) return;
    final chatState = ref.read(chatProvider(widget.charId));
    final session = chatState.value?.session;
    if (session == null) return;

    final messages = session.messages.where((m) =>
        !m.isTyping && (m.role == 'user' || m.role == 'assistant')).toList();
    if (messages.isEmpty) {
      if (mounted) GlazeToast.show(context, 'No stable messages to scan');
      return;
    }

    final coveredIds = <String>{};
    for (final entry in _book!.entries) {
      for (final id in entry.messageIds) {
        coveredIds.add(id);
      }
    }
    for (final draft in _book!.pendingDrafts) {
      for (final id in draft.messageIds) {
        coveredIds.add(id);
      }
    }

    final uncovered = messages.where((m) => m.id.isNotEmpty && !coveredIds.contains(m.id)).toList();
    if (uncovered.isEmpty) {
      if (mounted) GlazeToast.show(context, 'All messages are already covered');
      return;
    }

    final interval = _gs.autoCreateInterval;
    final segments = <List<ChatMessage>>[];
    for (int i = 0; i < uncovered.length; i += interval) {
      final end = (i + interval > uncovered.length) ? uncovered.length : i + interval;
      segments.add(uncovered.sublist(i, end));
    }

    if (segments.isEmpty) {
      if (mounted) GlazeToast.show(context, 'Need more uncovered messages before creating a draft');
      return;
    }

    final newDrafts = <MemoryDraft>[];
    for (int i = 0; i < segments.length; i++) {
      final segment = segments[i];
      final segmentIds = segment.map((m) => m.id).toList();
      final firstIdx = messages.indexOf(segment.first);
      final lastIdx = messages.indexOf(segment.last);

      final alreadyExists = _book!.pendingDrafts.any((d) =>
          d.messageIds.toSet().containsAll(segmentIds.toSet()));
      if (alreadyExists) continue;

      newDrafts.add(MemoryDraft(
        id: 'draft_${DateTime.now().millisecondsSinceEpoch}_${i}_${generateId().substring(0, 6)}',
        title: '${firstIdx + 1}-${lastIdx + 1}',
        messageIds: segmentIds,
        messageRange: MessageRange(start: firstIdx + 1, end: lastIdx + 1),
        status: 'pending_generation',
        source: 'scan_chat',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ));
    }

    if (newDrafts.isEmpty) {
      if (mounted) GlazeToast.show(context, 'All segments already have drafts');
      return;
    }

    setState(() {
      _book = _book!.copyWith(
        pendingDrafts: [..._book!.pendingDrafts, ...newDrafts],
      );
    });
    await _save();
    if (mounted) GlazeToast.show(context, '${newDrafts.length} drafts created');
  }

  void _generateAllPending() {
    if (_book == null) return;
    final needsGen = _book!.pendingDrafts.where((d) =>
        d.content.isEmpty &&
        (d.status == 'pending_generation' || d.status == 'needs_regeneration') &&
        _generatingDrafts[d.id] != true).toList();

    for (final draft in needsGen) {
      _generateDraft(draft.id);
    }
  }

  void _generateDraft(String draftId) async {
    if (_book == null || _generatingDrafts[draftId] == true) return;
    final draftIndex = _book!.pendingDrafts.indexWhere((d) => d.id == draftId);
    if (draftIndex < 0) return;

    final chatState = ref.read(chatProvider(widget.charId));
    final session = chatState.value?.session;
    if (session == null) return;

    final draft = _book!.pendingDrafts[draftIndex];
    final draftMessages = session.messages.where((m) => draft.messageIds.contains(m.id)).toList();
    if (draftMessages.isEmpty) {
      if (mounted) GlazeToast.show(context, 'Messages not found for this draft');
      return;
    }

    final historyText = draftMessages.map((m) => '${m.role}: ${m.content}').join('\n\n');
    final cancelToken = CancelToken();
    _cancelTokens[draftId] = cancelToken;

    setState(() { _generatingDrafts[draftId] = true; });

    try {
      final generator = MemoryDraftGenerator(ref);
      final result = await generator.generate(
        draft: draft,
        settings: _globalSettingsAsBookSettings(),
        historyText: historyText,
        cancelToken: cancelToken,
      );

      final updatedDrafts = [..._book!.pendingDrafts];
      updatedDrafts[draftIndex] = result;
      setState(() {
        _book = _book!.copyWith(pendingDrafts: updatedDrafts);
        _generatingDrafts.remove(draftId);
      });
      await _save();
    } catch (e) {
      final updatedDrafts = [..._book!.pendingDrafts];
      updatedDrafts[draftIndex] = updatedDrafts[draftIndex].copyWith(
        status: 'needs_regeneration',
        error: e.toString(),
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
      setState(() {
        _book = _book!.copyWith(pendingDrafts: updatedDrafts);
        _generatingDrafts.remove(draftId);
      });
      await _save();
      if (mounted) GlazeToast.show(context, 'Generation failed: $e');
    } finally {
      _cancelTokens.remove(draftId);
    }
  }

  void _cancelDraftGeneration(String draftId) {
    _cancelTokens[draftId]?.cancel();
    setState(() { _generatingDrafts.remove(draftId); });
  }

  void _batchGenerate() async {
    if (_book == null) return;
    final needsGen = _book!.pendingDrafts.where((d) =>
        d.content.isEmpty &&
        (d.status == 'pending_generation' || d.status == 'needs_regeneration') &&
        _generatingDrafts[d.id] != true).toList();
    final batchSize = _gs.batchSize;
    final toGenerate = needsGen.take(batchSize).toList();

    for (final draft in toGenerate) {
      _generateDraft(draft.id);
    }
  }

  void _approveDraft(String draftId) async {
    if (_book == null) return;
    final draftIndex = _book!.pendingDrafts.indexWhere((d) => d.id == draftId);
    if (draftIndex < 0) return;
    final draft = _book!.pendingDrafts[draftIndex];
    if (draft.content.isEmpty) return;

    final entry = MemoryEntry(
      id: draft.id.replaceAll('draft_', 'mem_'),
      title: draft.title,
      content: draft.content,
      keys: draft.keys,
      vectorSearch: draft.vectorSearch,
      messageIds: draft.messageIds,
      status: 'active',
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );

    setState(() {
      _book = _book!.copyWith(
        entries: [..._book!.entries, entry],
        pendingDrafts: _book!.pendingDrafts.where((d) => d.id != draftId).toList(),
      );
    });
    await _save();
  }

  void _deleteDraft(String draftId) async {
    if (_book == null) return;
    setState(() {
      _book = _book!.copyWith(
        pendingDrafts: _book!.pendingDrafts.where((d) => d.id != draftId).toList(),
      );
    });
    await _save();
  }

  void _deleteAllDrafts() async {
    if (_book == null) return;
    setState(() {
      _book = _book!.copyWith(pendingDrafts: []);
    });
    await _save();
  }

  void _deleteEntry(String entryId) async {
    if (_book == null) return;
    setState(() {
      _book = _book!.copyWith(
        entries: _book!.entries.where((e) => e.id != entryId).toList(),
      );
    });
    await _save();
    await ref.read(embeddingRepoProvider).deleteByEntryId(entryId);
  }

  void _openSettings() async {
    final currentSettings = _globalSettingsAsBookSettings();
    final newSettings = await GlazeBottomSheet.show<MemoryBookSettings>(
      context,
      title: 'Memory Settings',
      child: MemoryGenerationSettingsSheet(settings: currentSettings),
    );
    if (newSettings != null && mounted) {
      final newGlobal = MemoryGlobalSettings(
        enabled: newSettings.enabled,
        autoCreateEnabled: newSettings.autoCreateEnabled,
        autoGenerateEnabled: newSettings.autoGenerateEnabled,
        maxInjectedEntries: newSettings.maxInjectedEntries,
        autoCreateInterval: newSettings.autoCreateInterval,
        useDelayedAutomation: newSettings.useDelayedAutomation,
        injectionTarget: newSettings.injectionTarget,
        batchSize: newSettings.batchSize,
        parallelJobs: _gs.parallelJobs,
        vectorSearchEnabled: newSettings.vectorSearchEnabled,
        keyMatchMode: newSettings.keyMatchMode,
        generationSource: newSettings.generationSource,
        generationModel: newSettings.generationModel,
        generationUseCurrentModelOverride: _gs.generationUseCurrentModelOverride,
        generationEndpoint: newSettings.generationEndpoint,
        generationApiKey: newSettings.generationApiKey,
        generationTemperature: newSettings.generationTemperature,
        generationMaxTokens: newSettings.generationMaxTokens,
        promptPreset: newSettings.promptPreset,
        customPrompts: _gs.customPrompts,
      );
      await ref.read(memoryGlobalSettingsProvider.notifier).save(newGlobal);
    }
  }

  void _reindexAll() async {
    if (_book == null) return;
    final config = ref.read(embeddingConfigProvider);
    if (config.endpoint.isEmpty) {
      if (mounted) GlazeToast.show(context, 'Set up embedding API in Embedding Settings first');
      return;
    }

    setState(() { _isReindexing = true; });
    try {
      final service = ref.read(memoryEmbeddingServiceProvider);
      final result = await service.reindexAll(
        _book!,
        charId: widget.charId,
        sessionId: widget.sessionId,
        config: config,
        embeddingTarget: _gs.vectorSearchEnabled ? 'content' : 'content',
      );
      if (mounted) {
        setState(() { _isReindexing = false; });
        GlazeToast.show(context, 'Indexed: ${result.indexed}, Skipped: ${result.skipped}, Failed: ${result.failed}');
      }
    } catch (e) {
      if (mounted) {
        setState(() { _isReindexing = false; });
        GlazeToast.error(context, 'Reindex failed: ', e);
      }
    }
  }

  void _deleteAllMemoryIndexes() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Memory Indexes'),
        content: const Text('Remove all stored memory embeddings? You will need to re-index after.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete All')),
        ],
      ),
    );
    if (confirmed != true) return;

    await ref.read(memoryEmbeddingServiceProvider).deleteAllMemoryIndexes();
    if (mounted) GlazeToast.show(context, 'All memory indexes deleted');
  }

  void _editEntry(MemoryEntry entry) async {
    final result = await GlazeBottomSheet.show<MemoryEntry>(
      context,
      title: entry.title.isNotEmpty ? entry.title : 'Edit Memory',
      child: MemoryEntryEditorSheet(entry: entry),
    );
    if (result != null && mounted) {
      final entries = [..._book!.entries];
      final idx = entries.indexWhere((e) => e.id == entry.id);
      if (idx >= 0) entries[idx] = result;
      setState(() { _book = _book!.copyWith(entries: entries); });
      await _save();
    }
  }

  void _addEntry() async {
    final entry = MemoryEntry(
      id: 'mem_${DateTime.now().millisecondsSinceEpoch}',
      status: 'active',
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    final result = await GlazeBottomSheet.show<MemoryEntry>(
      context,
      title: 'New Memory',
      child: MemoryEntryEditorSheet(entry: entry),
    );
    if (result != null && mounted) {
      setState(() {
        _book = _book!.copyWith(entries: [..._book!.entries, result]);
      });
      await _save();
    }
  }

  void _editDraft(MemoryDraft draft) async {
    final entry = MemoryEntry(
      id: draft.id,
      title: draft.title,
      content: draft.content,
      keys: draft.keys,
      messageIds: draft.messageIds,
      status: 'active',
      createdAt: draft.createdAt,
    );
    final result = await GlazeBottomSheet.show<MemoryEntry>(
      context,
      title: 'Edit Draft',
      child: MemoryEntryEditorSheet(entry: entry),
    );
    if (result != null && mounted) {
      final drafts = [..._book!.pendingDrafts];
      final idx = drafts.indexWhere((d) => d.id == draft.id);
      if (idx >= 0) {
        drafts[idx] = drafts[idx].copyWith(
          title: result.title,
          content: result.content,
          keys: result.keys,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        );
      }
      setState(() { _book = _book!.copyWith(pendingDrafts: drafts); });
      await _save();
    }
  }

  void _cycleSearchType() async {
    final s = _gs;
    String nextMode;
    bool nextVector;
    if (!s.vectorSearchEnabled) {
      nextVector = true;
      nextMode = 'glaze';
    } else if (s.keyMatchMode == 'glaze') {
      nextVector = true;
      nextMode = 'both';
    } else if (s.keyMatchMode == 'both') {
      nextVector = false;
      nextMode = 'plain';
    } else {
      nextVector = false;
      nextMode = 'plain';
    }
    await ref.read(memoryGlobalSettingsProvider.notifier).save(
      s.copyWith(vectorSearchEnabled: nextVector, keyMatchMode: nextMode),
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final settings = _gs;
    final entries = _book!.entries;
    final pendingDrafts = _book!.pendingDrafts;
    final activeCount = entries.where((e) => e.status == 'active').length;
    final needsRebuildCount = entries.where((e) => e.status == 'needs_rebuild').length;
    final draftsNeedingGen = pendingDrafts.where((d) =>
        d.content.isEmpty &&
        (d.status == 'pending_generation' || d.status == 'needs_regeneration') &&
        _generatingDrafts[d.id] != true).toList();
    final isGenerating = _generatingDrafts.values.any((v) => v);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildOverview(settings),
          const SizedBox(height: 12),
          _buildSearchTypeSelector(settings),
          const SizedBox(height: 12),
          _buildStatusSummary(activeCount, needsRebuildCount, pendingDrafts.length),
          const SizedBox(height: 12),
          _buildActionButtons(),
          if (draftsNeedingGen.isNotEmpty || isGenerating) ...[
            const SizedBox(height: 12),
            _buildBatchActions(draftsNeedingGen, isGenerating),
          ],
          const SizedBox(height: 16),
          if (pendingDrafts.isNotEmpty) ...[
            _buildPendingDraftsSection(pendingDrafts),
            const SizedBox(height: 16),
          ],
          _buildApprovedSection(entries),
        ],
      ),
    );
  }

  Widget _buildOverview(MemoryGlobalSettings settings) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Memory Books', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: context.colors.textPrimary)),
                    const SizedBox(height: 2),
                    Text('Session ${widget.sessionId.substring(0, 8)}...', style: TextStyle(fontSize: 12, color: context.colors.textSecondary)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: context.colors.accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(_searchModelLabel, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: context.colors.accent)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(_settingsSummary, style: TextStyle(fontSize: 12, color: context.colors.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildSearchTypeSelector(MemoryGlobalSettings settings) {
    return GestureDetector(
      onTap: _cycleSearchType,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Search type', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: context.colors.textPrimary)),
            Row(
              children: [
                Text(_searchTypeLabel, style: TextStyle(fontSize: 13, color: context.colors.textSecondary)),
                const SizedBox(width: 4),
                Icon(Icons.arrow_drop_down, size: 20, color: context.colors.textSecondary),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusSummary(int active, int needsRebuild, int drafts) {
    return Row(
      children: [
        Expanded(child: _statusCard('$active', 'Active', Colors.green)),
        const SizedBox(width: 8),
        Expanded(child: _statusCard('$needsRebuild', 'Rebuild', Colors.orange)),
        const SizedBox(width: 8),
        Expanded(child: _statusCard('$drafts', 'Drafts', Colors.amber)),
      ],
    );
  }

  Widget _statusCard(String value, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: context.colors.textPrimary)),
          Text(label, style: TextStyle(fontSize: 11, color: context.colors.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _openSettings,
                icon: Icon(Icons.settings, size: 16, color: context.colors.textSecondary),
                label: Text('Settings', style: TextStyle(color: context.colors.textPrimary)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _scanChat,
                icon: Icon(Icons.search, size: 16, color: context.colors.textSecondary),
                label: Text('Scan Chat', style: TextStyle(color: context.colors.textPrimary)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                onPressed: _addEntry,
                icon: Icon(Icons.add, size: 16),
                label: Text('Add'),
                style: FilledButton.styleFrom(
                  backgroundColor: context.colors.accent,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isReindexing ? null : _reindexAll,
                icon: Icon(Icons.storage, size: 16, color: context.colors.textSecondary),
                label: Text(_isReindexing ? 'Indexing...' : 'Reindex All', style: TextStyle(color: context.colors.textPrimary)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isReindexing ? null : _deleteAllMemoryIndexes,
                icon: Icon(Icons.delete_sweep, size: 16, color: Colors.redAccent.withValues(alpha: 0.7)),
                label: Text('Clear Indexes', style: TextStyle(color: context.colors.textSecondary)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.2)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBatchActions(List<MemoryDraft> needsGen, bool isGenerating) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.colors.accent.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isGenerating
                ? 'Generating drafts...'
                : '${needsGen.length} draft${needsGen.length > 1 ? 's' : ''} need generation',
            style: TextStyle(fontSize: 14, color: context.colors.textSecondary),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: needsGen.isNotEmpty ? _batchGenerate : null,
            style: FilledButton.styleFrom(
              backgroundColor: context.colors.accent,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(isGenerating ? 'Generate Remaining' : 'Generate Batch'),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingDraftsSection(List<MemoryDraft> drafts) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Pending Drafts', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: context.colors.textPrimary)),
            const Spacer(),
            if (drafts.length > 1)
              TextButton(
                onPressed: _deleteAllDrafts,
                style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
                child: Text('Delete All', style: TextStyle(fontSize: 12)),
              ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text('${drafts.length}', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: context.colors.textSecondary)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...drafts.map((draft) => _buildDraftCard(draft)),
      ],
    );
  }

  Widget _buildDraftCard(MemoryDraft draft) {
    final isGen = _generatingDrafts[draft.id] == true;
    final needsGen = draft.content.isEmpty && (draft.status == 'pending_generation' || draft.status == 'needs_regeneration');
    final needsRegen = draft.status == 'needs_regeneration';
    final hasContent = draft.content.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isGen
            ? Colors.amber.withValues(alpha: 0.05)
            : Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: isGen
            ? Border.all(color: Colors.amber.withValues(alpha: 0.4))
            : needsRegen
                ? Border.all(color: Colors.redAccent.withValues(alpha: 0.3))
                : Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      draft.title.isNotEmpty ? draft.title : 'Untitled Draft',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: context.colors.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _draftStatusLabel(draft, isGen),
                      style: TextStyle(fontSize: 12, color: _draftStatusColor(draft, isGen)),
                    ),
                  ],
                ),
              ),
              _draftStatusBadge(draft, isGen),
            ],
          ),
          if (draft.content.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              draft.content.length > 180 ? '${draft.content.substring(0, 180)}...' : draft.content,
              style: TextStyle(fontSize: 13, color: context.colors.textSecondary),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (draft.error != null && needsRegen) ...[
            const SizedBox(height: 4),
            Text(draft.error!, style: TextStyle(fontSize: 11, color: Colors.redAccent), maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (isGen)
                _actionBtn('Stop', Colors.amber, () => _cancelDraftGeneration(draft.id))
              else if (needsGen || needsRegen)
                _actionBtn('Generate', Colors.amber, () => _generateDraft(draft.id))
              else if (hasContent)
                _actionBtn('Approve', Colors.green, () => _approveDraft(draft.id)),
              const SizedBox(width: 6),
              if (hasContent && !isGen)
                _actionBtn('Edit', context.colors.accent, () => _editDraft(draft)),
              const SizedBox(width: 6),
              _actionBtn('Delete', Colors.redAccent, () => _deleteDraft(draft.id)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionBtn(String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
      ),
    );
  }

  String _draftStatusLabel(MemoryDraft draft, bool isGen) {
    if (isGen) return 'Generating...';
    if (draft.status == 'needs_regeneration') return 'Needs regeneration';
    if (draft.content.isEmpty && draft.status == 'pending_generation') return 'Needs generation';
    if (draft.content.isNotEmpty) return 'Pending approval';
    return draft.status;
  }

  Color _draftStatusColor(MemoryDraft draft, bool isGen) {
    if (isGen) return Colors.amber;
    if (draft.status == 'needs_regeneration') return Colors.redAccent;
    if (draft.content.isEmpty) return Colors.amber;
    return context.colors.textSecondary;
  }

  Widget _draftStatusBadge(MemoryDraft draft, bool isGen) {
    final (String label, Color color) = isGen
        ? ('GEN', Colors.amber)
        : draft.status == 'needs_regeneration'
            ? ('REGEN', Colors.redAccent)
            : draft.content.isEmpty && draft.status == 'pending_generation'
                ? ('TODO', Colors.amber)
                : ('DRAFT', Colors.cyan);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
    );
  }

  Widget _buildApprovedSection(List<MemoryEntry> entries) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Approved Memories', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: context.colors.textPrimary)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text('${entries.length}', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: context.colors.textSecondary)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (entries.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text('No approved memories yet', style: TextStyle(fontSize: 13, color: context.colors.textSecondary)),
            ),
          )
        else
          ...entries.map((entry) => _buildEntryCard(entry)),
      ],
    );
  }

  Widget _buildEntryCard(MemoryEntry entry) {
    final isActive = entry.status == 'active';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isActive ? Colors.white.withValues(alpha: 0.05) : Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(12),
        border: entry.status == 'needs_rebuild'
            ? Border.all(color: Colors.orange.withValues(alpha: 0.3))
            : Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.title.isNotEmpty ? entry.title : 'Untitled Memory',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: isActive ? context.colors.textPrimary : context.colors.textSecondary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${entry.status == "needs_rebuild" ? "Needs rebuild" : "Active"} • ${entry.messageIds.length} msgs • ${entry.keys.take(3).join(", ")}',
                      style: TextStyle(fontSize: 12, color: context.colors.textSecondary),
                    ),
                  ],
                ),
              ),
              _entryStatusBadge(entry),
            ],
          ),
          if (entry.content.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              entry.content.length > 180 ? '${entry.content.substring(0, 180)}...' : entry.content,
              style: TextStyle(fontSize: 13, color: context.colors.textSecondary),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _actionBtn('Edit', context.colors.accent, () => _editEntry(entry)),
              const SizedBox(width: 6),
              _actionBtn('Delete', Colors.redAccent, () => _deleteEntry(entry.id)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _entryStatusBadge(MemoryEntry entry) {
    final isActive = entry.status == 'active';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: (isActive ? Colors.green : Colors.orange).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        isActive ? 'ACTIVE' : 'REBUILD',
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: isActive ? Colors.green : Colors.orange),
      ),
    );
  }
}
