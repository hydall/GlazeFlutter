import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/llm/memory_injection_service.dart';
import '../../../core/llm/summary_service.dart';
import '../../../core/models/chat_message.dart';
import '../../../core/state/lorebook_provider.dart';
import '../../../features/chat/chat_provider.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/widgets/glaze_bottom_sheet.dart';

void showContextInfoSheet(BuildContext context, WidgetRef ref, String charId) {
  GlazeBottomSheet.show(context, child: _ContextInfoPanel(charId: charId));
}

class _ContextInfoPanel extends ConsumerStatefulWidget {
  final String charId;
  const _ContextInfoPanel({required this.charId});

  @override
  ConsumerState<_ContextInfoPanel> createState() => _ContextInfoPanelState();
}

class _ContextInfoPanelState extends ConsumerState<_ContextInfoPanel> {
  List<_SourceItem> _sources = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final chatState = ref.read(chatProvider(widget.charId)).value;
    if (chatState?.session == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final session = chatState!.session!;
    final sources = <_SourceItem>[];

    final summaryService = ref.read(summaryServiceProvider);
    final summary = await summaryService.getSummary(session.id);
    sources.add(_SourceItem(
      icon: Icons.summarize,
      label: 'Summary',
      active: summary != null && summary.isNotEmpty,
      detail: summary != null && summary.isNotEmpty ? '${summary.length} chars' : 'Not generated',
      color: summary != null && summary.isNotEmpty ? Colors.green : context.cs.onSurfaceVariant,
    ));

    final memoryService = ref.read(memoryInjectionServiceProvider);
    final historyText = session.historyText;
    final memoryResult = await memoryService.buildInjection(
      sessionId: session.id,
      historyText: historyText,
      messageCount: session.messages.length,
    );
    sources.add(_SourceItem(
      icon: Icons.auto_stories,
      label: 'Memory Book',
      active: memoryResult.entries.isNotEmpty,
      detail: memoryResult.entries.isNotEmpty
          ? '${memoryResult.entries.length} entries injected (${memoryResult.injectionTarget})'
          : 'No active entries matched',
      color: memoryResult.entries.isNotEmpty ? Colors.orange : context.cs.onSurfaceVariant,
    ));

    final lorebooks = ref.read(lorebooksProvider).value ?? [];
    final settings = ref.read(lorebookSettingsProvider);
    final activeLorebooks = lorebooks.where((lb) {
      if (!lb.enabled) return false;
      if (lb.activationScope == 'global') return true;
      if (lb.activationScope == 'character' && lb.activationTargetId == widget.charId) return true;
      if (lb.activationScope == 'chat' && lb.activationTargetId == widget.charId) return true;
      return false;
    }).toList();

    final nonHiddenMessages = session.messages.where((m) => !m.isHidden && !m.isTyping).toList();
    final scanDepth = settings.scanDepth;
    final scanMessages = nonHiddenMessages.length > scanDepth
        ? nonHiddenMessages.sublist(nonHiddenMessages.length - scanDepth)
        : nonHiddenMessages;
    final scanText = scanMessages.map((m) => m.content).join('\n').toLowerCase();

    var triggeredCountRaw = 0;
    for (final lb in activeLorebooks) {
      for (final entry in lb.entries) {
        if (!entry.enabled) continue;
        if (entry.constant) {
          triggeredCountRaw++;
          continue;
        }
        for (final key in entry.keys) {
          if (key.isEmpty) continue;
          if (scanText.contains(key.toLowerCase())) {
            triggeredCountRaw++;
            break;
          }
        }
      }
    }
    final triggeredCount = triggeredCountRaw.clamp(0, settings.maxInjectedEntries);

    sources.add(_SourceItem(
      icon: Icons.menu_book,
      label: 'Lorebooks',
      active: activeLorebooks.isNotEmpty,
      detail: '${activeLorebooks.length} active book${activeLorebooks.length != 1 ? 's' : ''}, $triggeredCount entr${triggeredCount != 1 ? 'ies' : 'y'} triggered',
      color: activeLorebooks.isNotEmpty ? Colors.cyan : context.cs.onSurfaceVariant,
    ));

    sources.add(_SourceItem(
      icon: Icons.chat_bubble_outline,
      label: 'Chat History',
      active: true,
      detail: '${nonHiddenMessages.length} visible message${nonHiddenMessages.length != 1 ? 's' : ''}${session.messages.where((m) => m.isHidden).isNotEmpty ? ', ${session.messages.where((m) => m.isHidden).length} hidden' : ''}',
      color: context.cs.primary,
    ));

    if (mounted) setState(() { _sources = sources; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(chatProvider(widget.charId), (prev, next) {
      final prevSession = prev?.value?.session;
      final nextSession = next.value?.session;
      if (prevSession != nextSession) _load();
    });
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
          child: Row(
            children: [
              Icon(Icons.info_outline, color: context.cs.primary, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Context Sources', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: context.cs.onSurface)),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: Colors.white10),
        if (_loading)
          const Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator())
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.all(12),
            itemCount: _sources.length,
            itemBuilder: (_, i) => _SourceTile(source: _sources[i]),
          ),
      ],
    );
  }
}

class _SourceItem {
  final IconData icon;
  final String label;
  final bool active;
  final String detail;
  final Color color;
  const _SourceItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.detail,
    required this.color,
  });
}

class _SourceTile extends StatelessWidget {
  final _SourceItem source;
  const _SourceTile({required this.source});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: source.active ? Colors.white.withValues(alpha: 0.05) : Colors.white.withValues(alpha: 0.02),
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: source.color.withValues(alpha: source.active ? 0.3 : 0.05)),
      ),
      child: ListTile(
        leading: Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: source.color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(source.icon, color: source.color, size: 18),
        ),
        title: Text(
          source.label,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: source.active ? context.cs.onSurface : context.cs.onSurfaceVariant),
        ),
        subtitle: Text(
          source.detail,
          style: TextStyle(fontSize: 12, color: context.cs.onSurfaceVariant),
        ),
        trailing: source.active
            ? Icon(Icons.check_circle, size: 18, color: source.color)
            : Icon(Icons.radio_button_unchecked, size: 18, color: context.cs.onSurfaceVariant),
      ),
    );
  }
}
