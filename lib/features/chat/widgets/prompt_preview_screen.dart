import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/llm/history_assembler.dart';
import '../../../core/llm/prompt_builder.dart';
import '../../../core/llm/prompt_isolate.dart';
import '../../../core/llm/prompt_payload_builder.dart';
import '../../../core/llm/tokenizer.dart';
import '../../../core/models/api_config.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/widgets/glaze_bottom_sheet.dart';
import '../../../shared/widgets/glaze_filter_chip_bar.dart';
import '../../../shared/widgets/glaze_toast.dart';
import '../../../shared/widgets/sheet_view.dart';
import '../chat_provider.dart';

class PromptPreviewScreen extends ConsumerStatefulWidget {
  final String charId;
  const PromptPreviewScreen({super.key, required this.charId});

  @override
  ConsumerState<PromptPreviewScreen> createState() =>
      _PromptPreviewScreenState();
}

class _PromptPreviewScreenState extends ConsumerState<PromptPreviewScreen> {
  PromptResult? _result;
  ApiConfig? _apiConfig;
  bool _loading = true;
  _SectionFilter _filter = _SectionFilter.all;
  bool _showTokens = true;

  @override
  void initState() {
    super.initState();
    _build();
  }

  Future<void> _build() async {
    setState(() => _loading = true);

    try {
      final chatState = ref.read(chatProvider(widget.charId)).value;
      final session = chatState?.session;
      if (session == null) {
        setState(() => _loading = false);
        return;
      }

      final builder = ref.read(promptPayloadBuilderProvider);
      final payload = await builder.buildFromSession(
        charId: widget.charId,
        session: session,
      );
      _apiConfig = payload.apiConfig;

      final result = await buildPromptInIsolate(payload);
      if (mounted)
        setState(() {
          _result = result;
          _loading = false;
        });
    } catch (e) {
      debugPrint('Prompt preview error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(chatProvider(widget.charId), (prev, next) {
      final prevSession = prev?.value?.session;
      final nextSession = next.value?.session;
      if (prevSession != nextSession && !_loading) {
        _build();
      }
    });
    return SheetView(
      title: 'Prompt Preview',
      showBack: true,
      onBack: () => Navigator.of(context).maybePop(),
      actions: [
        SheetViewAction(
          icon: Icon(
            _showTokens ? Icons.numbers : Icons.numbers_outlined,
            size: 20,
          ),
          onPressed: () => setState(() => _showTokens = !_showTokens),
          tooltip: 'Toggle token counts',
        ),
        SheetViewAction(
          icon: const Icon(Icons.copy, size: 20),
          onPressed: _copyJson,
          tooltip: 'Copy as JSON',
        ),
      ],
      body: Column(
        children: [
          Builder(
            builder: (context) =>
                SizedBox(height: MediaQuery.paddingOf(context).top),
          ),
          if (_result != null && _apiConfig != null)
            _SummaryBar(result: _result!, contextSize: _apiConfig!.contextSize),
          GlazeFilterChipBar<_SectionFilter>(
            current: _filter,
            options: _SectionFilter.values.toList(),
            labelBuilder: _labelForFilter,
            onSelected: (f) => setState(() => _filter = f),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _result == null
                ? Center(
                    child: Text(
                      'No data',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  )
                : _MessageList(
                    messages: _filteredMessages,
                    showTokens: _showTokens,
                  ),
          ),
        ],
      ),
    );
  }

  List<PromptMessage> get _filteredMessages {
    final msgs = _result?.messages ?? [];
    return switch (_filter) {
      _SectionFilter.all => msgs,
      _SectionFilter.system =>
        msgs
            .where((m) => m.role == 'system' && !m.isHistory && !m.isLorebook)
            .toList(),
      _SectionFilter.lorebook => msgs.where((m) => m.isLorebook).toList(),
      _SectionFilter.history => msgs.where((m) => m.isHistory).toList(),
      _SectionFilter.depth => msgs.where((m) => m.isDepth).toList(),
    };
  }

  void _copyJson() {
    if (_result == null) return;
    final json = _result!.messages.map((m) {
      final map = <String, dynamic>{'role': m.role, 'content': m.content};
      if (m.isLorebook) map['lorebook'] = true;
      if (m.blockName != null) map['block'] = m.blockName;
      if (m.isDepth) map['depth'] = m.depth;
      return map;
    }).toList();
    Clipboard.setData(ClipboardData(text: json.toString()));
    GlazeToast.show(context, 'Copied to clipboard');
  }
}

class _SummaryBar extends StatelessWidget {
  final PromptResult result;
  final int contextSize;
  const _SummaryBar({required this.result, required this.contextSize});

  @override
  Widget build(BuildContext context) {
    final total = result.breakdown.totalTokens;
    final pct = contextSize > 0
        ? (total / contextSize * 100).clamp(0, 100)
        : 0.0;
    final barColor = pct > 90
        ? Colors.red
        : pct > 75
        ? Colors.orange
        : Colors.green;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '$total',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: barColor,
                ),
              ),
              Text(
                ' / $contextSize tokens',
                style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
              ),
              const Spacer(),
              Text(
                '${pct.toStringAsFixed(1)}%',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: barColor,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${result.messages.length} msgs',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct / 100,
              backgroundColor: Colors.white10,
              color: barColor,
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }
}

enum _SectionFilter { all, system, lorebook, history, depth }

String _labelForFilter(_SectionFilter f) => switch (f) {
  _SectionFilter.all => 'All',
  _SectionFilter.system => 'System',
  _SectionFilter.lorebook => 'Lorebook',
  _SectionFilter.history => 'History',
  _SectionFilter.depth => 'Depth',
};

class _MessageList extends StatelessWidget {
  final List<PromptMessage> messages;
  final bool showTokens;
  const _MessageList({required this.messages, required this.showTokens});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
      itemCount: messages.length,
      itemBuilder: (_, i) => _PromptMessageCard(
        message: messages[i],
        index: i,
        showTokens: showTokens,
      ),
    );
  }
}

class _PromptMessageCard extends StatefulWidget {
  final PromptMessage message;
  final int index;
  final bool showTokens;
  const _PromptMessageCard({
    required this.message,
    required this.index,
    required this.showTokens,
  });

  @override
  State<_PromptMessageCard> createState() => _PromptMessageCardState();
}

class _PromptMessageCardState extends State<_PromptMessageCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final msg = widget.message;
    final scheme = _schemeFor(msg);
    final tokenCount = widget.showTokens ? estimateTokens(msg.content) : 0;

    return Card(
      color: scheme.bgColor,
      margin: const EdgeInsets.symmetric(vertical: 3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: scheme.accentColor.withValues(alpha: 0.2)),
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
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: scheme.accentColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    scheme.label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: scheme.accentColor,
                    ),
                  ),
                  if (msg.blockName != null) ...[
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        msg.blockName!,
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                  const Spacer(),
                  if (widget.showTokens)
                    Text(
                      '$tokenCount t',
                      style: TextStyle(
                        fontSize: 10,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  if (msg.isDepth && msg.depth != null) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'd${msg.depth}',
                        style: const TextStyle(
                          fontSize: 9,
                          color: Colors.orange,
                        ),
                      ),
                    ),
                  ],
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
              if (!_expanded) ...[
                const SizedBox(height: 6),
                Text(
                  msg.content,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary.withValues(alpha: 0.8),
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
                  constraints: const BoxConstraints(maxHeight: 300),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      msg.content,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textPrimary,
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

_SectionScheme _schemeFor(PromptMessage msg) {
  if (msg.isLorebook) {
    return _SectionScheme(
      label: 'Lorebook',
      accentColor: Colors.cyan,
      bgColor: Colors.cyan.withValues(alpha: 0.04),
    );
  }
  if (msg.isDepth) {
    return _SectionScheme(
      label: 'Depth Block',
      accentColor: Colors.orange,
      bgColor: Colors.orange.withValues(alpha: 0.04),
    );
  }
  if (msg.isHistory) {
    return _SectionScheme(
      label: msg.role == 'user' ? 'User' : 'Assistant',
      accentColor: msg.role == 'user' ? Colors.blue : Colors.green,
      bgColor: (msg.role == 'user' ? Colors.blue : Colors.green).withValues(
        alpha: 0.04,
      ),
    );
  }
  if (msg.blockName == 'Memory Book') {
    return _SectionScheme(
      label: 'Memory Book',
      accentColor: Colors.amber,
      bgColor: Colors.amber.withValues(alpha: 0.04),
    );
  }
  if (msg.blockName == 'Summary') {
    return _SectionScheme(
      label: 'Summary',
      accentColor: Colors.purple,
      bgColor: Colors.purple.withValues(alpha: 0.04),
    );
  }
  return _SectionScheme(
    label: msg.blockName ?? msg.role,
    accentColor: AppColors.accent,
    bgColor: AppColors.accent.withValues(alpha: 0.04),
  );
}

class _SectionScheme {
  final String label;
  final Color accentColor;
  final Color bgColor;
  const _SectionScheme({
    required this.label,
    required this.accentColor,
    required this.bgColor,
  });
}

void showPromptPreviewScreen(BuildContext context, String charId) {
  GlazeBottomSheet.show(
    context,
    child: PromptPreviewScreen(charId: charId),
  );
}
