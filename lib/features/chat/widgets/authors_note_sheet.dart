import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/chat_message.dart';
import '../../../core/state/db_provider.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/widgets/sheet_view.dart';
import '../chat_provider.dart';

class AuthorsNoteSheet extends ConsumerStatefulWidget {
  final String charId;
  const AuthorsNoteSheet({super.key, required this.charId});

  @override
  ConsumerState<AuthorsNoteSheet> createState() => _AuthorsNoteSheetState();
}

class _AuthorsNoteSheetState extends ConsumerState<AuthorsNoteSheet> {
  late final TextEditingController _controller;
  late String _insertionMode;
  late int _depth;
  late String _role;
  late bool _enabled;

  @override
  void initState() {
    super.initState();
    final session = ref.read(chatProvider(widget.charId)).value?.session;
    final note = session?.authorsNote;
    _controller = TextEditingController(text: note?.content ?? '');
    _insertionMode = note?.insertionMode ?? 'depth';
    _depth = note?.depth ?? 4;
    _role = note?.role ?? 'system';
    _enabled = note?.enabled ?? true;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final session = ref.read(chatProvider(widget.charId)).value?.session;
    if (session == null) return;
    final content = _controller.text.trim();
    final note = content.isNotEmpty
        ? AuthorsNote(
            content: content,
            role: _role,
            insertionMode: _insertionMode,
            depth: _depth,
            enabled: _enabled,
          )
        : null;
    final updated = session.copyWith(
      authorsNote: note,
      updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
    await ref.read(chatRepoProvider).put(updated);
    ref.invalidate(chatProvider(widget.charId));
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return SheetView(
      title: "Author's Note",
      showBack: true,
      actions: [
        SheetViewAction(
          icon: Switch(
            value: _enabled,
            onChanged: (v) => setState(() => _enabled = v),
            activeThumbColor: AppColors.accent,
          ),
          onPressed: () => setState(() => _enabled = !_enabled),
        ),
      ],
      body: ListView(
        padding: EdgeInsets.only(
          top: MediaQuery.paddingOf(context).top + 8,
          left: 16,
          right: 16,
          bottom: MediaQuery.paddingOf(context).bottom + 16,
        ),
        children: [
          TextField(
            controller: _controller,
            maxLines: 6,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 14,
            ),
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.05),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              hintText: 'Enter author\'s note...',
              hintStyle: TextStyle(
                color: AppColors.textSecondary.withValues(alpha: 0.5),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _insertionMode,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.05),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    labelText: 'Insertion',
                    labelStyle: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  dropdownColor: const Color(0xFF2A2A2A),
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                  ),
                  items: const [
                    DropdownMenuItem(value: 'depth', child: Text('Depth')),
                    DropdownMenuItem(
                      value: 'relative',
                      child: Text('Relative'),
                    ),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _insertionMode = v);
                  },
                ),
              ),
              if (_insertionMode == 'depth') ...[
                const SizedBox(width: 12),
                SizedBox(
                  width: 80,
                  child: DropdownButtonFormField<int>(
                    initialValue: _depth,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.05),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      labelText: 'Depth',
                      labelStyle: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    dropdownColor: const Color(0xFF2A2A2A),
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                    ),
                    items: List.generate(
                      20,
                      (i) => DropdownMenuItem(
                        value: i + 1,
                        child: Text('${i + 1}'),
                      ),
                    ),
                    onChanged: (v) {
                      if (v != null) setState(() => _depth = v);
                    },
                  ),
                ),
              ],
              const SizedBox(width: 12),
              SizedBox(
                width: 100,
                child: DropdownButtonFormField<String>(
                  initialValue: _role,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.05),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    labelText: 'Role',
                    labelStyle: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  dropdownColor: const Color(0xFF2A2A2A),
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                  ),
                  items: const [
                    DropdownMenuItem(value: 'system', child: Text('System')),
                    DropdownMenuItem(value: 'user', child: Text('User')),
                    DropdownMenuItem(
                      value: 'assistant',
                      child: Text('Assistant'),
                    ),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _role = v);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _save,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent,
              minimumSize: const Size.fromHeight(44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Save',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

void showAuthorsNoteSheet(BuildContext context, String charId) {
  showModalBottomSheet(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => AuthorsNoteSheet(charId: charId),
  );
}
