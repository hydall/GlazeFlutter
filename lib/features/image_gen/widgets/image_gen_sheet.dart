import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/theme/app_colors.dart';
import '../image_gen_models.dart';
import '../image_gen_provider.dart';

class ImageGenSheet extends ConsumerStatefulWidget {
  const ImageGenSheet({super.key});

  @override
  ConsumerState<ImageGenSheet> createState() => _ImageGenSheetState();
}

class _ImageGenSheetState extends ConsumerState<ImageGenSheet> {
  late ImageGenSettings _settings;

  @override
  void initState() {
    super.initState();
    _settings = ref.read(imageGenSettingsProvider).value ?? const ImageGenSettings();
  }

  Future<void> _save() async {
    await ref.read(imageGenSettingsProvider.notifier).save(_settings);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
              child: Row(
                children: [
                  const Text('Image Generation', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => Navigator.pop(context)),
                ],
              ),
            ),
            const Divider(height: 1, color: Colors.white10),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.all(16),
                children: [
                  _ToggleRow(
                    label: 'Enabled',
                    value: _settings.enabled,
                    onChanged: (v) => setState(() { _settings = _settings.copyWith(enabled: v); _save(); }),
                  ),
                  const SizedBox(height: 16),
                  _SectionTitle('Provider'),
                  _ProviderSelector(
                    selected: _settings.apiType,
                    onChanged: (v) => setState(() { _settings = _settings.copyWith(apiType: v); _save(); }),
                  ),
                  const SizedBox(height: 16),
                  ..._buildProviderFields(),
                  const SizedBox(height: 16),
                  _SectionTitle('Image Context'),
                  _ToggleRow(
                    label: 'Send recent images as context',
                    value: _settings.imageContextEnabled,
                    onChanged: (v) => setState(() { _settings = _settings.copyWith(imageContextEnabled: v); _save(); }),
                  ),
                  if (_settings.imageContextEnabled)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        children: [
                          const Text('Context images:', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                          const SizedBox(width: 8),
                          SegmentedButton<int>(
                            segments: const [ButtonSegment(value: 1, label: Text('1')), ButtonSegment(value: 2, label: Text('2')), ButtonSegment(value: 3, label: Text('3'))],
                            selected: {_settings.imageContextCount},
                            onSelectionChanged: (v) => setState(() { _settings = _settings.copyWith(imageContextCount: v.first); _save(); }),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.04), borderRadius: BorderRadius.circular(8)),
                    child: const Text(
                      'Tip: Add [IMG:GEN:{"prompt":"..."}] to a message or system prompt to trigger auto-generation.',
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildProviderFields() {
    switch (_settings.apiType) {
      case ImageGenApiType.openai:
        return [
          _ToggleRow(
            label: 'Use LLM API endpoint',
            value: _settings.useSameEndpoint,
            onChanged: (v) => setState(() { _settings = _settings.copyWith(useSameEndpoint: v); _save(); }),
          ),
          if (!_settings.useSameEndpoint) ...[
            _TextFieldRow(label: 'Endpoint', value: _settings.customEndpoint, onChanged: (v) { _settings = _settings.copyWith(customEndpoint: v); _save(); }),
            _TextFieldRow(label: 'API Key', value: _settings.customApiKey, obscure: true, onChanged: (v) { _settings = _settings.copyWith(customApiKey: v); _save(); }),
            _TextFieldRow(label: 'Model', value: _settings.customModel, hint: 'dall-e-3', onChanged: (v) { _settings = _settings.copyWith(customModel: v); _save(); }),
          ],
          _DropdownRow(label: 'Size', value: _settings.openaiSize, items: OpenAIConstants.sizes, onChanged: (v) { _settings = _settings.copyWith(openaiSize: v); _save(); }),
          _DropdownRow(label: 'Quality', value: _settings.openaiQuality, items: OpenAIConstants.qualities, onChanged: (v) { _settings = _settings.copyWith(openaiQuality: v); _save(); }),
        ];
      case ImageGenApiType.gemini:
        return [
          _ToggleRow(
            label: 'Use LLM API endpoint',
            value: _settings.useSameEndpoint,
            onChanged: (v) => setState(() { _settings = _settings.copyWith(useSameEndpoint: v); _save(); }),
          ),
          if (!_settings.useSameEndpoint) ...[
            _TextFieldRow(label: 'Endpoint', value: _settings.customEndpoint, onChanged: (v) { _settings = _settings.copyWith(customEndpoint: v); _save(); }),
            _TextFieldRow(label: 'API Key', value: _settings.customApiKey, obscure: true, onChanged: (v) { _settings = _settings.copyWith(customApiKey: v); _save(); }),
            _TextFieldRow(label: 'Model', value: _settings.customModel, hint: 'imagen-3.0-generate-002', onChanged: (v) { _settings = _settings.copyWith(customModel: v); _save(); }),
          ],
          _DropdownRow(label: 'Aspect Ratio', value: _settings.geminiAspectRatio, items: GeminiConstants.aspectRatios, onChanged: (v) { _settings = _settings.copyWith(geminiAspectRatio: v); _save(); }),
          _DropdownRow(label: 'Image Size', value: _settings.geminiImageSize, items: GeminiConstants.imageSizes, onChanged: (v) { _settings = _settings.copyWith(geminiImageSize: v); _save(); }),
        ];
      case ImageGenApiType.naistera:
        return [
          _TextFieldRow(label: 'API Key', value: _settings.naisteraApiKey, obscure: true, onChanged: (v) { _settings = _settings.copyWith(naisteraApiKey: v); _save(); }),
          _DropdownRow(
            label: 'Model',
            value: _settings.naisteraModel,
            items: NaisteraConstants.models.map((e) => e.$1).toList(),
            labels: NaisteraConstants.models.map((e) => e.$2).toList(),
            onChanged: (v) { _settings = _settings.copyWith(naisteraModel: v); _save(); },
          ),
          _DropdownRow(label: 'Aspect Ratio', value: _settings.naisteraAspectRatio, items: NaisteraConstants.aspectRatios, onChanged: (v) { _settings = _settings.copyWith(naisteraAspectRatio: v); _save(); }),
          _ToggleRow(label: 'Send character avatar', value: _settings.naisteraSendCharAvatar, onChanged: (v) { _settings = _settings.copyWith(naisteraSendCharAvatar: v); _save(); }),
          _ToggleRow(label: 'Send persona avatar', value: _settings.naisteraSendUserAvatar, onChanged: (v) { _settings = _settings.copyWith(naisteraSendUserAvatar: v); _save(); }),
        ];
      case ImageGenApiType.routmy:
        return [
          _TextFieldRow(label: 'API Key', value: _settings.routmyApiKey, obscure: true, onChanged: (v) { _settings = _settings.copyWith(routmyApiKey: v); _save(); }),
          _DropdownRow(
            label: 'Model',
            value: _settings.routmyModel,
            items: RoutMyConstants.models.map((e) => e.$1).toList(),
            labels: RoutMyConstants.models.map((e) => e.$2).toList(),
            onChanged: (v) { _settings = _settings.copyWith(routmyModel: v); _save(); },
          ),
          _DropdownRow(label: 'Aspect Ratio', value: _settings.routmyAspectRatio, items: RoutMyConstants.aspectRatios, onChanged: (v) { _settings = _settings.copyWith(routmyAspectRatio: v); _save(); }),
          _DropdownRow(label: 'Image Size', value: _settings.routmyImageSize, items: RoutMyConstants.imageSizes, onChanged: (v) { _settings = _settings.copyWith(routmyImageSize: v); _save(); }),
          _DropdownRow(label: 'Quality', value: _settings.routmyQuality, items: ['standard', 'hd'], onChanged: (v) { _settings = _settings.copyWith(routmyQuality: v); _save(); }),
          _ToggleRow(label: 'Send character avatar', value: _settings.routmySendCharAvatar, onChanged: (v) { _settings = _settings.copyWith(routmySendCharAvatar: v); _save(); }),
          _ToggleRow(label: 'Send persona avatar', value: _settings.routmySendUserAvatar, onChanged: (v) { _settings = _settings.copyWith(routmySendUserAvatar: v); _save(); }),
        ];
    }
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
  );
}

class _ToggleRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _ToggleRow({required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
      Switch(value: value, onChanged: onChanged, activeThumbColor: AppColors.accent),
    ],
  );
}

class _TextFieldRow extends StatefulWidget {
  final String label;
  final String value;
  final bool obscure;
  final String? hint;
  final ValueChanged<String> onChanged;
  const _TextFieldRow({required this.label, required this.value, this.obscure = false, this.hint, required this.onChanged});

  @override
  State<_TextFieldRow> createState() => _TextFieldRowState();
}

class _TextFieldRowState extends State<_TextFieldRow> {
  late final _controller = TextEditingController(text: widget.value);
  bool _obscure = true;

  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        SizedBox(width: 100, child: Text(widget.label, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary))),
        Expanded(
          child: TextField(
            controller: _controller,
            obscureText: widget.obscure && _obscure,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              hintText: widget.hint,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              suffixIcon: widget.obscure
                  ? IconButton(icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility, size: 18), onPressed: () => setState(() => _obscure = !_obscure))
                  : null,
            ),
            onChanged: widget.onChanged,
          ),
        ),
      ],
    ),
  );
}

class _DropdownRow extends StatelessWidget {
  final String label;
  final String value;
  final List<String> items;
  final List<String>? labels;
  final ValueChanged<String> onChanged;
  const _DropdownRow({required this.label, required this.value, required this.items, this.labels, required this.onChanged});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        SizedBox(width: 100, child: Text(label, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary))),
        Expanded(
          child: DropdownButton<String>(
            value: items.contains(value) ? value : items.first,
            isExpanded: true,
            underline: const SizedBox.shrink(),
            items: List.generate(items.length, (i) => DropdownMenuItem(value: items[i], child: Text(labels != null ? labels![i] : items[i], style: const TextStyle(fontSize: 14)))),
            onChanged: (v) { if (v != null) onChanged(v); },
          ),
        ),
      ],
    ),
  );
}

class _ProviderSelector extends StatelessWidget {
  final ImageGenApiType selected;
  final ValueChanged<ImageGenApiType> onChanged;
  const _ProviderSelector({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final providers = [
      (ImageGenApiType.openai, 'OpenAI', Icons.smart_toy),
      (ImageGenApiType.gemini, 'Gemini', Icons.auto_awesome),
      (ImageGenApiType.naistera, 'Naistera', Icons.palette),
      (ImageGenApiType.routmy, 'RoutMy', Icons.route),
    ];
    return Wrap(
      spacing: 8,
      children: providers.map((p) {
        final isSelected = selected == p.$1;
        return GestureDetector(
          onTap: () => onChanged(p.$1),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected ? AppColors.accent.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: isSelected ? AppColors.accent : Colors.white.withValues(alpha: 0.1)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(p.$3, size: 16, color: isSelected ? AppColors.accent : AppColors.textSecondary),
              const SizedBox(width: 6),
              Text(p.$2, style: TextStyle(fontSize: 13, color: isSelected ? AppColors.accent : AppColors.textSecondary, fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal)),
            ]),
          ),
        );
      }).toList(),
    );
  }
}
