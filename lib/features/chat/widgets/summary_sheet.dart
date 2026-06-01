import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/chat_message.dart';
import '../../../core/state/chat_session_ops_provider.dart';
import '../../../features/settings/api_list_provider.dart';

import '../../../shared/widgets/generic_editor.dart';
import '../../../shared/widgets/sheet_view.dart';
import '../../../core/llm/summary_service.dart';
import '../../../shared/widgets/glaze_bottom_sheet.dart';
import '../../../shared/widgets/glaze_toast.dart';
import '../chat_provider.dart';

class SummarySheet extends ConsumerStatefulWidget {
  final String charId;
  const SummarySheet({super.key, required this.charId});

  @override
  ConsumerState<SummarySheet> createState() => _SummarySheetState();
}

class _SummarySheetState extends ConsumerState<SummarySheet> {
  late Map<String, dynamic> _localItem;
  bool _isGenerating = false;

  @override
  void initState() {
    super.initState();
    final session = ref.read(chatProvider(widget.charId)).value?.session;
    final summary = session?.summary;
    
    _localItem = {
      'content': summary?.content ?? '',
    };
  }

  Future<void> _performSave(Map<String, dynamic> item) async {
    final session = ref.read(chatProvider(widget.charId)).value?.session;
    if (session == null) return;
    
    final content = (item['content'] as String?)?.trim() ?? '';
    final summary = content.isNotEmpty
        ? ChatSummary(
            content: content,
            role: item['role'] as String? ?? 'system',
            insertionMode: item['insertionMode'] as String? ?? 'relative',
            depth: item['depth'] as int? ?? 4,
            prefix: item['prefix'] as String? ?? 'Summary: ',
          )
        : null;
        
    final updated = session.copyWith(
      summary: summary,
      updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
    await ref.read(chatSessionOpsProvider.notifier).saveSession(updated);
    ref.invalidate(chatProvider(widget.charId));
  }

  List<GenericEditorSection> get _config => [
        GenericEditorSection(
          fields: [
            GenericEditorField(
              key: 'role',
              label: 'Role',
              type: 'select',
              options: [
                {'label': 'System', 'value': 'system'},
                {'label': 'User', 'value': 'user'},
                {'label': 'Assistant', 'value': 'assistant'},
              ],
            ),
            GenericEditorField(
              key: 'insertionMode',
              label: 'Insertion Mode',
              type: 'select',
              options: [
                {'label': 'Relative', 'value': 'relative'},
                {'label': 'Depth', 'value': 'depth'},
              ],
            ),
            GenericEditorField(
              key: 'depth',
              label: 'Depth',
              type: 'select',
              options: List.generate(
                20,
                (i) => {'label': '${i + 1}', 'value': i + 1},
              ),
              showIf: (item) => item['insertionMode'] == 'depth',
            ),
            GenericEditorField(
              key: 'prefix',
              label: 'Prefix',
              type: 'text',
              placeholder: 'Summary: ',
            ),
            GenericEditorField(
              key: 'content',
              label: 'Summary Content',
              type: 'textarea',
              placeholder: 'Enter conversation summary...',
              rows: 8,
            ),
          ],
        ),
      ];

  Future<void> _generateSummary() async {
    final chatState = ref.read(chatProvider(widget.charId)).value;
    final session = chatState?.session;
    if (session == null) return;
    final chatApi = ref.read(activeApiConfigProvider);
    if (chatApi == null || chatApi.mode == 'embedding') {
      if (mounted) {
        GlazeBottomSheet.show(
          context,
          title: 'Summary',
          bigInfo: const BottomSheetBigInfo(
            icon: Icons.api_outlined,
            description:
                'No chat API config found. Add one in API Settings first.',
          ),
        );
      }
      return;
    }

    if (!mounted) return;
    setState(() => _isGenerating = true);
    try {
      final summary = await ref
          .read(summaryServiceProvider)
          .generateSummary(
            sessionId: session.id,
            history: session.messages,
            apiConfig: chatApi,
          );
      if (!mounted) return;
      setState(() {
        _localItem = Map.from(_localItem)..['content'] = summary;
      });
      _performSave(_localItem);
    } catch (e) {
      if (!mounted) return;
      GlazeToast.error(context, 'Summary Failed', e);
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SheetView(
      title: "Summary",
      showBack: true,
      body: Builder(
        builder: (innerContext) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: GenericEditor(
                item: _localItem,
                config: _config,
                onChanged: (val) => setState(() => _localItem = val),
                onSave: _performSave,
                useWindows: false,
                padding: EdgeInsets.only(
                  top: MediaQuery.paddingOf(innerContext).top + 4,
                  bottom: 16,
                ),
              ),
            ),
            Container(
              padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.paddingOf(innerContext).bottom + 24),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
              ),
              child: FilledButton.icon(
                onPressed: _isGenerating ? null : _generateSummary,
                icon: _isGenerating 
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) 
                    : const Icon(Icons.auto_awesome, size: 18),
                label: Text(_isGenerating ? 'Generating...' : 'Generate Summary'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF528BCC),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void showSummarySheet(BuildContext context, String charId) {
  showModalBottomSheet(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => SummarySheet(charId: charId),
  );
}
