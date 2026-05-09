import 'package:flutter/material.dart';

import '../../../core/models/preset.dart';
import '../../../shared/theme/app_colors.dart';

class RegexTile extends StatelessWidget {
  final PresetRegex regex;
  final ValueChanged<PresetRegex> onChanged;

  const RegexTile({super.key, required this.regex, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      key: ValueKey(regex.id),
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
            crossAxisAlignment: CrossAxisAlignment.start,
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
              const SizedBox(height: 8),
              TextFormField(
                initialValue: regex.trimOut,
                decoration: const InputDecoration(labelText: 'Trim output'),
                onChanged: (v) => onChanged(regex.copyWith(trimOut: v)),
              ),
              const SizedBox(height: 16),

              _SubHeader('Affects (Placement)'),
              _CheckboxRow(
                options: const [
                  (1, 'User Input'),
                  (2, 'AI Output'),
                  (4, 'World Info'),
                  (5, 'Reasoning'),
                ],
                selected: regex.placement,
                onChanged: (v) => onChanged(regex.copyWith(placement: v)),
              ),
              const SizedBox(height: 12),

              _SubHeader('Ephemerality'),
              _CheckboxRow(
                options: const [
                  (1, 'Alter Chat Display'),
                  (2, 'Alter Outgoing Prompt'),
                ],
                selected: regex.ephemerality,
                onChanged: (v) => onChanged(regex.copyWith(ephemerality: v)),
              ),
              const SizedBox(height: 12),

              _SubHeader('Depth Range'),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      initialValue: regex.minDepth?.toString() ?? '',
                      decoration: const InputDecoration(
                        labelText: 'Min Depth',
                        hintText: 'Unlimited',
                        isDense: true,
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (v) {
                        final n = int.tryParse(v);
                        onChanged(regex.copyWith(minDepth: n));
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      initialValue: regex.maxDepth?.toString() ?? '',
                      decoration: const InputDecoration(
                        labelText: 'Max Depth',
                        hintText: 'Unlimited',
                        isDense: true,
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (v) {
                        final n = int.tryParse(v);
                        onChanged(regex.copyWith(maxDepth: n));
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              _SubHeader('Macro Substitution'),
              _MacroRulesSelector(
                value: regex.macroRules,
                onChanged: (v) => onChanged(regex.copyWith(macroRules: v)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SubHeader extends StatelessWidget {
  final String text;
  const _SubHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.accent, letterSpacing: 0.4)),
    );
  }
}

class _CheckboxRow extends StatelessWidget {
  final List<(int, String)> options;
  final List<int> selected;
  final ValueChanged<List<int>> onChanged;

  const _CheckboxRow({required this.options, required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 0,
      runSpacing: 0,
      children: options.map((opt) {
        final (value, label) = opt;
        final isActive = selected.contains(value);
        return SizedBox(
          height: 36,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Checkbox(
                value: isActive,
                onChanged: (v) {
                  final newList = List<int>.from(selected);
                  if (v == true) {
                    if (!newList.contains(value)) newList.add(value);
                  } else {
                    newList.remove(value);
                  }
                  onChanged(newList);
                },
                activeColor: AppColors.accent,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              Text(label, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
              const SizedBox(width: 4),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _MacroRulesSelector extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _MacroRulesSelector({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    const options = [
      ('0', "Don't substitute"),
      ('1', 'Raw'),
      ('2', 'Escaped'),
    ];
    return Row(
      children: options.map((opt) {
        final (val, label) = opt;
        final isActive = value == val;
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            label: Text(label, style: TextStyle(fontSize: 12, color: isActive ? Colors.black : AppColors.textSecondary)),
            selected: isActive,
            onSelected: (_) => onChanged(val),
            selectedColor: AppColors.accent,
            visualDensity: VisualDensity.compact,
          ),
        );
      }).toList(),
    );
  }
}
