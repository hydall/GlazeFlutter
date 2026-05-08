import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/llm/lorebook_coverage.dart';
import '../../../core/llm/tokenizer.dart';
import '../../../core/state/db_provider.dart';
import '../../../core/state/lorebook_provider.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/widgets/glaze_bottom_sheet.dart';
import '../../../shared/widgets/glaze_filter_chip_bar.dart';
import '../../../shared/widgets/sheet_view.dart';
import '../chat_provider.dart';

void showLorebookCoverageSheet(
  BuildContext context,
  WidgetRef ref,
  String charId,
) {
  GlazeBottomSheet.show(
    context,
    child: _CoveragePanel(charId: charId),
  );
}

class _CoveragePanel extends ConsumerStatefulWidget {
  final String charId;
  const _CoveragePanel({required this.charId});

  @override
  ConsumerState<_CoveragePanel> createState() => _CoveragePanelState();
}

class _CoveragePanelState extends ConsumerState<_CoveragePanel> {
  CoverageResult? _result;
  bool _loading = true;
  _FilterMode _filter = _FilterMode.activated;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final chatState = ref.read(chatProvider(widget.charId)).value;
    final session = chatState?.session;
    if (session == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    final charRepo = ref.read(characterRepoProvider);
    final character = await charRepo.getById(widget.charId);

    final lorebooks = await ref.read(lorebookRepoProvider).getAll();
    final settings = ref.read(lorebookSettingsProvider);
    final activations = ref.read(lorebookActivationsProvider);

    final nonHidden = session.messages.where((m) => !m.isHidden).toList();
    String lastUserMsg = '';
    for (final m in nonHidden.reversed) {
      if (m.role == 'user') {
        lastUserMsg = m.content;
        break;
      }
    }

    final result = computeLorebookCoverage(
      history: session.messages,
      char: character,
      textToScan: lastUserMsg,
      chatId: session.id,
      lorebooks: lorebooks,
      globalSettings: settings,
      activations: activations,
    );

    if (mounted)
      setState(() {
        _result = result;
        _loading = false;
      });
  }

  @override
  Widget build(BuildContext context) {
    return SheetView(
      title: 'Lorebook Coverage',
      actions: [
        SheetViewAction(
          icon: const Icon(Icons.refresh, size: 20),
          onPressed: _load,
          tooltip: 'Refresh',
        ),
      ],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _result == null
          ? const Center(
              child: Text(
                'No data',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            )
          : Column(
              children: [
                Builder(
                  builder: (context) =>
                      SizedBox(height: MediaQuery.paddingOf(context).top),
                ),
                _SummaryBar(result: _result!),
                GlazeFilterChipBar<_FilterMode>(
                  current: _filter,
                  options: _FilterMode.values.toList(),
                  labelBuilder: _labelForFilter,
                  onSelected: (f) => setState(() => _filter = f),
                ),
                Expanded(
                  child: _EntryList(
                    entries: _filteredEntries,
                    result: _result!,
                  ),
                ),
              ],
            ),
    );
  }

  List<CoverageEntry> get _filteredEntries {
    final entries = _result?.entries ?? [];
    return switch (_filter) {
      _FilterMode.activated =>
        entries.where((e) => e.activated && !e.cutOffByBudget).toList(),
      _FilterMode.cutOff => entries.where((e) => e.cutOffByBudget).toList(),
      _FilterMode.notTriggered => entries.where((e) => !e.activated).toList(),
      _FilterMode.all => entries,
    };
  }
}

class _SummaryBar extends StatelessWidget {
  final CoverageResult result;
  const _SummaryBar({required this.result});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          _StatChip(
            label: 'Active',
            value: '${result.activatedCount - result.cutOffCount}',
            color: Colors.green,
          ),
          const SizedBox(width: 8),
          if (result.cutOffCount > 0) ...[
            _StatChip(
              label: 'Cut off',
              value: '${result.cutOffCount}',
              color: Colors.orange,
            ),
            const SizedBox(width: 8),
          ],
          _StatChip(
            label: 'Inactive',
            value: '${result.totalCandidates - result.activatedCount}',
            color: AppColors.textSecondary,
          ),
          const SizedBox(width: 8),
          _StatChip(
            label: 'Total',
            value: '${result.totalCandidates}',
            color: Colors.cyan,
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: color.withValues(alpha: 0.8)),
          ),
        ],
      ),
    );
  }
}

enum _FilterMode { activated, cutOff, notTriggered, all }

String _labelForFilter(_FilterMode m) => switch (m) {
  _FilterMode.activated => 'Activated',
  _FilterMode.cutOff => 'Cut Off',
  _FilterMode.notTriggered => 'Not Triggered',
  _FilterMode.all => 'All',
};

class _EntryList extends StatelessWidget {
  final List<CoverageEntry> entries;
  final CoverageResult result;
  const _EntryList({required this.entries, required this.result});

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'No entries in this category',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
      itemCount: entries.length,
      itemBuilder: (_, i) => _CoverageTile(entry: entries[i]),
    );
  }
}

class _CoverageTile extends StatefulWidget {
  final CoverageEntry entry;
  const _CoverageTile({required this.entry});

  @override
  State<_CoverageTile> createState() => _CoverageTileState();
}

class _CoverageTileState extends State<_CoverageTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    final statusColor = e.cutOffByBudget
        ? Colors.orange
        : e.activated
        ? Colors.green
        : AppColors.textSecondary;

    final tokenCount = estimateTokens(e.content);

    return Card(
      color: Colors.white.withValues(alpha: e.activated ? 0.05 : 0.02),
      margin: const EdgeInsets.symmetric(vertical: 3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: statusColor.withValues(alpha: e.activated ? 0.25 : 0.06),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => setState(() => _expanded = !_expanded),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    e.activated
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    size: 16,
                    color: statusColor,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      e.comment.isNotEmpty ? e.comment : e.id,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: e.activated
                            ? AppColors.textPrimary
                            : AppColors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  _PositionBadge(position: e.position),
                  const SizedBox(width: 4),
                  Text(
                    '$tokenCount t',
                    style: TextStyle(
                      fontSize: 10,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Text(
                    e.lorebookName,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.cyan.withValues(alpha: 0.8),
                    ),
                  ),
                  if (e.constant) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.purple.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'CONST',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: Colors.purple,
                        ),
                      ),
                    ),
                  ],
                  if (e.cutOffByBudget) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'BUDGET',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: Colors.orange,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              if (e.matchedKeys.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 4,
                  runSpacing: 3,
                  children: e.matchedKeys
                      .map(
                        (k) => Chip(
                          label: Text(
                            k,
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.green,
                            ),
                          ),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          padding: EdgeInsets.zero,
                          labelPadding: const EdgeInsets.symmetric(
                            horizontal: 6,
                          ),
                          backgroundColor: Colors.green.withValues(alpha: 0.1),
                          side: BorderSide(
                            color: Colors.green.withValues(alpha: 0.25),
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                      )
                      .toList(),
                ),
              ],
              if (e.matchedSecondaryKeys.isNotEmpty) ...[
                const SizedBox(height: 4),
                Wrap(
                  spacing: 4,
                  runSpacing: 3,
                  children: e.matchedSecondaryKeys
                      .map(
                        (k) => Chip(
                          label: Text(
                            k,
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.teal,
                            ),
                          ),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          padding: EdgeInsets.zero,
                          labelPadding: const EdgeInsets.symmetric(
                            horizontal: 6,
                          ),
                          backgroundColor: Colors.teal.withValues(alpha: 0.1),
                          side: BorderSide(
                            color: Colors.teal.withValues(alpha: 0.25),
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                      )
                      .toList(),
                ),
              ],
              if (e.matchMessageIndex != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Matched in message #${e.matchMessageIndex! + 1}',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.blue.withValues(alpha: 0.7),
                  ),
                ),
              ],
              if (_expanded) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  constraints: const BoxConstraints(maxHeight: 160),
                  child: SingleChildScrollView(
                    child: Text(
                      e.content,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PositionBadge extends StatelessWidget {
  final String position;
  const _PositionBadge({required this.position});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (position) {
      'worldInfoBefore' => ('Before', Colors.cyan),
      'worldInfoAfter' => ('After', Colors.teal),
      'lorebooksMacro' => ('Macro', Colors.purple),
      _ => (position, AppColors.textSecondary),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
