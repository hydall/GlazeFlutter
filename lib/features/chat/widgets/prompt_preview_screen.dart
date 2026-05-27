import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dart:convert';

import '../../../core/llm/history_assembler.dart';
import '../../../core/llm/prompt_builder.dart';
import '../../../core/llm/prompt_isolate.dart';
import '../../../core/llm/prompt_payload_builder.dart';
import '../../../core/llm/tokenizer.dart';
import '../../../core/models/api_config.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/widgets/glaze_filter_chip_bar.dart';
import '../../../shared/widgets/glaze_tab_bar.dart';
import '../../../shared/widgets/glaze_toast.dart';
import '../../../shared/widgets/sheet_view.dart';
import '../chat_provider.dart';
import 'cached_token_breakdown.dart';

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
  int _dataTabIndex = 0;
  int _previewTabIndex = 0;

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
        skipVectorSearch: true,
      );
      _apiConfig = payload.apiConfig;

      final result = await buildPromptInIsolate(payload);
      ref
          .read(cachedTokenBreakdownProvider(widget.charId).notifier)
          .state = result.breakdown;
      if (mounted) {
        setState(() {
          _result = result;
          _loading = false;
        });
      }
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
      titleWidget: Row(
        children: [
          Expanded(
            child: Text(
              'Request Preview',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: context.cs.onSurface,
              ),
            ),
          ),
          if (_previewTabIndex == 1) ...[
            Material(
              color: Colors.white.withValues(alpha: 0.06),
              shape: const CircleBorder(),
              child: Tooltip(
                message: 'Copy',
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _copyContent,
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: Center(
                      child: Icon(Icons.copy, size: 20, color: context.cs.primary),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          _SegmentedToggle(
            isRaw: _previewTabIndex == 1,
            onChanged: (isRaw) => setState(() => _previewTabIndex = isRaw ? 1 : 0),
          ),
        ],
      ),
      showBack: true,
      onBack: () => Navigator.of(context).maybePop(),
      headerBottom: GlazeTabBar(
        tabs: const [
          GlazeTabItem(label: 'Request', icon: Icons.upload_rounded),
          GlazeTabItem(label: 'Response', icon: Icons.download_rounded),
        ],
        activeIndex: _dataTabIndex,
        onChanged: (i) => setState(() => _dataTabIndex = i),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    return Builder(
      builder: (context) {
        final topPad = MediaQuery.paddingOf(context).top;

        if (_dataTabIndex == 0) {
          if (_loading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (_result == null) {
            return Center(
              child: Text(
                'No data',
                style: TextStyle(color: context.cs.onSurfaceVariant),
              ),
            );
          }
          if (_previewTabIndex == 1) {
            return _buildRawView(_getRawPromptJson(), topPad);
          }
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: SizedBox(height: topPad),
              ),
              if (_apiConfig != null) ...[
                SliverToBoxAdapter(
                  child: _SummaryBar(result: _result!, contextSize: _apiConfig!.contextSize),
                ),
                const SliverToBoxAdapter(child: _SectionTitle('Parameters')),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverToBoxAdapter(
                    child: _buildParamsGrid(_apiConfig!),
                  ),
                ),
              ],
              SliverToBoxAdapter(
                child: _SectionTitle('Messages (${_result!.messages.length})'),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: GlazeFilterChipBar<_SectionFilter>(
                    current: _filter,
                    options: _SectionFilter.values.toList(),
                    labelBuilder: _labelForFilter,
                    onSelected: (f) => setState(() => _filter = f),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => _PromptMessageCard(
                      message: _filteredMessages[i],
                      index: i,
                    ),
                    childCount: _filteredMessages.length,
                  ),
                ),
              ),
            ],
          );
        } else {
          final chatState = ref.watch(chatProvider(widget.charId)).value;
          final raw = chatState?.lastRawResponse;
          if (raw == null || raw.isEmpty) {
            return Center(
              child: Text(
                'No response data',
                style: TextStyle(color: context.cs.onSurfaceVariant),
              ),
            );
          }
          String displayString = raw;
          if (_previewTabIndex == 0) {
            try {
              final decoded = jsonDecode(raw);
              displayString = const JsonEncoder.withIndent('  ').convert(decoded);
            } catch (_) {
            }
          }
          return _buildRawView(displayString, topPad);
        }
      },
    );
  }

  Widget _buildRawView(String text, double topPad) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: topPad + 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SelectableText(
              text,
              style: TextStyle(
                color: context.cs.onSurface,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParamsGrid(ApiConfig config) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = (constraints.maxWidth - 8) / 2;
        final items = [
          _ParamItem(label: 'model', value: config.model),
          _ParamItem(label: 'max_tokens', value: config.maxTokens.toString()),
          _ParamItem(label: 'temperature', value: config.temperature.toString()),
          _ParamItem(label: 'top_p', value: config.topP.toString()),
          _ParamItem(label: 'stream', value: config.stream.toString()),
        ];
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: items.map((w) => SizedBox(width: itemWidth, child: w)).toList(),
        );
      },
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

  void _copyContent() {
    String textToCopy = '';
    if (_dataTabIndex == 0) {
      if (_previewTabIndex == 0) {
        if (_result == null) return;
        final json = _result!.messages.map((m) {
          final map = <String, dynamic>{'role': m.role, 'content': m.content};
          if (m.isLorebook) map['lorebook'] = true;
          if (m.blockName != null) map['block'] = m.blockName;
          if (m.isDepth) map['depth'] = m.depth;
          return map;
        }).toList();
        textToCopy = jsonEncode(json);
      } else {
        textToCopy = _getRawPromptJson();
      }
    } else {
      final chatState = ref.read(chatProvider(widget.charId)).value;
      textToCopy = chatState?.lastRawResponse ?? '';
    }

    if (textToCopy.isEmpty) return;
    Clipboard.setData(ClipboardData(text: textToCopy));
    GlazeToast.show(context, 'Copied to clipboard');
  }

  String _getRawPromptJson() {
    if (_result == null || _apiConfig == null) return '';
    try {
      final rawJson = const JsonEncoder.withIndent('  ').convert({
        'model': _apiConfig!.model,
        'messages': _result!.messages.map((m) {
          final map = <String, dynamic>{'role': m.role, 'content': m.content};
          if (m.isLorebook) map['lorebook'] = true;
          if (m.blockName != null) map['block'] = m.blockName;
          return map;
        }).toList(),
        'max_tokens': _apiConfig!.maxTokens,
        'temperature': _apiConfig!.temperature,
        'top_p': _apiConfig!.topP,
        'stream': _apiConfig!.stream,
      });
      return rawJson;
    } catch (_) {
      return '';
    }
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
                style: TextStyle(fontSize: 14, color: context.cs.onSurfaceVariant),
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
                style: TextStyle(fontSize: 12, color: context.cs.onSurfaceVariant),
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

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 10, left: 16, right: 16),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: context.cs.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _ParamItem extends StatelessWidget {
  final String label;
  final String value;
  const _ParamItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              color: context.cs.onSurfaceVariant,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: context.cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _PromptMessageCard extends StatefulWidget {
  final PromptMessage message;
  final int index;
  const _PromptMessageCard({
    required this.message,
    required this.index,
  });

  @override
  State<_PromptMessageCard> createState() => _PromptMessageCardState();
}

class _PromptMessageCardState extends State<_PromptMessageCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final msg = widget.message;
    final tokenCount = estimateTokens(msg.content);

    return Card(
      color: Colors.white.withValues(alpha: 0.05),
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _expanded = !_expanded),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _buildRoleChip(msg.role),
                  if (msg.blockName != null) ...[
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        msg.blockName!,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: context.cs.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                  const Spacer(),
                  Text(
                    '$tokenCount t',
                    style: TextStyle(
                      fontSize: 10,
                      color: context.cs.onSurfaceVariant,
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
                    color: context.cs.onSurfaceVariant,
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
                    color: context.cs.onSurfaceVariant.withValues(alpha: 0.8),
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
                      style: TextStyle(
                        fontSize: 12,
                        color: context.cs.onSurface,
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
  Widget _buildRoleChip(String role) {
    Color bg = const Color(0xFF424242);
    Color fg = const Color(0xFFE0E0E0);
    if (role == 'system') {
      bg = const Color(0xFF1565C0);
      fg = const Color(0xFFE3F2FD);
    } else if (role == 'user') {
      bg = const Color(0xFF7B1FA2);
      fg = const Color(0xFFF3E5F5);
    } else if (role == 'assistant') {
      bg = const Color(0xFF2E7D32);
      fg = const Color(0xFFE8F5E9);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        role.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }
}

class _SegmentedToggle extends StatelessWidget {
  final bool isRaw;
  final ValueChanged<bool> onChanged;

  const _SegmentedToggle({required this.isRaw, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!isRaw),
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 32,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Stack(
          children: [
            AnimatedPositioned(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              left: isRaw ? 32 : 0,
              top: 0,
              bottom: 0,
              width: 32,
              child: Container(
                decoration: BoxDecoration(
                  color: context.cs.primary,
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 32,
                  child: Center(
                    child: Icon(
                      Icons.visibility,
                      size: 16,
                      color: !isRaw ? Colors.white : context.cs.onSurfaceVariant,
                    ),
                  ),
                ),
                SizedBox(
                  width: 32,
                  child: Center(
                    child: Icon(
                      Icons.code,
                      size: 16,
                      color: isRaw ? Colors.white : context.cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

void showPromptPreviewScreen(BuildContext context, String charId) {
  showModalBottomSheet(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => PromptPreviewScreen(charId: charId),
  );
}
