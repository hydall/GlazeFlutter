import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/memory_book.dart';
import '../../../core/state/memory_settings_provider.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/widgets/glaze_bottom_sheet.dart';
import '../../../shared/widgets/glaze_toast.dart';
import '../../memory/controllers/memory_book_controller.dart';
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
  late final MemoryBookController _ctrl;
  Timer? _elapsedTimer;

  @override
  void initState() {
    super.initState();
    _ctrl = MemoryBookController(ref, widget.sessionId, widget.charId);
    _load();
  }

  Future<void> _load() async {
    await _ctrl.load();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _elapsedTimer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _startElapsedTimer() {
    _elapsedTimer ??= Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (_ctrl.generatingDrafts.isNotEmpty && mounted) setState(() {});
    });
  }

  void _stopElapsedTimer() {
    if (_ctrl.generatingDrafts.isEmpty) {
      _elapsedTimer?.cancel();
      _elapsedTimer = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_ctrl.loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final settings = _ctrl.globalSettings;
    final book = _ctrl.book!;
    final entries = book.entries;
    final pendingDrafts = book.pendingDrafts;
    final activeCount = _ctrl.book!.entries.where((e) => e.status == 'active').length;
    final needsRebuildCount = _ctrl.book!.entries.where((e) => e.status == 'needs_rebuild').length;
    final draftsNeedingGen = _ctrl.draftsNeedingGeneration;
    final isGenerating = _ctrl.isGenerating;

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

  // ─── Overview ────────────────────────────────────────────────────

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
                    Text('Memory Books', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: context.cs.onSurface)),
                    const SizedBox(height: 2),
                    Text('Session ${widget.sessionId.substring(0, 8)}...', style: TextStyle(fontSize: 12, color: context.cs.onSurfaceVariant)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: context.cs.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(_ctrl.searchModelLabel, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: context.cs.primary)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(_ctrl.settingsSummary, style: TextStyle(fontSize: 12, color: context.cs.onSurfaceVariant)),
        ],
      ),
    );
  }

  // ─── Search type ─────────────────────────────────────────────────

  Widget _buildSearchTypeSelector(MemoryGlobalSettings settings) {
    return GestureDetector(
      onTap: () async {
        await _ctrl.cycleSearchType();
        if (mounted) setState(() {});
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Search type', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: context.cs.onSurface)),
            Row(
              children: [
                Text(_ctrl.searchTypeLabel, style: TextStyle(fontSize: 13, color: context.cs.onSurfaceVariant)),
                const SizedBox(width: 4),
                Icon(Icons.arrow_drop_down, size: 20, color: context.cs.onSurfaceVariant),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ─── Status summary ──────────────────────────────────────────────

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
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: context.cs.onSurface)),
          Text(label, style: TextStyle(fontSize: 11, color: context.cs.onSurfaceVariant)),
        ],
      ),
    );
  }

  // ─── Action buttons ──────────────────────────────────────────────

  Widget _buildActionButtons() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _openSettings,
                icon: Icon(Icons.settings, size: 16, color: context.cs.onSurfaceVariant),
                label: Text('Settings', style: TextStyle(color: context.cs.onSurface)),
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
                icon: Icon(Icons.search, size: 16, color: context.cs.onSurfaceVariant),
                label: Text('Scan Chat', style: TextStyle(color: context.cs.onSurface)),
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
                  backgroundColor: context.cs.primary,
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
                onPressed: _ctrl.isReindexing ? null : _reindexAll,
                icon: Icon(Icons.storage, size: 16, color: context.cs.onSurfaceVariant),
                label: Text(_ctrl.isReindexing ? 'Indexing...' : 'Reindex All', style: TextStyle(color: context.cs.onSurface)),
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
                onPressed: _ctrl.isReindexing ? null : _deleteAllMemoryIndexes,
                icon: Icon(Icons.delete_sweep, size: 16, color: Colors.redAccent.withValues(alpha: 0.7)),
                label: Text('Clear Indexes', style: TextStyle(color: context.cs.onSurfaceVariant)),
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
        border: Border.all(color: context.cs.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isGenerating
                ? 'Generating drafts...'
                : '${needsGen.length} draft${needsGen.length > 1 ? 's' : ''} need generation',
            style: TextStyle(fontSize: 14, color: context.cs.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: needsGen.isNotEmpty ? _batchGenerate : null,
            style: FilledButton.styleFrom(
              backgroundColor: context.cs.primary,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(isGenerating ? 'Generate Remaining' : 'Generate Batch'),
          ),
        ],
      ),
    );
  }

  // ─── Pending Drafts section ──────────────────────────────────────

  Widget _buildPendingDraftsSection(List<MemoryDraft> drafts) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Pending Drafts', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: context.cs.onSurface)),
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
              child: Text('${drafts.length}', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: context.cs.onSurfaceVariant)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...drafts.map((draft) => _buildDraftCard(draft)),
      ],
    );
  }

  Widget _buildDraftCard(MemoryDraft draft) {
    final isGen = _ctrl.generatingDrafts[draft.id] == true;
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
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: context.cs.onSurface),
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
              style: TextStyle(fontSize: 13, color: context.cs.onSurfaceVariant),
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
                _actionBtn('Stop', Colors.amber, () => _cancelDraft(draft.id))
              else if (needsGen || needsRegen)
                _actionBtn('Generate', Colors.amber, () => _generateDraft(draft.id))
              else if (hasContent)
                _actionBtn('Approve', Colors.green, () => _approveDraft(draft.id)),
              const SizedBox(width: 6),
              if (hasContent && !isGen)
                _actionBtn('Edit', context.cs.primary, () => _editDraft(draft)),
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
    if (isGen) {
      final start = _ctrl.genStartTimes[draft.id];
      if (start != null) {
        final elapsed = DateTime.now().difference(start).inMilliseconds / 1000.0;
        return 'Generating... ${elapsed.toStringAsFixed(1)}s';
      }
      return 'Generating...';
    }
    if (draft.status == 'needs_regeneration') return 'Needs regeneration';
    if (draft.content.isEmpty && draft.status == 'pending_generation') return 'Needs generation';
    if (draft.content.isNotEmpty) return 'Pending approval';
    return draft.status;
  }

  Color _draftStatusColor(MemoryDraft draft, bool isGen) {
    if (isGen) return Colors.amber;
    if (draft.status == 'needs_regeneration') return Colors.redAccent;
    if (draft.content.isEmpty) return Colors.amber;
    return context.cs.onSurfaceVariant;
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

  // ─── Approved section ────────────────────────────────────────────

  Widget _buildApprovedSection(List<MemoryEntry> entries) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Approved Memories', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: context.cs.onSurface)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text('${entries.length}', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: context.cs.onSurfaceVariant)),
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
              child: Text('No approved memories yet', style: TextStyle(fontSize: 13, color: context.cs.onSurfaceVariant)),
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
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: isActive ? context.cs.onSurface : context.cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${entry.status == "needs_rebuild" ? "Needs rebuild" : "Active"} • ${entry.messageIds.length} msgs • ${entry.keys.take(3).join(", ")}',
                      style: TextStyle(fontSize: 12, color: context.cs.onSurfaceVariant),
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
              style: TextStyle(fontSize: 13, color: context.cs.onSurfaceVariant),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _actionBtn('Edit', context.cs.primary, () => _editEntry(entry)),
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

  // ─── Actions delegating to controller ────────────────────────────

  void _scanChat() async {
    final msg = await _ctrl.scanChat();
    if (msg != null && mounted) {
      setState(() {});
      GlazeToast.show(context, msg);
    }
  }

  void _generateDraft(String draftId) {
    _ctrl.generateDraft(
      draftId,
      onStart: () {
        if (mounted) {
          setState(() {});
          _startElapsedTimer();
        }
      },
      onComplete: () {
        if (mounted) {
          setState(() {});
          _stopElapsedTimer();
        }
      },
      onError: (error) {
        if (mounted) {
          setState(() {});
          _stopElapsedTimer();
          GlazeToast.show(context, 'Generation failed: $error');
        }
      },
    );
  }

  void _cancelDraft(String draftId) {
    _ctrl.cancelDraftGeneration(draftId);
    if (mounted) setState(() {});
  }

  void _batchGenerate() {
    _ctrl.batchGenerate(
      onStart: () {
        if (mounted) {
          setState(() {});
          _startElapsedTimer();
        }
      },
      onComplete: () {
        if (mounted) {
          setState(() {});
          _stopElapsedTimer();
        }
      },
      onError: (error) {
        if (mounted) {
          setState(() {});
          _stopElapsedTimer();
          GlazeToast.show(context, 'Generation failed: $error');
        }
      },
    );
  }

  void _approveDraft(String draftId) async {
    await _ctrl.approveDraft(draftId);
    if (mounted) setState(() {});
  }

  void _deleteDraft(String draftId) async {
    await _ctrl.deleteDraft(draftId);
    if (mounted) setState(() {});
  }

  void _deleteAllDrafts() async {
    await _ctrl.deleteAllDrafts();
    if (mounted) setState(() {});
  }

  void _deleteEntry(String entryId) async {
    await _ctrl.deleteEntry(entryId);
    if (mounted) setState(() {});
  }

  void _openSettings() async {
    final currentSettings = _ctrl.globalSettingsAsBookSettings();
    final newResult = await GlazeBottomSheet.show<MemorySettingsSheetResult>(
      context,
      title: 'Memory Settings',
      child: MemoryGenerationSettingsSheet(settings: currentSettings),
    );
    if (newResult != null && mounted) {
      await _ctrl.updateSettings(newResult.settings, newResult.vectorThreshold);
      if (mounted) setState(() {});
    }
  }

  void _reindexAll() async {
    setState(() {});
    final msg = await _ctrl.reindexAll();
    if (mounted) {
      setState(() {});
      if (msg != null) {
        if (msg.startsWith('Reindex failed') || msg.startsWith('Set up')) {
          GlazeToast.error(context, '', msg);
        } else {
          GlazeToast.show(context, msg);
        }
      }
    }
  }

  void _deleteAllMemoryIndexes() async {
    final confirmed = await GlazeBottomSheet.show<bool>(
      context,
      title: 'Delete All Indexes',
      bigInfo: const BottomSheetBigInfo(
        icon: Icons.delete_outline,
        description: 'Remove all stored memory embeddings? You will need to re-index after.',
      ),
      items: [
        BottomSheetItem(
          label: 'Delete All',
          isDestructive: true,
          centered: true,
          onTap: () => Navigator.of(context, rootNavigator: true).pop(true),
        ),
        BottomSheetItem(
          label: 'Cancel',
          centered: true,
          onTap: () => Navigator.of(context, rootNavigator: true).pop(false),
        ),
      ],
    );
    if (confirmed != true) return;
    await _ctrl.deleteAllMemoryIndexes();
    if (mounted) GlazeToast.show(context, 'All memory indexes deleted');
  }

  void _editEntry(MemoryEntry entry) async {
    final result = await GlazeBottomSheet.show<MemoryEntry>(
      context,
      title: entry.title.isNotEmpty ? entry.title : 'Edit Memory',
      child: MemoryEntryEditorSheet(entry: entry),
    );
    if (result != null && mounted) {
      await _ctrl.editEntry(entry, result);
      if (mounted) setState(() {});
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
      await _ctrl.addEntry(result);
      if (mounted) setState(() {});
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
      await _ctrl.editDraft(draft, result);
      if (mounted) setState(() {});
    }
  }
}
