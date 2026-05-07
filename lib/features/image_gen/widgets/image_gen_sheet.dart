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

  void _update(ImageGenSettings s) {
    _settings = s;
    ref.read(imageGenSettingsProvider.notifier).save(s);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = _settings;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
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
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _ToggleRow(
                    label: 'Enabled',
                    value: s.enabled,
                    onChanged: (v) => _update(s.copyWith(enabled: v)),
                  ),
                  const SizedBox(height: 16),
                  const _SectionTitle('Provider'),
                  _ProviderSelector(
                    selected: s.apiType,
                    onChanged: (v) => _update(s.copyWith(apiType: v)),
                  ),
                  const SizedBox(height: 16),
                  ..._buildProviderFields(s),
                  const SizedBox(height: 16),
                  const _SectionTitle('Image Context'),
                  _ToggleRow(
                    label: 'Send recent images as context',
                    value: s.imageContextEnabled,
                    onChanged: (v) => _update(s.copyWith(imageContextEnabled: v)),
                  ),
                  if (s.imageContextEnabled)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        children: [
                          const Text('Context images:', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                          const SizedBox(width: 8),
                          SegmentedButton<int>(
                            segments: const [ButtonSegment(value: 1, label: Text('1')), ButtonSegment(value: 2, label: Text('2')), ButtonSegment(value: 3, label: Text('3'))],
                            selected: {s.imageContextCount},
                            onSelectionChanged: (v) => _update(s.copyWith(imageContextCount: v.first)),
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
          ),
        ],
      ),
    );
  }

  List<Widget> _buildProviderFields(ImageGenSettings s) {
    switch (s.apiType) {
      case ImageGenApiType.openai:
        return [
          _ToggleRow(
            label: 'Use LLM API endpoint',
            value: s.useSameEndpoint,
            onChanged: (v) => _update(s.copyWith(useSameEndpoint: v)),
          ),
          if (!s.useSameEndpoint) ...[
            _TextFieldRow(label: 'Endpoint', value: s.customEndpoint, onChanged: (v) => _update(s.copyWith(customEndpoint: v))),
            _TextFieldRow(label: 'API Key', value: s.customApiKey, obscure: true, onChanged: (v) => _update(s.copyWith(customApiKey: v))),
            _TextFieldRow(label: 'Model', value: s.customModel, hint: 'dall-e-3', onChanged: (v) => _update(s.copyWith(customModel: v))),
          ],
          _DropdownRow(label: 'Size', value: s.openaiSize, items: OpenAIConstants.sizes, onChanged: (v) => _update(s.copyWith(openaiSize: v))),
          _DropdownRow(label: 'Quality', value: s.openaiQuality, items: OpenAIConstants.qualities, onChanged: (v) => _update(s.copyWith(openaiQuality: v))),
        ];
      case ImageGenApiType.gemini:
        return [
          _ToggleRow(
            label: 'Use LLM API endpoint',
            value: s.useSameEndpoint,
            onChanged: (v) => _update(s.copyWith(useSameEndpoint: v)),
          ),
          if (!s.useSameEndpoint) ...[
            _TextFieldRow(label: 'Endpoint', value: s.customEndpoint, onChanged: (v) => _update(s.copyWith(customEndpoint: v))),
            _TextFieldRow(label: 'API Key', value: s.customApiKey, obscure: true, onChanged: (v) => _update(s.copyWith(customApiKey: v))),
            _TextFieldRow(label: 'Model', value: s.customModel, hint: 'imagen-3.0-generate-002', onChanged: (v) => _update(s.copyWith(customModel: v))),
          ],
          _DropdownRow(label: 'Aspect Ratio', value: s.geminiAspectRatio, items: GeminiConstants.aspectRatios, onChanged: (v) => _update(s.copyWith(geminiAspectRatio: v))),
          _DropdownRow(label: 'Image Size', value: s.geminiImageSize, items: GeminiConstants.imageSizes, onChanged: (v) => _update(s.copyWith(geminiImageSize: v))),
        ];
      case ImageGenApiType.naistera:
        return [
          _TextFieldRow(label: 'API Key', value: s.naisteraApiKey, obscure: true, onChanged: (v) => _update(s.copyWith(naisteraApiKey: v))),
          _DropdownRow(
            label: 'Model',
            value: s.naisteraModel,
            items: NaisteraConstants.models.map((e) => e.$1).toList(),
            labels: NaisteraConstants.models.map((e) => e.$2).toList(),
            onChanged: (v) => _update(s.copyWith(naisteraModel: v)),
          ),
          _DropdownRow(label: 'Aspect Ratio', value: s.naisteraAspectRatio, items: NaisteraConstants.aspectRatios, onChanged: (v) => _update(s.copyWith(naisteraAspectRatio: v))),
          _ToggleRow(label: 'Send character avatar', value: s.naisteraSendCharAvatar, onChanged: (v) => _update(s.copyWith(naisteraSendCharAvatar: v))),
          _ToggleRow(label: 'Send persona avatar', value: s.naisteraSendUserAvatar, onChanged: (v) => _update(s.copyWith(naisteraSendUserAvatar: v))),
        ];
      case ImageGenApiType.routmy:
        return [
          _TextFieldRow(label: 'API Key', value: s.routmyApiKey, obscure: true, onChanged: (v) => _update(s.copyWith(routmyApiKey: v))),
          _DropdownRow(
            label: 'Model',
            value: s.routmyModel,
            items: RoutMyConstants.models.map((e) => e.$1).toList(),
            labels: RoutMyConstants.models.map((e) => e.$2).toList(),
            onChanged: (v) => _update(s.copyWith(routmyModel: v)),
          ),
          _DropdownRow(label: 'Aspect Ratio', value: s.routmyAspectRatio, items: RoutMyConstants.aspectRatios, onChanged: (v) => _update(s.copyWith(routmyAspectRatio: v))),
          _DropdownRow(label: 'Image Size', value: s.routmyImageSize, items: RoutMyConstants.imageSizes, onChanged: (v) => _update(s.copyWith(routmyImageSize: v))),
          _DropdownRow(label: 'Quality', value: s.routmyQuality, items: ['standard', 'hd'], onChanged: (v) => _update(s.copyWith(routmyQuality: v))),
          _ToggleRow(label: 'Send character avatar', value: s.routmySendCharAvatar, onChanged: (v) => _update(s.copyWith(routmySendCharAvatar: v))),
          _ToggleRow(label: 'Send persona avatar', value: s.routmySendUserAvatar, onChanged: (v) => _update(s.copyWith(routmySendUserAvatar: v))),
        ];
      case ImageGenApiType.ruRoutmy:
        return [
          _TextFieldRow(label: 'API Key', value: s.ruRoutmyApiKey, obscure: true, onChanged: (v) => _update(s.copyWith(ruRoutmyApiKey: v))),
          _DropdownRow(
            label: 'Model',
            value: s.ruRoutmyModel,
            items: RuRoutMyConstants.models.map((e) => e.$1).toList(),
            labels: RuRoutMyConstants.models.map((e) => e.$2).toList(),
            onChanged: (v) => _update(s.copyWith(ruRoutmyModel: v)),
          ),
          _DropdownRow(label: 'Aspect Ratio', value: s.ruRoutmyAspectRatio, items: RuRoutMyConstants.aspectRatios, onChanged: (v) => _update(s.copyWith(ruRoutmyAspectRatio: v))),
          _DropdownRow(label: 'Image Size', value: s.ruRoutmyImageSize, items: RuRoutMyConstants.imageSizes, onChanged: (v) => _update(s.copyWith(ruRoutmyImageSize: v))),
          _DropdownRow(label: 'Quality', value: s.ruRoutmyQuality, items: ['standard', 'hd'], onChanged: (v) => _update(s.copyWith(ruRoutmyQuality: v))),
          _ToggleRow(label: 'Send character avatar', value: s.ruRoutmySendCharAvatar, onChanged: (v) => _update(s.copyWith(ruRoutmySendCharAvatar: v))),
          _ToggleRow(label: 'Send persona avatar', value: s.ruRoutmySendUserAvatar, onChanged: (v) => _update(s.copyWith(ruRoutmySendUserAvatar: v))),
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
  void didUpdateWidget(covariant _TextFieldRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value && widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

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
      (ImageGenApiType.ruRoutmy, 'RU-RoutMy', Icons.public),
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
