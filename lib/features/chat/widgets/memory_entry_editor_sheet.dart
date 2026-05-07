import 'package:flutter/material.dart';

import '../../../core/models/memory_book.dart';
import '../../../shared/theme/app_colors.dart';

class MemoryEntryEditorSheet extends StatefulWidget {
  final MemoryEntry entry;

  const MemoryEntryEditorSheet({super.key, required this.entry});

  @override
  State<MemoryEntryEditorSheet> createState() => _MemoryEntryEditorSheetState();
}

class _MemoryEntryEditorSheetState extends State<MemoryEntryEditorSheet> {
  late TextEditingController _titleController;
  late TextEditingController _contentController;
  late TextEditingController _keysController;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.entry.title);
    _contentController = TextEditingController(text: widget.entry.content);
    _keysController = TextEditingController(text: widget.entry.keys.join(', '));
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _keysController.dispose();
    super.dispose();
  }

  void _save() {
    final content = _contentController.text.trim();
    if (content.isEmpty) return;
    final keys = _keysController.text
        .split(',')
        .map((k) => k.trim().toLowerCase())
        .where((k) => k.isNotEmpty)
        .toList();
    final entry = widget.entry.copyWith(
      title: _titleController.text.trim(),
      content: content,
      keys: keys,
    );
    Navigator.pop(context, entry);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _field('Title', _titleController, hint: 'Optional label'),
          const SizedBox(height: 12),
          _field('Keys', _keysController, hint: 'Comma-separated trigger keywords'),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text('Only this field is used for keyword retrieval', style: TextStyle(fontSize: 11, color: AppColors.textSecondary.withValues(alpha: 0.6))),
          ),
          const SizedBox(height: 12),
          _field('Content', _contentController, hint: 'Memory text injected into prompt', maxLines: 8),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.accent, foregroundColor: Colors.black),
                onPressed: _save,
                child: const Text('Save'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _field(String label, TextEditingController controller, {String? hint, int maxLines = 1}) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        hintText: hint,
        hintStyle: TextStyle(color: AppColors.textSecondary.withValues(alpha: 0.4)),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}
