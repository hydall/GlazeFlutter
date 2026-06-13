import 'package:easy_localization/easy_localization.dart';
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
                      decoration: InputDecoration(labelText: 'label_role'.tr()),
                      items: [
                        DropdownMenuItem(value: 'system', child: Text('role_system'.tr())),
                        DropdownMenuItem(value: 'user', child: Text('role_user'.tr())),
                        DropdownMenuItem(value: 'assistant', child: Text('role_assistant'.tr())),
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
                      decoration: InputDecoration(labelText: 'label_insertion_strategy'.tr()),
                      items: [
                        DropdownMenuItem(value: 'relative', child: Text('injection_relative'.tr())),
                        DropdownMenuItem(value: 'depth', child: Text('label_depth'.tr())),
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
                      decoration: InputDecoration(labelText: 'label_depth'.tr()),
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
                decoration: InputDecoration(labelText: 'label_block_name'.tr()),
                onChanged: (v) => onChanged(block.copyWith(name: v)),
              ),
              const SizedBox(height: 8),
              TextFormField(
                initialValue: block.content,
                decoration: InputDecoration(labelText: 'label_content'.tr()),
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
      message: 'block_append_to_last_user'.tr(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          'block_append_badge'.tr(),
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
