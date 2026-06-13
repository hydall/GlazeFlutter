import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../../../core/models/preset.dart';
import '../../../shared/theme/app_colors.dart';

class RegexTile extends StatelessWidget {
  final PresetRegex regex;
  final ValueChanged<PresetRegex> onChanged;

  const RegexTile({super.key, required this.regex, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return _SimpleExpansionTile(
      key: ValueKey(regex.id),
      header: Row(
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
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              initialValue: regex.name,
              decoration: InputDecoration(labelText: 'label_name'.tr()),
              onChanged: (v) => onChanged(regex.copyWith(name: v)),
            ),
            const SizedBox(height: 8),
            TextFormField(
              initialValue: regex.regex,
              decoration: InputDecoration(labelText: 'regex_find'.tr()),
              onChanged: (v) => onChanged(regex.copyWith(regex: v)),
            ),
            const SizedBox(height: 8),
            TextFormField(
              initialValue: regex.replacement,
              decoration: InputDecoration(labelText: 'regex_replace_with'.tr()),
              onChanged: (v) => onChanged(regex.copyWith(replacement: v)),
            ),
            const SizedBox(height: 8),
            TextFormField(
              initialValue: regex.trimOut,
              decoration: InputDecoration(labelText: 'regex_trim_out'.tr()),
              onChanged: (v) => onChanged(regex.copyWith(trimOut: v)),
            ),
            const SizedBox(height: 16),

            _SubHeader('regex_affects'.tr()),
            _CheckboxRow(
              options: [
                (1, 'regex_user_input'.tr()),
                (2, 'regex_ai_output'.tr()),
                (3, 'regex_slash_commands'.tr()),
                (5, 'regex_world_info'.tr()),
                (6, 'regex_reasoning'.tr()),
              ],
              selected: regex.placement,
              onChanged: (v) => onChanged(regex.copyWith(placement: v)),
            ),
            const SizedBox(height: 12),

            _SubHeader('regex_ephemerality'.tr()),
            _CheckboxRow(
              options: [
                (1, 'regex_alter_display'.tr()),
                (2, 'regex_alter_prompt'.tr()),
              ],
              selected: regex.ephemerality,
              onChanged: (v) => onChanged(regex.copyWith(ephemerality: v)),
            ),
            const SizedBox(height: 12),

            _SubHeader('regex_depth_range'.tr()),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: regex.minDepth?.toString() ?? '',
                    decoration: InputDecoration(
                      labelText: 'regex_min_depth'.tr(),
                      hintText: 'regex_unlimited_placeholder'.tr(),
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
                    decoration: InputDecoration(
                      labelText: 'regex_max_depth'.tr(),
                      hintText: 'regex_unlimited_placeholder'.tr(),
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

            _SubHeader('regex_macros_find'.tr()),
            _MacroRulesSelector(
              value: regex.macroRules,
              onChanged: (v) => onChanged(regex.copyWith(macroRules: v)),
            ),
            const SizedBox(height: 12),
            _SubHeader('regex_st_flags'.tr()),
            _FlagSwitch(
              label: 'regex_only_format_display'.tr(),
              value: regex.markdownOnly,
              onChanged: (v) => onChanged(regex.copyWith(markdownOnly: v)),
            ),
            _FlagSwitch(
              label: 'regex_only_format_prompt'.tr(),
              value: regex.promptOnly,
              onChanged: (v) => onChanged(regex.copyWith(promptOnly: v)),
            ),
            _FlagSwitch(
              label: 'regex_run_on_edit'.tr(),
              value: regex.runOnEdit,
              onChanged: (v) => onChanged(regex.copyWith(runOnEdit: v)),
            ),
            const SizedBox(height: 8),
            _SubHeader('regex_substitute_regex_header'.tr()),
            _SubstituteRegexSelector(
              value: regex.substituteRegex,
              onChanged: (v) => onChanged(regex.copyWith(substituteRegex: v)),
            ),
          ],
        ),
      ),
    );
  }
}

class _SimpleExpansionTile extends StatefulWidget {
  final Widget header;
  final Widget body;

  const _SimpleExpansionTile({super.key, required this.header, required this.body});

  @override
  State<_SimpleExpansionTile> createState() => _SimpleExpansionTileState();
}

class _SimpleExpansionTileState extends State<_SimpleExpansionTile>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _heightFactor;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _heightFactor = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() {
      _expanded = !_expanded;
      if (_expanded) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: _toggle,
          child: Row(
            children: [
              RotationTransition(
                turns: Tween(begin: 0.0, end: 0.25).animate(_controller),
                child: Icon(Icons.chevron_right, color: theme.iconTheme.color),
              ),
              Expanded(child: widget.header),
            ],
          ),
        ),
        ClipRect(
          child: AnimatedBuilder(
            animation: _heightFactor,
            builder: (context, child) {
              return Align(
                alignment: Alignment.topCenter,
                heightFactor: _heightFactor.value,
                child: child,
              );
            },
            child: widget.body,
          ),
        ),
        const Divider(height: 1),
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
      child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: context.cs.primary, letterSpacing: 0.4)),
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
                activeColor: context.cs.primary,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              Text(label, style: TextStyle(fontSize: 13, color: context.cs.onSurfaceVariant)),
              const SizedBox(width: 4),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _FlagSwitch extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _FlagSwitch({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(label, style: TextStyle(fontSize: 13, color: context.cs.onSurfaceVariant)),
      value: value,
      onChanged: onChanged,
    );
  }
}

class _SubstituteRegexSelector extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;

  const _SubstituteRegexSelector({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final options = [
      (0, 'regex_macro_none'.tr()),
      (1, 'regex_macro_raw'.tr()),
      (2, 'regex_macro_escaped'.tr()),
    ];
    return Wrap(
      spacing: 8,
      children: options.map((opt) {
        final (val, label) = opt;
        return ChoiceChip(
          selected: value == val,
          label: Text(label, style: TextStyle(fontSize: 12)),
          onSelected: (_) => onChanged(val),
          visualDensity: VisualDensity.compact,
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
    final options = [
      ('0', 'regex_macro_none'.tr()),
      ('1', 'regex_macro_raw'.tr()),
      ('2', 'regex_macro_escaped'.tr()),
    ];
    return Row(
      children: options.map((opt) {
        final (val, label) = opt;
        final isActive = value == val;
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            selected: isActive,
            label: Text(label, style: TextStyle(fontSize: 12, color: isActive ? Colors.black : context.cs.onSurfaceVariant)),
            onSelected: (_) => onChanged(val),
            selectedColor: context.cs.primary,
            visualDensity: VisualDensity.compact,
          ),
        );
      }).toList(),
    );
  }
}
