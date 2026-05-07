import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/state/active_selection_provider.dart';
import '../../../shared/theme/app_colors.dart';

class GenerationOverridesSheet extends ConsumerStatefulWidget {
  const GenerationOverridesSheet({super.key});

  @override
  ConsumerState<GenerationOverridesSheet> createState() =>
      _GenerationOverridesSheetState();
}

class _GenerationOverridesSheetState
    extends ConsumerState<GenerationOverridesSheet> {
  late double _temperature;
  late double _topP;
  late bool _requestReasoning;
  late String _reasoningEffort;
  bool _temperatureOverridden = false;
  bool _topPOverridden = false;

  static const _efforts = ['auto', 'low', 'medium', 'high'];

  @override
  void initState() {
    super.initState();
    final overrides = ref.read(generationOverridesProvider);
    _temperature = overrides.temperature ?? 0.7;
    _topP = overrides.topP ?? 0.9;
    _requestReasoning = overrides.requestReasoning ?? false;
    _reasoningEffort = overrides.reasoningEffort ?? 'medium';
    _temperatureOverridden = overrides.temperature != null;
    _topPOverridden = overrides.topP != null;
  }

  void _apply() {
    ref.read(generationOverridesProvider.notifier).state = GenerationOverrides(
      temperature: _temperatureOverridden ? _temperature : null,
      topP: _topPOverridden ? _topP : null,
      requestReasoning: _requestReasoning ? true : null,
      reasoningEffort: _requestReasoning ? _reasoningEffort : null,
    );
    Navigator.pop(context);
  }

  void _reset() {
    ref.read(generationOverridesProvider.notifier).state =
        const GenerationOverrides.empty();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Generation Overrides',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _OverrideSlider(
            label: 'Temperature',
            value: _temperature,
            min: 0,
            max: 2,
            overridden: _temperatureOverridden,
            onOverrideChanged: (v) =>
                setState(() => _temperatureOverridden = v),
            onChanged: (v) => setState(() => _temperature = v),
          ),
          const SizedBox(height: 12),
          _OverrideSlider(
            label: 'Top P',
            value: _topP,
            min: 0,
            max: 1,
            overridden: _topPOverridden,
            onOverrideChanged: (v) => setState(() => _topPOverridden = v),
            onChanged: (v) => setState(() => _topP = v),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text('Reasoning', style: TextStyle(fontSize: 14)),
              const Spacer(),
              Switch(
                value: _requestReasoning,
                onChanged: (v) => setState(() => _requestReasoning = v),
                activeColor: AppColors.accent,
              ),
            ],
          ),
          if (_requestReasoning) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Text('Effort:', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                const SizedBox(width: 8),
                ..._efforts.map((e) => Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(e, style: const TextStyle(fontSize: 12)),
                        selected: _reasoningEffort == e,
                        onSelected: (_) =>
                            setState(() => _reasoningEffort = e),
                        visualDensity: VisualDensity.compact,
                      ),
                    )),
              ],
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              TextButton(
                onPressed: _reset,
                child: const Text('Reset'),
              ),
              const Spacer(),
              FilledButton(
                onPressed: _apply,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.black,
                ),
                child: const Text('Apply'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OverrideSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final bool overridden;
  final ValueChanged<bool> onOverrideChanged;
  final ValueChanged<double> onChanged;

  const _OverrideSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.overridden,
    required this.onOverrideChanged,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: overridden ? 1.0 : 0.4,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Checkbox(
                value: overridden,
                onChanged: (v) => onOverrideChanged(v ?? false),
                activeColor: AppColors.accent,
              ),
              Text(label, style: const TextStyle(fontSize: 14)),
              const Spacer(),
              Text(
                value.toStringAsFixed(2),
                style: TextStyle(
                  fontSize: 14,
                  color: overridden ? AppColors.accent : AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          Slider(
            value: value,
            min: min,
            max: max,
            onChanged: overridden ? onChanged : null,
            activeColor: AppColors.accent,
          ),
        ],
      ),
    );
  }
}
