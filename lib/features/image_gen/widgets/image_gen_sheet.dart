import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/theme/app_colors.dart';
import '../../../shared/widgets/help_tip.dart';
import '../../../shared/widgets/sheet_view.dart';
import '../image_gen_models.dart';
import '../image_gen_provider.dart';

class ImageGenSheet extends ConsumerStatefulWidget {
  const ImageGenSheet({super.key});

  @override
  ConsumerState<ImageGenSheet> createState() => _ImageGenSheetState();
}

class _ImageGenSheetState extends ConsumerState<ImageGenSheet> {
  late ImageGenSettings _settings;
  bool _isFetchingModels = false;

  @override
  void initState() {
    super.initState();
    _settings =
        ref.read(imageGenSettingsProvider).value ?? const ImageGenSettings();
  }

  void _update(ImageGenSettings s) {
    _settings = s;
    ref.read(imageGenSettingsProvider.notifier).save(s);
    if (mounted) setState(() {});
  }

  void _showOptionsSheet<T>({
    required String title,
    required List<T> items,
    required String Function(T) labelBuilder,
    required bool Function(T) isSelected,
    required void Function(T) onSelected,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: context.cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: items.length,
                itemBuilder: (context, i) {
                  final item = items[i];
                  final selected = isSelected(item);
                  return ListTile(
                    title: Text(labelBuilder(item)),
                    trailing: selected
                        ? Text(
                            'Active',
                            style: TextStyle(
                              fontSize: 12,
                              color: context.cs.primary,
                            ),
                          )
                        : null,
                    onTap: () {
                      Navigator.pop(context);
                      onSelected(item);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openApiTypeSelector() {
    _showOptionsSheet<ImageGenApiType>(
      title: 'API Type',
      items: ImageGenApiType.values,
      labelBuilder: (t) => switch (t) {
        ImageGenApiType.openai => 'OpenAI',
        ImageGenApiType.gemini => 'Gemini',
        ImageGenApiType.naistera => 'Naistera',
        ImageGenApiType.routmy => 'rout.my',
        ImageGenApiType.ruRoutmy => 'RU-rout.my',
      },
      isSelected: (t) => _settings.apiType == t,
      onSelected: (t) => _update(_settings.copyWith(apiType: t)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = _settings;

    return SheetView(
      titleWidget: Row(
        children: [
          const Text(
            'Image Generation',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const HelpTip(term: 'image-gen'),
          const Spacer(),
          Switch(
            value: s.enabled,
            onChanged: (v) => _update(s.copyWith(enabled: v)),
          ),
        ],
      ),
      headerBottom: Align(
        alignment: Alignment.centerLeft,
        child: _buildPresetSelector(s.apiType),
      ),
      fitContent: false,
      body: s.enabled ? _buildBody(context, s) : const SizedBox.shrink(),
    );
  }

  Widget _buildBody(BuildContext context, ImageGenSettings s) {
    return Builder(
      builder: (context) => SingleChildScrollView(
        padding: EdgeInsets.only(
          top: MediaQuery.paddingOf(context).top + 16,
          bottom: MediaQuery.paddingOf(context).bottom + 24,
        ),
        child: Column(
          children: [
            _MenuGroup(
              title: 'Connection',
              children: _buildConnectionFields(s),
            ),
            _MenuGroup(title: 'Model', children: _buildModelFields(s)),
            if (s.apiType == ImageGenApiType.naistera &&
                NaisteraConstants.noRefModels.contains(s.naisteraModel))
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.05),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    'imggen_no_refs_hint'.tr(),
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            if ((s.apiType == ImageGenApiType.naistera &&
                    !NaisteraConstants.noRefModels.contains(s.naisteraModel)) ||
                s.apiType == ImageGenApiType.routmy ||
                s.apiType == ImageGenApiType.ruRoutmy)
              ..._buildReferences(s),
            if (s.apiType != ImageGenApiType.naistera ||
                !NaisteraConstants.noRefModels.contains(s.naisteraModel))
              _MenuGroup(
                title: 'Image Context',
                children: [
                  _CheckboxRow(
                    label: 'Send previous images as context',
                    description:
                        'Include recently generated images as visual reference for new generations',
                    value: s.imageContextEnabled,
                    onChanged: (v) =>
                        _update(s.copyWith(imageContextEnabled: v)),
                  ),
                  if (s.imageContextEnabled)
                    _SelectorRow(
                      label: 'Context image count',
                      value: s.imageContextCount.toString(),
                      onTap: () {
                        _showOptionsSheet<int>(
                          title: 'Context image count',
                          items: [1, 2, 3],
                          labelBuilder: (i) => i.toString(),
                          isSelected: (i) => s.imageContextCount == i,
                          onSelected: (i) =>
                              _update(s.copyWith(imageContextCount: i)),
                        );
                      },
                    ),
                ],
              ),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: context.cs.surfaceContainerHighest.withValues(
                  alpha: 0.8,
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'AI must include image tags to trigger generation:',
                    style: TextStyle(
                      fontSize: 13,
                      color: context.cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '[IMG:GEN:{"prompt":"...","style":"anime"}]',
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: context.cs.primary,
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

  Widget _buildPresetSelector(ImageGenApiType selected) {
    final name = switch (selected) {
      ImageGenApiType.openai => 'OpenAI',
      ImageGenApiType.gemini => 'Gemini',
      ImageGenApiType.naistera => 'Naistera',
      ImageGenApiType.routmy => 'rout.my',
      ImageGenApiType.ruRoutmy => 'RU-rout.my',
    };
    return InkWell(
      onTap: _openApiTypeSelector,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: context.cs.primary.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.cs.primary.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              name,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: context.cs.primary,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.keyboard_arrow_down,
              size: 20,
              color: context.cs.primary,
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildConnectionFields(ImageGenSettings s) {
    if (s.apiType == ImageGenApiType.naistera) {
      return [
        _TextFieldItem(
          label: 'API Key',
          value: s.naisteraApiKey,
          obscure: true,
          hint: 'sk-...',
          onChanged: (v) => _update(s.copyWith(naisteraApiKey: v)),
        ),
        InkWell(
          onTap: () {},
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
            ),
            child: const Row(
              children: [
                Text('Learn about Naistera', style: TextStyle(fontSize: 13)),
                SizedBox(width: 4),
                Icon(Icons.public, size: 14, color: Colors.blue),
                SizedBox(width: 4),
                Text(
                  'here',
                  style: TextStyle(fontSize: 13, color: Colors.blue),
                ),
              ],
            ),
          ),
        ),
      ];
    } else if (s.apiType == ImageGenApiType.routmy) {
      return [
        _TextFieldItem(
          label: 'rout.my API Key',
          value: s.routmyApiKey,
          obscure: true,
          hint: 'sk-...',
          onChanged: (v) => _update(s.copyWith(routmyApiKey: v)),
        ),
      ];
    } else if (s.apiType == ImageGenApiType.ruRoutmy) {
      return [
        _TextFieldItem(
          label: 'RU-rout.my API Key',
          value: s.ruRoutmyApiKey,
          obscure: true,
          hint: 'sk-...',
          onChanged: (v) => _update(s.copyWith(ruRoutmyApiKey: v)),
        ),
      ];
    } else {
      return [
        _CheckboxRow(
          label: 'Use LLM API',
          description: 'Use the same endpoint as LLM for image generation',
          value: s.useSameEndpoint,
          onChanged: (v) => _update(s.copyWith(useSameEndpoint: v)),
        ),
        if (!s.useSameEndpoint) ...[
          _TextFieldItem(
            label: 'Endpoint URL',
            value: s.customEndpoint,
            hint: 'https://api.openai.com/v1',
            onChanged: (v) => _update(s.copyWith(customEndpoint: v)),
          ),
          _TextFieldItem(
            label: 'API Key',
            value: s.customApiKey,
            obscure: true,
            hint: 'sk-...',
            onChanged: (v) => _update(s.copyWith(customApiKey: v)),
          ),
        ],
      ];
    }
  }

  List<Widget> _buildModelFields(ImageGenSettings s) {
    if (s.apiType == ImageGenApiType.naistera) {
      return [
        _SelectorRow(
          label: 'Model',
          value: NaisteraConstants.models
              .firstWhere(
                (e) => e.$1 == s.naisteraModel,
                orElse: () => (s.naisteraModel, s.naisteraModel),
              )
              .$2,
          onTap: () => _showOptionsSheet<String>(
            title: 'Model',
            items: NaisteraConstants.models.map((e) => e.$1).toList(),
            labelBuilder: (v) =>
                NaisteraConstants.models.firstWhere((e) => e.$1 == v).$2,
            isSelected: (v) => s.naisteraModel == v,
            onSelected: (v) => _update(s.copyWith(naisteraModel: v)),
          ),
        ),
        _SelectorRow(
          label: 'Aspect Ratio',
          value: s.naisteraAspectRatio,
          onTap: () => _showOptionsSheet<String>(
            title: 'Aspect Ratio',
            items: NaisteraConstants.aspectRatios,
            labelBuilder: (v) => v,
            isSelected: (v) => s.naisteraAspectRatio == v,
            onSelected: (v) => _update(s.copyWith(naisteraAspectRatio: v)),
          ),
        ),
      ];
    } else if (s.apiType == ImageGenApiType.routmy ||
        s.apiType == ImageGenApiType.ruRoutmy) {
      final isRu = s.apiType == ImageGenApiType.ruRoutmy;
      final model = isRu ? s.ruRoutmyModel : s.routmyModel;
      final aspect = isRu ? s.ruRoutmyAspectRatio : s.routmyAspectRatio;
      final size = isRu ? s.ruRoutmyImageSize : s.routmyImageSize;
      final quality = isRu ? s.ruRoutmyQuality : s.routmyQuality;
      final constantsModels = RoutMyConstants.models;

      return [
        _SelectorRow(
          label: 'Model',
          value: constantsModels
              .firstWhere((e) => e.$1 == model, orElse: () => (model, model))
              .$2,
          onTap: () => _showOptionsSheet<String>(
            title: 'Model',
            items: constantsModels.map((e) => e.$1).toList(),
            labelBuilder: (v) =>
                constantsModels.firstWhere((e) => e.$1 == v).$2,
            isSelected: (v) => model == v,
            onSelected: (v) => isRu
                ? _update(s.copyWith(ruRoutmyModel: v))
                : _update(s.copyWith(routmyModel: v)),
          ),
        ),
        _SelectorRow(
          label: 'Aspect Ratio',
          value: aspect,
          onTap: () => _showOptionsSheet<String>(
            title: 'Aspect Ratio',
            items: RoutMyConstants.aspectRatios,
            labelBuilder: (v) => v,
            isSelected: (v) => aspect == v,
            onSelected: (v) => isRu
                ? _update(s.copyWith(ruRoutmyAspectRatio: v))
                : _update(s.copyWith(routmyAspectRatio: v)),
          ),
        ),
        _SelectorRow(
          label: 'Resolution',
          value: size,
          onTap: () => _showOptionsSheet<String>(
            title: 'Resolution',
            items: RoutMyConstants.imageSizes,
            labelBuilder: (v) => v,
            isSelected: (v) => size == v,
            onSelected: (v) => isRu
                ? _update(s.copyWith(ruRoutmyImageSize: v))
                : _update(s.copyWith(routmyImageSize: v)),
          ),
        ),
        _SelectorRow(
          label: 'Quality',
          value: quality == 'hd' ? 'HD' : 'Standard',
          onTap: () => _showOptionsSheet<String>(
            title: 'Quality',
            items: ['standard', 'hd'],
            labelBuilder: (v) => v == 'hd' ? 'HD' : 'Standard',
            isSelected: (v) => quality == v,
            onSelected: (v) => isRu
                ? _update(s.copyWith(ruRoutmyQuality: v))
                : _update(s.copyWith(routmyQuality: v)),
          ),
        ),
      ];
    } else if (s.apiType == ImageGenApiType.openai) {
      return [
        _TextFieldItem(
          label: 'Model',
          value: s.customModel,
          hint: 'dall-e-3',
          onChanged: (v) => _update(s.copyWith(customModel: v)),
          suffix: InkWell(
            onTap: () async {
              setState(() {
                _isFetchingModels = true;
              });
              await Future<void>.delayed(const Duration(seconds: 1));
              setState(() {
                _isFetchingModels = false;
              });
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: context.cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.black12),
              ),
              child: _isFetchingModels
                  ? const Center(
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : Icon(Icons.refresh, size: 18, color: context.cs.primary),
            ),
          ),
        ),
        _SelectorRow(
          label: 'Image Size',
          value: s.openaiSize,
          onTap: () => _showOptionsSheet<String>(
            title: 'Image Size',
            items: OpenAIConstants.sizes,
            labelBuilder: (v) => v,
            isSelected: (v) => s.openaiSize == v,
            onSelected: (v) => _update(s.copyWith(openaiSize: v)),
          ),
        ),
        _SelectorRow(
          label: 'Quality',
          value: s.openaiQuality == 'hd' ? 'HD' : 'Standard',
          onTap: () => _showOptionsSheet<String>(
            title: 'Quality',
            items: OpenAIConstants.qualities,
            labelBuilder: (v) => v == 'hd' ? 'HD' : 'Standard',
            isSelected: (v) => s.openaiQuality == v,
            onSelected: (v) => _update(s.copyWith(openaiQuality: v)),
          ),
        ),
      ];
    } else {
      return [
        _TextFieldItem(
          label: 'Model',
          value: s.customModel,
          hint: 'imagen-3.0-generate-002',
          onChanged: (v) => _update(s.copyWith(customModel: v)),
        ),
        _SelectorRow(
          label: 'Aspect Ratio',
          value: s.geminiAspectRatio,
          onTap: () => _showOptionsSheet<String>(
            title: 'Aspect Ratio',
            items: GeminiConstants.aspectRatios,
            labelBuilder: (v) => v,
            isSelected: (v) => s.geminiAspectRatio == v,
            onSelected: (v) => _update(s.copyWith(geminiAspectRatio: v)),
          ),
        ),
        _SelectorRow(
          label: 'Resolution',
          value: s.geminiImageSize,
          onTap: () => _showOptionsSheet<String>(
            title: 'Resolution',
            items: GeminiConstants.imageSizes,
            labelBuilder: (v) => v,
            isSelected: (v) => s.geminiImageSize == v,
            onSelected: (v) => _update(s.copyWith(geminiImageSize: v)),
          ),
        ),
      ];
    }
  }

  List<Widget> _buildReferences(ImageGenSettings s) {
    final isRoutmy = s.apiType == ImageGenApiType.routmy;
    final isRuRoutmy = s.apiType == ImageGenApiType.ruRoutmy;

    final sendCharAvatar = isRoutmy
        ? s.routmySendCharAvatar
        : (isRuRoutmy ? s.ruRoutmySendCharAvatar : s.naisteraSendCharAvatar);
    final sendUserAvatar = isRoutmy
        ? s.routmySendUserAvatar
        : (isRuRoutmy ? s.ruRoutmySendUserAvatar : s.naisteraSendUserAvatar);

    final refs = (isRoutmy || isRuRoutmy)
        ? s.routmyAdditionalRefs
        : s.additionalReferences;

    return [
      _MenuGroup(
        title: 'Reference Images',
        children: [
          _CheckboxRow(
            label: 'Send character avatar',
            description: 'Use character\'s avatar as visual reference',
            value: sendCharAvatar,
            onChanged: (v) {
              if (isRoutmy) {
                _update(s.copyWith(routmySendCharAvatar: v));
              } else if (isRuRoutmy) {
                _update(s.copyWith(ruRoutmySendCharAvatar: v));
              } else {
                _update(s.copyWith(naisteraSendCharAvatar: v));
              }
            },
          ),
          _CheckboxRow(
            label: 'Send persona avatar',
            description: 'Use active persona\'s avatar as visual reference',
            value: sendUserAvatar,
            onChanged: (v) {
              if (isRoutmy) {
                _update(s.copyWith(routmySendUserAvatar: v));
              } else if (isRuRoutmy) {
                _update(s.copyWith(ruRoutmySendUserAvatar: v));
              } else {
                _update(s.copyWith(naisteraSendUserAvatar: v));
              }
            },
          ),
        ],
      ),
      _MenuGroup(
        title: 'Additional References',
        trailing: Text(
          '${refs.length}/8',
          style: TextStyle(fontSize: 13, color: context.cs.onSurfaceVariant),
        ),
        children: [
          for (int i = 0; i < refs.length; i++)
            _ReferenceRow(
              key: ValueKey('ref_$i'),
              refItem: refs[i],
              onNameChanged: (v) {
                final copy = List<ReferenceImage>.from(refs);
                copy[i] = copy[i].copyWith(name: v);
                if (isRoutmy || isRuRoutmy) {
                  _update(s.copyWith(routmyAdditionalRefs: copy));
                } else {
                  _update(s.copyWith(additionalReferences: copy));
                }
              },
              onMatchModeChanged: (v) {
                final copy = List<ReferenceImage>.from(refs);
                copy[i] = copy[i].copyWith(matchMode: v);
                if (isRoutmy || isRuRoutmy) {
                  _update(s.copyWith(routmyAdditionalRefs: copy));
                } else {
                  _update(s.copyWith(additionalReferences: copy));
                }
              },
              onPickImage: () {},
              onRemove: () {
                final copy = List<ReferenceImage>.from(refs);
                copy.removeAt(i);
                if (isRoutmy || isRuRoutmy) {
                  _update(s.copyWith(routmyAdditionalRefs: copy));
                } else {
                  _update(s.copyWith(additionalReferences: copy));
                }
              },
            ),
          if (refs.length < 8)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: InkWell(
                onTap: () {
                  final copy = List<ReferenceImage>.from(refs);
                  copy.add(
                    const ReferenceImage(
                      name: '',
                      imageData: '',
                      matchMode: 'match',
                    ),
                  );
                  if (isRoutmy || isRuRoutmy) {
                    _update(s.copyWith(routmyAdditionalRefs: copy));
                  } else {
                    _update(s.copyWith(additionalReferences: copy));
                  }
                },
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: context.cs.primary.withValues(alpha: 0.4),
                      style: BorderStyle.solid,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      '+ Add reference',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: context.cs.primary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ];
  }
}

class _MenuGroup extends StatelessWidget {
  final String title;
  final Widget? trailing;
  final List<Widget> children;

  const _MenuGroup({
    required this.title,
    this.trailing,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: context.cs.onSurfaceVariant,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
        ...children,
        const SizedBox(height: 16),
      ],
    );
  }
}

class _SelectorRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;

  const _SelectorRow({
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: context.cs.primary,
                  ),
                ),
                Icon(
                  Icons.keyboard_arrow_down,
                  size: 22,
                  color: context.cs.primary,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CheckboxRow extends StatelessWidget {
  final String label;
  final String? description;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _CheckboxRow({
    required this.label,
    this.description,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 14)),
                if (description != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      description!,
                      style: TextStyle(
                        fontSize: 12,
                        color: context.cs.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _TextFieldItem extends StatefulWidget {
  final String label;
  final String value;
  final bool obscure;
  final String? hint;
  final ValueChanged<String> onChanged;
  final Widget? suffix;
  const _TextFieldItem({
    required this.label,
    required this.value,
    this.obscure = false,
    this.hint,
    required this.onChanged,
    this.suffix,
  });
  @override
  State<_TextFieldItem> createState() => _TextFieldItemState();
}

class _TextFieldItemState extends State<_TextFieldItem> {
  late final _controller = TextEditingController(text: widget.value);
  bool _obscure = true;

  @override
  void didUpdateWidget(covariant _TextFieldItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value && widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label, style: const TextStyle(fontSize: 14)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                obscureText: widget.obscure && _obscure,
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  hintText: widget.hint,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  suffixIcon: widget.obscure
                      ? IconButton(
                          icon: Icon(
                            _obscure ? Icons.visibility_off : Icons.visibility,
                            size: 18,
                          ),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        )
                      : null,
                ),
                onChanged: widget.onChanged,
              ),
            ),
            if (widget.suffix != null) ...[
              const SizedBox(width: 8),
              widget.suffix!,
            ],
          ],
        ),
      ],
    ),
  );
}

class _ReferenceRow extends StatefulWidget {
  final ReferenceImage refItem;
  final ValueChanged<String> onNameChanged;
  final ValueChanged<String> onMatchModeChanged;
  final VoidCallback onPickImage;
  final VoidCallback onRemove;

  const _ReferenceRow({
    super.key,
    required this.refItem,
    required this.onNameChanged,
    required this.onMatchModeChanged,
    required this.onPickImage,
    required this.onRemove,
  });

  @override
  State<_ReferenceRow> createState() => _ReferenceRowState();
}

class _ReferenceRowState extends State<_ReferenceRow> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.refItem.name,
  );

  @override
  void didUpdateWidget(covariant _ReferenceRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refItem.name != oldWidget.refItem.name &&
        widget.refItem.name != _controller.text) {
      _controller.text = widget.refItem.name;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          InkWell(
            onTap: widget.onPickImage,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: context.cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: widget.refItem.imageData.isNotEmpty
                      ? context.cs.primary
                      : Colors.black12,
                ),
              ),
              child: const Icon(Icons.image, size: 20, color: Colors.grey),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _controller,
              onChanged: widget.onNameChanged,
              decoration: const InputDecoration(
                hintText: 'keyword',
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 10,
                ),
                border: InputBorder.none,
              ),
            ),
          ),
          InkWell(
            onTap: () {
              showModalBottomSheet(
                context: context,
                backgroundColor: Colors.transparent,
                builder: (context) => Container(
                  decoration: BoxDecoration(
                    color: context.cs.surface,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'Match Mode',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      ListTile(
                        title: const Text('match'),
                        trailing: widget.refItem.matchMode == 'match'
                            ? Text(
                                'Active',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: context.cs.primary,
                                ),
                              )
                            : null,
                        onTap: () {
                          widget.onMatchModeChanged('match');
                          Navigator.pop(context);
                        },
                      ),
                      ListTile(
                        title: const Text('always'),
                        trailing: widget.refItem.matchMode == 'always'
                            ? Text(
                                'Active',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: context.cs.primary,
                                ),
                              )
                            : null,
                        onTap: () {
                          widget.onMatchModeChanged('always');
                          Navigator.pop(context);
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
            child: Row(
              children: [
                Text(
                  widget.refItem.matchMode.isEmpty
                      ? 'match'
                      : widget.refItem.matchMode,
                  style: TextStyle(
                    fontSize: 13,
                    color: context.cs.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Icon(
                  Icons.keyboard_arrow_down,
                  size: 18,
                  color: context.cs.primary,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.close, size: 18, color: Colors.grey),
            onPressed: widget.onRemove,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}
