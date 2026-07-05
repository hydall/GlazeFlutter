import 'package:flutter/material.dart';

import '../../../shared/widgets/sheet_view.dart';
import 'tokenizer_sheet.dart';
import 'prompt_preview_screen.dart';
import 'lorebook_coverage_sheet.dart';

/// Unified diagnostics surface that merges the Context (tokenizer), Request
/// Preview, and Lorebook Coverage sheets into one tabbed sheet. All three
/// answer the same question - "what actually goes into the prompt?" - so they
/// live behind a single Magic Drawer entry instead of three separate cards.
class PromptInspectorSheet extends StatefulWidget {
  final String charId;
  final String initialTabId;

  const PromptInspectorSheet({
    super.key,
    required this.charId,
    this.initialTabId = _tabContext,
  });

  static const _tabContext = 'context';
  static const _tabPreview = 'preview';
  static const _tabCoverage = 'coverage';

  @override
  State<PromptInspectorSheet> createState() => _PromptInspectorSheetState();
}

class _PromptInspectorSheetState extends State<PromptInspectorSheet> {
  late String _activeTabId = widget.initialTabId;

  static const _order = [
    PromptInspectorSheet._tabContext,
    PromptInspectorSheet._tabPreview,
    PromptInspectorSheet._tabCoverage,
  ];

  int get _activeIndex {
    final i = _order.indexOf(_activeTabId);
    return i < 0 ? 0 : i;
  }

  @override
  Widget build(BuildContext context) {
    // Keep every tab's state alive across switches (each runs its own async
    // computation on first build) via an IndexedStack.
    final body = IndexedStack(
      index: _activeIndex,
      children: [
        TokenizerSheet(charId: widget.charId, embedded: true),
        PromptPreviewScreen(charId: widget.charId, embedded: true),
        CoveragePanel(charId: widget.charId, embedded: true),
      ],
    );

    return SheetView(
      title: 'Prompt Inspector',
      showBack: true,
      startExpanded: true,
      onBack: () => Navigator.of(context).maybePop(),
      tabs: const [
        SheetViewTab(
          id: PromptInspectorSheet._tabContext,
          label: 'Context',
          icon: Icons.segment,
        ),
        SheetViewTab(
          id: PromptInspectorSheet._tabPreview,
          label: 'Request',
          icon: Icons.visibility,
        ),
        SheetViewTab(
          id: PromptInspectorSheet._tabCoverage,
          label: 'Coverage',
          icon: Icons.search,
        ),
      ],
      activeTabId: _activeTabId,
      onTabSelected: (id) => setState(() => _activeTabId = id),
      body: body,
    );
  }
}

void showPromptInspectorSheet(
  BuildContext context,
  String charId, {
  String initialTabId = PromptInspectorSheet._tabContext,
}) {
  showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) =>
        PromptInspectorSheet(charId: charId, initialTabId: initialTabId),
  );
}
