import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/chat_message.dart';
import '../../../core/state/chat_session_ops_provider.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/widgets/generic_editor.dart';
import '../../../shared/widgets/sheet_view.dart';
import '../chat_provider.dart';

class AuthorsNoteSheet extends ConsumerStatefulWidget {
  final String charId;
  const AuthorsNoteSheet({super.key, required this.charId});

  @override
  ConsumerState<AuthorsNoteSheet> createState() => _AuthorsNoteSheetState();
}

class _AuthorsNoteSheetState extends ConsumerState<AuthorsNoteSheet> {
  late Map<String, dynamic> _localItem;
  late bool _enabled;

  @override
  void initState() {
    super.initState();
    final session = ref.read(chatProvider(widget.charId)).value?.session;
    final note = session?.authorsNote;
    
    _enabled = note?.enabled ?? true;
    _localItem = {
      'content': note?.content ?? '',
      'insertionMode': note?.insertionMode ?? 'depth',
      'depth': note?.depth ?? 4,
      'role': note?.role ?? 'system',
    };
  }

  Future<void> _performSave(Map<String, dynamic> item) async {
    final session = ref.read(chatProvider(widget.charId)).value?.session;
    if (session == null) return;
    
    final content = (item['content'] as String?)?.trim() ?? '';
    final note = content.isNotEmpty
        ? AuthorsNote(
            content: content,
            role: item['role'] as String? ?? 'system',
            insertionMode: item['insertionMode'] as String? ?? 'depth',
            depth: item['depth'] as int? ?? 4,
            enabled: _enabled,
          )
        : null;
        
    final updated = session.copyWith(
      authorsNote: note,
      updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
    await ref.read(chatSessionOpsProvider.notifier).saveSession(updated);
    ref.invalidate(chatProvider(widget.charId));
  }

  List<GenericEditorSection> get _config => [
        GenericEditorSection(
          fields: [
            GenericEditorField(
              key: 'content',
              label: 'Note Content',
              type: 'textarea',
              placeholder: 'Enter author\'s note...',
              rows: 6,
            ),
            GenericEditorField(
              key: 'insertionMode',
              label: 'Insertion Mode',
              type: 'select',
              options: [
                {'label': 'Depth', 'value': 'depth'},
                {'label': 'Relative', 'value': 'relative'},
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
              key: 'role',
              label: 'Role',
              type: 'select',
              options: [
                {'label': 'System', 'value': 'system'},
                {'label': 'User', 'value': 'user'},
                {'label': 'Assistant', 'value': 'assistant'},
              ],
            ),
          ],
        ),
      ];

  @override
  Widget build(BuildContext context) {
    return SheetView(
      title: "Author's Note",
      showBack: true,
      actions: [
        SheetViewAction(
          icon: Switch(
            value: _enabled,
            onChanged: (v) {
              setState(() => _enabled = v);
              _performSave(_localItem);
            },
            activeThumbColor: context.cs.primary,
          ),
          onPressed: () {
            setState(() => _enabled = !_enabled);
            _performSave(_localItem);
          },
        ),
      ],
      body: Builder(
        builder: (innerContext) => GenericEditor(
          item: _localItem,
          config: _config,
          onChanged: (val) => setState(() => _localItem = val),
          onSave: _performSave,
          useWindows: false,
          padding: EdgeInsets.only(
            top: MediaQuery.paddingOf(innerContext).top + 4,
            bottom: MediaQuery.paddingOf(innerContext).bottom + 24,
          ),
        ),
      ),
    );
  }
}

void showAuthorsNoteSheet(BuildContext context, String charId) {
  showModalBottomSheet(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => AuthorsNoteSheet(charId: charId),
  );
}
