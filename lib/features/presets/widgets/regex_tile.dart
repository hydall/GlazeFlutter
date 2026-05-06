import 'package:flutter/material.dart';

import '../../../core/models/preset.dart';

class RegexTile extends StatelessWidget {
  final PresetRegex regex;
  final ValueChanged<PresetRegex> onChanged;

  const RegexTile({super.key, required this.regex, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      title: Row(
        children: [
          Switch(
            value: !regex.disabled,
            onChanged: (v) => onChanged(regex.copyWith(disabled: !v)),
          ),
          Expanded(
            child: Text(
              regex.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(
            children: [
              TextFormField(
                initialValue: regex.name,
                decoration: const InputDecoration(labelText: 'Name'),
                onChanged: (v) => onChanged(regex.copyWith(name: v)),
              ),
              const SizedBox(height: 8),
              TextFormField(
                initialValue: regex.regex,
                decoration: const InputDecoration(labelText: 'Find (regex)'),
                onChanged: (v) => onChanged(regex.copyWith(regex: v)),
              ),
              const SizedBox(height: 8),
              TextFormField(
                initialValue: regex.replacement,
                decoration: const InputDecoration(labelText: 'Replace with'),
                onChanged: (v) => onChanged(regex.copyWith(replacement: v)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
