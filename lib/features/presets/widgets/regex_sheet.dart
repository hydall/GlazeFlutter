import 'package:flutter/material.dart';

import '../../../core/models/preset.dart';
import '../../../core/utils/id_generator.dart';
import '../../../shared/theme/app_colors.dart';
import 'regex_tile.dart';

/// Bottom-sheet body listing [PresetRegex] entries for a preset.
///
/// Shown via [GlazeBottomSheet.show] — not a full-screen route.
/// Any mutation is propagated immediately through [onChanged].
class RegexSheet extends StatefulWidget {
  final List<PresetRegex> regexes;
  final ValueChanged<List<PresetRegex>> onChanged;

  const RegexSheet({
    super.key,
    required this.regexes,
    required this.onChanged,
  });

  @override
  State<RegexSheet> createState() => _RegexSheetState();
}

class _RegexSheetState extends State<RegexSheet> {
  late final List<PresetRegex> _regexes = List.from(widget.regexes);

  void _addRegex() {
    setState(() {
      _regexes.add(PresetRegex(
        id: generateId(),
        name: 'Regex ${_regexes.length + 1}',
        regex: '',
      ));
    });
    widget.onChanged(_regexes);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Row(
            children: [
              Icon(Icons.code, size: 18, color: context.cs.primary),
              const SizedBox(width: 8),
              Text(
                'Regex Scripts',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: context.cs.onSurface,
                ),
              ),
              if (_regexes.isNotEmpty) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: context.cs.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${_regexes.length}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: context.cs.primary,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        Divider(color: context.cs.outline, height: 1),
        // List
        if (_regexes.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Center(
              child: Text(
                'No regex scripts',
                style: TextStyle(
                  color: context.cs.onSurfaceVariant.withValues(alpha: 0.6),
                  fontSize: 15,
                ),
              ),
            ),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _regexes.length,
            itemBuilder: (_, i) => Dismissible(
              key: ValueKey(_regexes[i].id),
              direction: DismissDirection.endToStart,
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 20),
                color: const Color(0xFFFF4444).withValues(alpha: 0.15),
                child: const Icon(Icons.delete, color: Color(0xFFFF4444)),
              ),
              onDismissed: (_) {
                setState(() => _regexes.removeAt(i));
                widget.onChanged(_regexes);
              },
              child: RegexTile(
                regex: _regexes[i],
                onChanged: (r) {
                  setState(() => _regexes[i] = r);
                  widget.onChanged(_regexes);
                },
              ),
            ),
          ),
        // Add regex button
        Padding(
          padding: const EdgeInsets.all(12),
          child: Material(
            color: context.cs.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: _addRegex,
              borderRadius: BorderRadius.circular(12),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Add Regex',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
