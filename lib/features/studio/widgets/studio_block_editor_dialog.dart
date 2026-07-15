import 'package:flutter/material.dart';

import '../../../core/models/studio_config.dart';

/// Dialog for editing a single [StudioPresetBlock].
///
/// Shows editable fields for: title, role, content, enabled, order, section,
/// and kind. Returns the updated block (or null if cancelled).
class StudioBlockEditorDialog extends StatefulWidget {
  final StudioPresetBlock block;
  final bool isNew;

  const StudioBlockEditorDialog({
    super.key,
    required this.block,
    this.isNew = false,
  });

  @override
  State<StudioBlockEditorDialog> createState() =>
      _StudioBlockEditorDialogState();
}

class _StudioBlockEditorDialogState extends State<StudioBlockEditorDialog> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _contentCtrl;
  late String _role;
  late String _section;
  late String _kind;
  late bool _enabled;

  static const _roles = ['system', 'user', 'assistant'];
  static const _sections = [
    'pregen',
    'final',
    'cleaner',
    'ledger',
    'build',
    'brief_parser',
  ];
  static const _kinds = [
    'custom_text',
    'slot',
    'instruction',
    'agent_instruction',
    'tracker_instruction',
    'previous_agents',
    'user_persona',
    'char_card',
    'scenario',
    'char_personality',
    'example_dialogue',
    'authors_note',
    'static_context',
    'chat_history',
    'memory',
    'dynamic_context',
  ];

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.block.title);
    _contentCtrl = TextEditingController(text: widget.block.content);
    _role = widget.block.role;
    _section = widget.block.section;
    _kind = widget.block.kind;
    _enabled = widget.block.enabled;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.isNew ? 'New Block' : 'Edit Block'),
      content: SizedBox(
        width: 600,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _titleCtrl,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _section,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Section',
                        border: OutlineInputBorder(),
                      ),
                      items: _sections
                          .map(
                            (s) => DropdownMenuItem(value: s, child: Text(s)),
                          )
                          .toList(),
                      onChanged: (v) =>
                          setState(() => _section = v ?? _section),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _kind,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Kind',
                        border: OutlineInputBorder(),
                      ),
                      items: _kinds
                          .map(
                            (k) => DropdownMenuItem(value: k, child: Text(k)),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => _kind = v ?? _kind),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _role,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Role',
                        border: OutlineInputBorder(),
                      ),
                      items: _roles
                          .map(
                            (r) => DropdownMenuItem(value: r, child: Text(r)),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => _role = v ?? _role),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(
                        value: _enabled,
                        onChanged: (v) => setState(() => _enabled = v),
                      ),
                      const Text('Enabled'),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _contentCtrl,
                maxLines: 12,
                decoration: const InputDecoration(
                  labelText: 'Content (macro templates supported)',
                  hintText:
                      'Use {{description}}, {{persona}}, {{memory}}, etc.',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Studio final-agent briefs: either enable the '
                  '"Previous Studio agents" block, or place these macros in '
                  'custom final blocks: {{studio_agent_briefs}}, '
                  '{{studio_continuity_brief}}, {{studio_agency_brief}}, '
                  '{{studio_narrative_brief}}, {{studio_dialogue_brief}}, '
                  '{{studio_guard_brief}}, {{studio_world_brief}}, '
                  '{{studio_meta_brief}}, {{studio_beauty_brief}}. If any '
                  'Studio brief macro is present, the Previous Studio agents '
                  'block is skipped to avoid duplicates.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }

  void _save() {
    final updated = widget.block.copyWith(
      title: _titleCtrl.text,
      content: _contentCtrl.text,
      role: _role,
      section: _section,
      kind: _kind,
      enabled: _enabled,
    );
    Navigator.of(context).pop(updated);
  }
}
