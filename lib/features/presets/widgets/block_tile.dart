import 'package:flutter/material.dart';

import '../../../core/models/preset.dart';

class BlockTile extends StatelessWidget {
  final PresetBlock block;
  final ValueChanged<PresetBlock> onChanged;

  const BlockTile({super.key, required this.block, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      title: Row(
        children: [
          Switch(
            value: block.enabled,
            onChanged: (v) => onChanged(block.copyWith(enabled: v)),
          ),
          Expanded(
            child: Text(
              block.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (block.appendToLastMessage) ...[
            const SizedBox(width: 6),
            _appendBadge(context),
            const SizedBox(width: 6),
          ],
          _roleChip(),
        ],
      ),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: block.role,
                      decoration: const InputDecoration(labelText: 'Role'),
                      items: const [
                        DropdownMenuItem(value: 'system', child: Text('System')),
                        DropdownMenuItem(value: 'user', child: Text('User')),
                        DropdownMenuItem(value: 'assistant', child: Text('Assistant')),
                      ],
                      onChanged: (v) {
                        if (v != null) onChanged(block.copyWith(role: v));
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: block.insertionMode,
                      decoration: const InputDecoration(labelText: 'Insertion'),
                      items: const [
                        DropdownMenuItem(value: 'relative', child: Text('Relative')),
                        DropdownMenuItem(value: 'depth', child: Text('Depth')),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          onChanged(block.copyWith(
                            insertionMode: v,
                            depth: v == 'depth' ? (block.depth ?? 4) : null,
                          ));
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 80,
                    child: TextFormField(
                      initialValue: block.depth?.toString() ?? '',
                      decoration: const InputDecoration(labelText: 'Depth'),
                      keyboardType: TextInputType.number,
                      enabled: block.insertionMode == 'depth',
                      onChanged: (v) {
                        final d = int.tryParse(v);
                        onChanged(block.copyWith(depth: d));
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextFormField(
                initialValue: block.name,
                decoration: const InputDecoration(labelText: 'Block Name'),
                onChanged: (v) => onChanged(block.copyWith(name: v)),
              ),
              const SizedBox(height: 8),
              TextFormField(
                initialValue: block.content,
                decoration: const InputDecoration(labelText: 'Content'),
                maxLines: 4,
                minLines: 2,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                onChanged: (v) => onChanged(block.copyWith(content: v)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _roleChip() {
    final color = switch (block.role) {
      'system' => Colors.blue,
      'user' => Colors.green,
      'assistant' => Colors.orange,
      _ => Colors.grey,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        block.role,
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _appendBadge(BuildContext context) {
    return Tooltip(
      message: 'Appended to last user message',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          '↩ Last User',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.primary,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }
}
