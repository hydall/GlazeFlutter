import 'package:flutter/material.dart';

import '../../../core/models/lorebook.dart';
import '../../../shared/theme/app_colors.dart';

class EntryEditorDialog extends StatefulWidget {
  final LorebookEntry? entry;

  const EntryEditorDialog({super.key, this.entry});

  @override
  State<EntryEditorDialog> createState() => _EntryEditorDialogState();
}

class _EntryEditorDialogState extends State<EntryEditorDialog> {
  late TextEditingController _commentController;
  late TextEditingController _contentController;
  late TextEditingController _keysController;
  late TextEditingController _secondaryKeysController;
  late TextEditingController _orderController;
  late TextEditingController _scanDepthController;
  late TextEditingController _probabilityController;
  late TextEditingController _stickyController;
  late TextEditingController _cooldownController;
  late TextEditingController _groupController;
  bool _enabled = true;
  bool _constant = false;
  bool _caseSensitive = false;
  bool _preventRecursion = false;
  bool _ignoreBudget = false;
  int _selectiveLogic = 5;
  String _position = 'worldInfoBefore';

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _commentController = TextEditingController(text: e?.comment ?? '');
    _contentController = TextEditingController(text: e?.content ?? '');
    _keysController = TextEditingController(text: e?.keys.join(', ') ?? '');
    _secondaryKeysController = TextEditingController(text: e?.secondaryKeys.join(', ') ?? '');
    _orderController = TextEditingController(text: (e?.order ?? 100).toString());
    _scanDepthController = TextEditingController(text: e?.scanDepth?.toString() ?? '');
    _probabilityController = TextEditingController(text: (e?.probability ?? 100).toString());
    _stickyController = TextEditingController(text: (e?.sticky ?? 0).toString());
    _cooldownController = TextEditingController(text: (e?.cooldown ?? 0).toString());
    _groupController = TextEditingController(text: e?.group ?? '');
    _enabled = e?.enabled ?? true;
    _constant = e?.constant ?? false;
    _caseSensitive = e?.caseSensitive ?? false;
    _preventRecursion = e?.preventRecursion ?? false;
    _ignoreBudget = e?.ignoreBudget ?? false;
    _selectiveLogic = e?.selectiveLogic ?? 5;
    _position = e?.position ?? 'worldInfoBefore';
  }

  @override
  void dispose() {
    _commentController.dispose();
    _contentController.dispose();
    _keysController.dispose();
    _secondaryKeysController.dispose();
    _orderController.dispose();
    _scanDepthController.dispose();
    _probabilityController.dispose();
    _stickyController.dispose();
    _cooldownController.dispose();
    _groupController.dispose();
    super.dispose();
  }

  LorebookEntry _buildEntry() {
    return LorebookEntry(
      id: widget.entry?.id ?? DateTime.now().millisecondsSinceEpoch.toRadixString(36),
      comment: _commentController.text.trim(),
      enabled: _enabled,
      constant: _constant,
      keys: _parseList(_keysController.text),
      secondaryKeys: _parseList(_secondaryKeysController.text),
      selectiveLogic: _selectiveLogic,
      content: _contentController.text,
      position: _position,
      order: int.tryParse(_orderController.text) ?? 100,
      scanDepth: int.tryParse(_scanDepthController.text),
      caseSensitive: _caseSensitive,
      probability: int.tryParse(_probabilityController.text) ?? 100,
      preventRecursion: _preventRecursion,
      sticky: int.tryParse(_stickyController.text) ?? 0,
      cooldown: int.tryParse(_cooldownController.text) ?? 0,
      group: _groupController.text.trim(),
      ignoreBudget: _ignoreBudget,
    );
  }

  List<String> _parseList(String text) {
    return text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.background,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    widget.entry == null ? 'New Entry' : 'Edit Entry',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _field('Comment', _commentController),
                  const SizedBox(height: 12),
                  _field('Keys (comma separated)', _keysController, hint: 'dragon, castle'),
                  const SizedBox(height: 12),
                  _field('Secondary Keys', _secondaryKeysController, hint: 'fire, knight'),
                  const SizedBox(height: 8),
                  _dropdown('Secondary Logic', _selectiveLogic, {
                    0: 'ANY secondary',
                    1: 'ALL secondary',
                    2: 'NOT ANY secondary',
                    3: 'NOT ALL secondary',
                    4: 'No secondary needed',
                    5: 'Default (no secondary)',
                  }, (v) => setState(() => _selectiveLogic = v)),
                  const SizedBox(height: 12),
                  _field('Content', _contentController, maxLines: 5),
                  const SizedBox(height: 8),
                  _dropdown('Position', _position, const {
                    'worldInfoBefore': 'Before char card',
                    'worldInfoAfter': 'After chat history',
                    'lorebooksMacro': '{{lorebooks}} macro',
                  }, (v) => setState(() => _position = v)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: _field('Order', _orderController)),
                      const SizedBox(width: 8),
                      Expanded(child: _field('Scan Depth', _scanDepthController, hint: 'global')),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: _field('Probability %', _probabilityController)),
                      const SizedBox(width: 8),
                      Expanded(child: _field('Sticky', _stickyController)),
                      const SizedBox(width: 8),
                      Expanded(child: _field('Cooldown', _cooldownController)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _field('Group', _groupController),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      _chip('Enabled', _enabled, (v) => setState(() => _enabled = v)),
                      _chip('Constant', _constant, (v) => setState(() => _constant = v)),
                      _chip('Case Sensitive', _caseSensitive, (v) => setState(() => _caseSensitive = v)),
                      _chip('Prevent Recursion', _preventRecursion, (v) => setState(() => _preventRecursion = v)),
                      _chip('Ignore Budget', _ignoreBudget, (v) => setState(() => _ignoreBudget = v)),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                  const SizedBox(width: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: AppColors.accent, foregroundColor: Colors.black),
                    onPressed: () => Navigator.pop(context, _buildEntry()),
                    child: const Text('Save'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(String label, TextEditingController controller, {int maxLines = 1, String? hint}) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        hintStyle: TextStyle(color: AppColors.textSecondary.withValues(alpha: 0.5), fontSize: 12),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Widget _dropdown<T>(String label, T value, Map<T, String> items, ValueChanged<T> onChanged) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isDense: true,
          isExpanded: true,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
          items: items.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 13)))).toList(),
          onChanged: (v) { if (v != null) onChanged(v); },
        ),
      ),
    );
  }

  Widget _chip(String label, bool value, ValueChanged<bool> onChanged) {
    return FilterChip(
      label: Text(label, style: TextStyle(fontSize: 11, color: value ? AppColors.accent : AppColors.textSecondary)),
      selected: value,
      onSelected: onChanged,
      selectedColor: AppColors.accent.withValues(alpha: 0.2),
      checkmarkColor: AppColors.accent,
    );
  }
}
