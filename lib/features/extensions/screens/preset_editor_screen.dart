import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/llm/sse_client.dart';
import '../../../core/models/api_config.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/widgets/glaze_bottom_sheet.dart';
import '../../../shared/widgets/glaze_scaffold.dart';
import '../../../shared/widgets/glaze_toast.dart';
import '../../../shared/widgets/menu_group.dart';
import '../../settings/api_list_provider.dart';
import '../models/block_config.dart';
import '../models/connection_profiles.dart';
import '../models/extension_preset.dart';
import '../models/preset_permissions.dart';
import '../providers/extension_presets_provider.dart';

class PresetEditorScreen extends ConsumerStatefulWidget {
  const PresetEditorScreen({required this.presetId, super.key});
  final String presetId;

  @override
  ConsumerState<PresetEditorScreen> createState() => _PresetEditorScreenState();
}

class _PresetEditorScreenState extends ConsumerState<PresetEditorScreen> {
  @override
  Widget build(BuildContext context) {
    final preset = ref.watch(extensionPresetByIdProvider(widget.presetId));

    if (preset == null) {
      return GlazeScaffold(
        title: 'Пресет',
        onBack: () => context.pop(),
        body: const Center(child: Text('Пресет не найден')),
      );
    }

    return GlazeScaffold(
      title: preset.name,
      onBack: () => context.pop(),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          MenuGroup(
            header: 'Блоки',
            items: [
              if (preset.blocks.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    'Пока нет блоков',
                    style: TextStyle(
                      fontSize: 13,
                      color: context.cs.onSurfaceVariant.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              ReorderableListView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                onReorderItem: (oldIdx, newIdx) => _reorderBlock(preset, oldIdx, newIdx),
                children: [
                  for (int i = 0; i < preset.blocks.length; i++)
                    _buildBlockTile(preset, preset.blocks[i], i),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: OutlinedButton.icon(
              onPressed: () => _addBlock(preset),
              icon: const Icon(Icons.add),
              label: const Text('Добавить блок'),
            ),
          ),
          const SizedBox(height: 24),
          MenuGroup(
            header: 'Разрешения (capabilities)',
            items: [
              for (final cap in GlazeCapability.values)
                _buildCapabilityTile(preset, cap),
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Каждое разрешение открывает JS-блокам доступ к соответствующему методу glaze.*. По умолчанию всё запрещено (default-deny).',
              style: TextStyle(
                fontSize: 12,
                color: context.cs.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
          ),
          const SizedBox(height: 24),
          MenuGroup(
            header: 'Профили подключения (generateText)',
            items: [
              _buildProfileTile(preset, ConnectionProfile.big),
              _buildProfileTile(preset, ConnectionProfile.medium),
              _buildProfileTile(preset, ConnectionProfile.small),
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Сопоставление для glaze.generateText({ preset }). Пусто = использовать активный API.',
              style: TextStyle(
                fontSize: 12,
                color: context.cs.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileTile(ExtensionPreset preset, ConnectionProfile profile) {
    final current = switch (profile) {
      ConnectionProfile.big => preset.connectionProfiles.big,
      ConnectionProfile.medium => preset.connectionProfiles.medium,
      ConnectionProfile.small => preset.connectionProfiles.small,
    };
    final label = switch (profile) {
      ConnectionProfile.big => 'big',
      ConnectionProfile.medium => 'medium',
      ConnectionProfile.small => 'small',
    };
    final configsAsync = ref.watch(apiListProvider);
    final configs = configsAsync.valueOrNull ?? const <ApiConfig>[];
    String displayName;
    if (current.isEmpty) {
      displayName = 'Использовать основной';
    } else {
      final match = configs.where((c) => c.id == current).firstOrNull;
      displayName = match == null
          ? 'Не найдено (id=$current)'
          : (match.name.isNotEmpty ? match.name : 'Без имени');
    }
    return ListTile(
      title: Text(label),
      subtitle: Text(
        displayName,
        style: TextStyle(
          fontSize: 12,
          color: context.cs.onSurfaceVariant.withValues(alpha: 0.7),
        ),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _openProfilePicker(preset, profile, configs, current),
    );
  }

  Future<void> _openProfilePicker(
    ExtensionPreset preset,
    ConnectionProfile profile,
    List<ApiConfig> configs,
    String current,
  ) async {
    String? pendingSelection = current;
    await GlazeBottomSheet.show<void>(
      context,
      title: 'Профиль "${profile.name}"',
      items: [
        BottomSheetItem(
          label: 'Использовать основной',
          icon: current.isEmpty
              ? Icons.radio_button_checked
              : Icons.radio_button_off,
          iconColor: current.isEmpty
              ? context.cs.primary
              : context.cs.onSurfaceVariant,
          onTap: () {
            pendingSelection = '';
            Navigator.of(context, rootNavigator: true).pop();
          },
        ),
        ...configs.map(
          (cfg) {
            final name = cfg.name.isNotEmpty ? cfg.name : 'Без имени';
            return BottomSheetItem(
              label: name,
              icon: cfg.id == current
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off,
              iconColor: cfg.id == current
                  ? context.cs.primary
                  : context.cs.onSurfaceVariant,
              onTap: () {
                pendingSelection = cfg.id;
                Navigator.of(context, rootNavigator: true).pop();
              },
            );
          },
        ),
      ],
    );
    final next = pendingSelection;
    if (next == null || next == current) return;
    final updated = switch (profile) {
      ConnectionProfile.big =>
        preset.copyWith(connectionProfiles: preset.connectionProfiles.copyWith(big: next)),
      ConnectionProfile.medium => preset.copyWith(
          connectionProfiles: preset.connectionProfiles.copyWith(medium: next)),
      ConnectionProfile.small => preset.copyWith(
          connectionProfiles: preset.connectionProfiles.copyWith(small: next)),
    };
    await ref.read(extensionPresetsProvider.notifier).update(updated);
  }

  Widget _buildCapabilityTile(ExtensionPreset preset, GlazeCapability cap) {
    final granted = preset.permissions.isGranted(cap);
    return SwitchListTile(
      title: Text(cap.label),
      subtitle: Text(
        cap.id,
        style: TextStyle(
          fontSize: 11,
          color: context.cs.onSurfaceVariant.withValues(alpha: 0.6),
        ),
      ),
      value: granted,
      onChanged: (v) {
        final next = preset.permissions.copyWithField(cap, v);
        ref.read(extensionPresetsProvider.notifier).update(
          preset.copyWith(permissions: next),
        );
      },
    );
  }

  String _blockSubtitle(BlockConfig block) {
    final type = switch (block.type) {
      BlockType.infoblock => 'Инфоблок',
      BlockType.imageGen => 'Картинка',
      BlockType.jsRunner => 'JS',
      BlockType.interactive => 'Интерактивная панель',
    };
    final trigger = switch (block.trigger) {
      BlockTrigger.afterUser => 'После user',
      BlockTrigger.afterAssistant => 'После assistant',
      BlockTrigger.periodic => 'Периодический',
    };
    return '$type • $trigger';
  }

  void _toggleBlock(ExtensionPreset preset, BlockConfig block, bool enabled) {
    final updated = preset.copyWith(
      blocks: [
        for (final b in preset.blocks)
          if (b.id == block.id) b.copyWith(enabled: enabled) else b,
      ],
    );
    ref.read(extensionPresetsProvider.notifier).update(updated);
  }

  Widget _buildBlockTile(ExtensionPreset preset, BlockConfig block, int index) {
    return Stack(
      key: ValueKey(block.id),
      children: [
        MenuScriptItem(
          name: block.name.isEmpty ? 'Без имени' : block.name,
          subtitle: _blockSubtitle(block),
          enabled: block.enabled,
          onToggle: (v) => _toggleBlock(preset, block, v),
          onTap: () => _editBlock(preset, block),
          onMore: () => _showBlockActions(preset, block),
        ),
        // Drag handle overlay — positioned to the left side so it doesn't
        // conflict with the switch / more-vert on the right.
        Positioned(
          right: 110,
          top: 0,
          bottom: 0,
          child: ReorderableDragStartListener(
            index: index,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Icon(Icons.drag_handle, size: 20, color: Colors.white24),
            ),
          ),
        ),
      ],
    );
  }

  void _reorderBlock(ExtensionPreset preset, int oldIdx, int newIdx) {
    final blocks = List<BlockConfig>.from(preset.blocks);
    final item = blocks.removeAt(oldIdx);
    blocks.insert(newIdx, item);
    // Update the `order` field to match position.
    final reordered = [
      for (int i = 0; i < blocks.length; i++)
        blocks[i].copyWith(order: i),
    ];
    ref.read(extensionPresetsProvider.notifier).update(
      preset.copyWith(blocks: reordered),
    );
  }

  Future<void> _addBlock(ExtensionPreset preset) async {
    final id = 'block_${DateTime.now().millisecondsSinceEpoch}';
    final block = BlockConfig(
      id: id,
      name: 'Новый блок',
      type: BlockType.infoblock,
      enabled: true,
    );
    final updated = preset.copyWith(blocks: [...preset.blocks, block]);
    await ref.read(extensionPresetsProvider.notifier).update(updated);
    if (mounted) _editBlock(updated, block);
  }

  void _editBlock(ExtensionPreset preset, BlockConfig block) {
    showDialog<void>(
      context: context,
      builder: (ctx) => _BlockEditDialog(
        block: block,
        onSave: (updated) {
          final newPreset = preset.copyWith(
            blocks: [
              for (final b in preset.blocks)
                if (b.id == updated.id) updated else b,
            ],
          );
          ref.read(extensionPresetsProvider.notifier).update(newPreset);
        },
      ),
    );
  }

  void _showBlockActions(ExtensionPreset preset, BlockConfig block) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.cs.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Удалить блок'),
              onTap: () {
                Navigator.pop(ctx);
                _deleteBlock(preset, block);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _deleteBlock(ExtensionPreset preset, BlockConfig block) {
    final updated = preset.copyWith(
      blocks: preset.blocks.where((b) => b.id != block.id).toList(),
    );
    ref.read(extensionPresetsProvider.notifier).update(updated);
  }
}

class _BlockEditDialog extends ConsumerStatefulWidget {
  const _BlockEditDialog({required this.block, required this.onSave});
  final BlockConfig block;
  final void Function(BlockConfig) onSave;

  @override
  ConsumerState<_BlockEditDialog> createState() => _BlockEditDialogState();
}

class _BlockEditDialogState extends ConsumerState<_BlockEditDialog> {
  late TextEditingController _nameController;
  late TextEditingController _templateController;
  late TextEditingController _promptController;
  late TextEditingController _apiConfigController;
  late TextEditingController _modelController;
  late TextEditingController _contextSystemPromptController;
  late TextEditingController _injectPrefixController;
  late TextEditingController _staticHtmlController;
  late TextEditingController _minHeightController;
  late BlockType _type;
  late BlockTrigger _trigger;
  late bool _inject;
  late int _injectLastN;
  late bool _dependsOnPrevious;
  late int _contextMessageCount;
  late bool _streamToPanel;
  /// For `BlockType.interactive`: when true, [BlockConfig.script] holds
  /// static HTML and is rendered without an LLM call. When false, the LLM
  /// agent generates HTML from [BlockConfig.prompt] at runtime.
  late bool _useStaticHtml;
  late int _minHeight;
  bool _fetchingModels = false;

  @override
  void initState() {
    super.initState();
    final b = widget.block;
    _nameController = TextEditingController(text: b.name);
    _templateController = TextEditingController(text: b.template);
    final promptText = b.type == BlockType.imageGen &&
            b.prompt.isEmpty &&
            b.imagePromptInstruction.isNotEmpty
        ? b.imagePromptInstruction
        : b.prompt;
    _promptController = TextEditingController(text: promptText);
    _apiConfigController = TextEditingController(text: b.apiConfigId);
    _modelController = TextEditingController(text: b.model);
    _contextSystemPromptController = TextEditingController(text: b.contextSystemPrompt);
    _injectPrefixController = TextEditingController(text: b.injectPrefix);
    _staticHtmlController = TextEditingController(text: b.script);
    // Default minHeight: 120 px (matches the runtime fallback in
    // _runInteractive). 60..2000 clamp is enforced by the WebView layer.
    _minHeightController = TextEditingController(text: '120');
    _type = b.type;
    _trigger = b.trigger;
    _inject = b.inject;
    _injectLastN = b.injectLastN;
    _dependsOnPrevious = b.dependsOnPrevious;
    _contextMessageCount = b.contextMessageCount;
    _streamToPanel = b.streamToPanel;
    // Heuristic: existing block has script but no prompt → static.
    _useStaticHtml =
        b.type == BlockType.interactive && b.script.trim().isNotEmpty;
    _minHeight = 120;
  }

  void _save() {
    widget.onSave(_buildSavedBlock());
    Navigator.pop(context);
  }

  BlockConfig _buildSavedBlock() {
    final isImage = _type == BlockType.imageGen;
    final isJs = _type == BlockType.jsRunner;
    final isInfoblock = _type == BlockType.infoblock;
    final isInteractive = _type == BlockType.interactive;
    final usesLlm = isInfoblock || isImage || isJs ||
        (isInteractive && !_useStaticHtml);
    return widget.block.copyWith(
      name: _nameController.text.trim(),
      type: _type,
      trigger: _trigger,
      template: isInfoblock ? _templateController.text : '',
      prompt: usesLlm ? _promptController.text : '',
      inject: isInfoblock ? _inject : false,
      injectLastN: isInfoblock ? _injectLastN : 0,
      injectPrefix: isInfoblock ? _injectPrefixController.text : '',
      dependsOnPrevious: _dependsOnPrevious,
      apiConfigId: usesLlm ? _apiConfigController.text.trim() : '',
      model: usesLlm ? _modelController.text.trim() : '',
      imagePromptInstruction: '',
      imageGenEnabled: true,
      contextMessageCount: usesLlm ? _contextMessageCount : 0,
      contextSystemPrompt: usesLlm ? _contextSystemPromptController.text : '',
      streamToPanel: usesLlm ? _streamToPanel : false,
      // For interactive panels the `script` field stores static HTML (when
      // the user chose the static mode). For other types we keep whatever
      // was there before (jsRunner still uses script as legacy static JS).
      script: isInteractive
          ? (_useStaticHtml ? _staticHtmlController.text : '')
          : (isJs ? widget.block.script : ''),
    );
  }

  void _onTypeChanged(BlockType type) {
    setState(() {
      _type = type;
      if (type == BlockType.imageGen) {
        _dependsOnPrevious = true;
        _inject = false;
      }
      if (type == BlockType.jsRunner && _contextMessageCount == 0) {
        _contextMessageCount = 10;
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _templateController.dispose();
    _promptController.dispose();
    _apiConfigController.dispose();
    _modelController.dispose();
    _contextSystemPromptController.dispose();
    _injectPrefixController.dispose();
    _staticHtmlController.dispose();
    _minHeightController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Настройки блока'),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Название'),
              ),
              const SizedBox(height: 16),
              _SectionLabel('Тип'),
              SegmentedButton<BlockType>(
                segments: const [
                  ButtonSegment(
                    value: BlockType.infoblock,
                    label: Text('Инфоблок'),
                    icon: Icon(Icons.notes),
                  ),
                  ButtonSegment(
                    value: BlockType.imageGen,
                    label: Text('Картинка'),
                    icon: Icon(Icons.image_outlined),
                  ),
                  ButtonSegment(
                    value: BlockType.jsRunner,
                    label: Text('JS'),
                    icon: Icon(Icons.code),
                  ),
                  ButtonSegment(
                    value: BlockType.interactive,
                    label: Text('Панель'),
                    icon: Icon(Icons.dashboard_customize_outlined),
                  ),
                ],
                selected: {_type},
                onSelectionChanged: (s) => _onTypeChanged(s.first),
                style: ButtonStyle(visualDensity: VisualDensity.compact),
              ),
              const SizedBox(height: 16),
              _SectionLabel('Триггер'),
              SegmentedButton<BlockTrigger>(
                segments: const [
                  ButtonSegment(
                    value: BlockTrigger.afterUser,
                    label: Text('После user'),
                  ),
                  ButtonSegment(
                    value: BlockTrigger.afterAssistant,
                    label: Text('После assistant'),
                  ),
                  ButtonSegment(
                    value: BlockTrigger.periodic,
                    label: Text('Периодический'),
                  ),
                ],
                selected: {_trigger},
                onSelectionChanged: (s) =>
                    setState(() => _trigger = s.first),
                style: ButtonStyle(visualDensity: VisualDensity.compact),
              ),
              if (_type == BlockType.infoblock ||
                  _type == BlockType.imageGen ||
                  _type == BlockType.jsRunner) ...[
                const SizedBox(height: 8),
                SwitchListTile(
                  title: const Text('Ждать завершения предыдущего блока'),
                  subtitle: Text(
                    _type == BlockType.imageGen
                        ? 'Ledger/infoblock передаётся agent\'у как previousOutput'
                        : _type == BlockType.jsRunner
                            ? 'Вывод предыдущего блока доступен в context.previousOutput'
                            : 'Получает вывод предыдущего блока как контекст',
                  ),
                  value: _dependsOnPrevious,
                  onChanged: (v) => setState(() => _dependsOnPrevious = v),
                  contentPadding: EdgeInsets.zero,
                ),
              ],
              if (_type == BlockType.infoblock) ...[
                const SizedBox(height: 16),
                SwitchListTile(
                  title: const Text('Инжектировать в промпт'),
                  subtitle: const Text(
                    'Дописывать вывод блока к последним N assistant-сообщениям в истории чата',
                  ),
                  value: _inject,
                  onChanged: (v) => setState(() => _inject = v),
                  contentPadding: EdgeInsets.zero,
                ),
                if (_inject) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: TextEditingController(text: _injectLastN.toString()),
                    decoration: const InputDecoration(
                      labelText: 'Сколько последних assistant-сообщений',
                      helperText:
                          '0 = не инжектировать. К каждому из N сообщений дописывается только его блок.',
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (v) =>
                        _injectLastN = int.tryParse(v) ?? _injectLastN,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _injectPrefixController,
                    decoration: const InputDecoration(
                      labelText: 'Текст перед блоком',
                      helperText:
                          'Между ответом и блоком (после пустой строки). Пусто = сразу блок.',
                      alignLabelWithHint: true,
                    ),
                    minLines: 1,
                    maxLines: 4,
                  ),
                ],
              ],
              if (_type == BlockType.infoblock ||
                  _type == BlockType.imageGen ||
                  _type == BlockType.jsRunner) ...[
                const SizedBox(height: 16),
                _SectionLabel(switch (_type) {
                  BlockType.imageGen => 'Image agent (LLM)',
                  BlockType.jsRunner => 'JS agent (LLM)',
                  _ => 'Промпт и формат',
                }),
                TextField(
                  controller: _promptController,
                  decoration: InputDecoration(
                    labelText: switch (_type) {
                      BlockType.imageGen => 'Инструкции agent\'а (<image_prompt>…)',
                      BlockType.jsRunner =>
                        'Инструкции: что должен сделать JS-скрипт',
                      _ => 'Инструкции для модели',
                    },
                    hintText: switch (_type) {
                      BlockType.imageGen =>
                        'Правила HTML-карточки, [IMG:GEN], JSON…',
                      BlockType.jsRunner =>
                        'Модель пишет ```js … ``` с return "…". context: messages, character, previousOutput',
                      _ => 'Что именно сгенерировать в этом блоке…',
                    },
                    helperText: switch (_type) {
                      BlockType.imageGen =>
                        'System prompt для LLM: HTML с data-iig-instruction',
                      BlockType.jsRunner =>
                        'Модель генерирует код; sandbox выполняет return строки/HTML',
                      _ => 'Уходит в system-сообщение к LLM (главные правила блока)',
                    },
                    alignLabelWithHint: true,
                  ),
                  maxLines: _type == BlockType.infoblock ? 4 : 12,
                  minLines: _type == BlockType.infoblock ? 2 : 6,
                ),
              ],
              if (_type == BlockType.infoblock) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _templateController,
                  decoration: const InputDecoration(
                    labelText: 'Шаблон XML (необязательно)',
                    hintText: '<{{name}}>\n<details>…</details>\n</{{name}}>',
                    helperText:
                        'Если задан — модель должна заполнить содержимое между тегами. '
                        'Пустое поле = сохраняем весь ответ модели без парсинга XML.',
                    alignLabelWithHint: true,
                  ),
                  maxLines: 5,
                  minLines: 2,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                  ),
                ),
              ],
              if (_type == BlockType.infoblock ||
                  _type == BlockType.imageGen ||
                  _type == BlockType.jsRunner) ...[
                const SizedBox(height: 16),
                _SectionLabel('История чата для блока'),
                TextField(
                  decoration: const InputDecoration(
                    labelText: 'Сколько последних сообщений чата передать',
                    helperText:
                        'Считается от сообщения, на котором висит блок (не от конца чата).\n'
                        '1 — только это сообщение (ответ ассистента на панели).\n'
                        '2 — user+assistant, заканчивая этим сообщением.\n'
                        '4 — ~2 хода (2×U+A) перед ним.\n'
                        '0 — без лога чата. -1 — вся история до этого сообщения.',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(signed: true),
                  controller: TextEditingController(text: _contextMessageCount.toString()),
                  onChanged: (v) =>
                      _contextMessageCount = int.tryParse(v) ?? _contextMessageCount,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _contextSystemPromptController,
                  decoration: const InputDecoration(
                    labelText: 'Текст перед историей чата',
                    hintText: 'Стиль, напоминания, описание сцены…',
                    helperText:
                        'Добавляется в user-сообщение перед логом чата. '
                        'Макросы: {{char}}, {{user}}, {{description}}, {{personality}}',
                    alignLabelWithHint: true,
                  ),
                  maxLines: 5,
                  minLines: 2,
                ),
                const SizedBox(height: 16),
                _SectionLabel(switch (_type) {
                  BlockType.imageGen => 'API agent\'а',
                  BlockType.jsRunner => 'API agent\'а',
                  _ => 'API',
                }),
                _ApiConfigSelector(
                  selectedId: _apiConfigController.text,
                  onSelected: (id) {
                    setState(() {
                      _apiConfigController.text = id ?? '';
                      _modelController.clear();
                    });
                  },
                ),
                const SizedBox(height: 8),
                _ModelField(
                  controller: _modelController,
                  apiConfigId: _apiConfigController.text,
                  fetching: _fetchingModels,
                  onFetchStart: () => setState(() => _fetchingModels = true),
                  onFetchEnd: () => setState(() => _fetchingModels = false),
                ),
                const SizedBox(height: 4),
                SwitchListTile(
                  title: const Text('Стриминг в панель'),
                  subtitle: Text(
                    switch (_type) {
                      BlockType.imageGen =>
                        'HTML agent\'а по мере генерации LLM (до Image Gen)',
                      BlockType.jsRunner =>
                        'Код от модели по мере генерации LLM (до sandbox)',
                      _ => 'Текст блока появляется по мере генерации LLM',
                    },
                  ),
                  value: _streamToPanel,
                  onChanged: (v) => setState(() => _streamToPanel = v),
                  contentPadding: EdgeInsets.zero,
                ),
              ],
              if (_type == BlockType.imageGen)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    'Провайдер и ключ Image Gen — в Settings → Image Gen. '
                    'Блок сначала вызывает LLM agent, затем рендерит картинку по [IMG:GEN].',
                    style: TextStyle(
                      fontSize: 12,
                      color: context.cs.onSurfaceVariant.withValues(alpha: 0.85),
                      height: 1.4,
                    ),
                  ),
                ),
              if (_type == BlockType.jsRunner)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    'LLM пишет JavaScript по промпту → код извлекается из ```js``` → '
                    'sandbox выполняет скрипт (context.messages, context.character, '
                    'context.previousOutput). Результат — return строки или HTML.',
                    style: TextStyle(
                      fontSize: 12,
                      color: context.cs.onSurfaceVariant.withValues(alpha: 0.85),
                      height: 1.4,
                    ),
                  ),
                ),
              if (_type == BlockType.interactive) ...[
                const SizedBox(height: 16),
                _SectionLabel('Источник HTML'),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: false,
                      label: Text('LLM'),
                      icon: Icon(Icons.auto_awesome),
                    ),
                    ButtonSegment(
                      value: true,
                      label: Text('Статический HTML'),
                      icon: Icon(Icons.code),
                    ),
                  ],
                  selected: {_useStaticHtml},
                  onSelectionChanged: (s) =>
                      setState(() => _useStaticHtml = s.first),
                  style: ButtonStyle(visualDensity: VisualDensity.compact),
                ),
                const SizedBox(height: 8),
                if (_useStaticHtml)
                  TextField(
                    controller: _staticHtmlController,
                    decoration: const InputDecoration(
                      labelText: 'HTML-разметка панели',
                      helperText:
                          'Голый HTML без <html>/<body>: рендерится в sandboxed iframe. '
                          'JS внутри имеет доступ к window.glaze.* (setVariables, '
                          'generateText, triggerGeneration и т.д.).',
                      alignLabelWithHint: true,
                    ),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                    minLines: 6,
                    maxLines: 18,
                  )
                else
                  TextField(
                    controller: _promptController,
                    decoration: const InputDecoration(
                      labelText: 'Промпт для LLM (HTML для панели)',
                      helperText:
                          'Модель должна вернуть HTML-разметку (можно в ```html```). '
                          'Если обрамлять ```html``` — fence будет снят автоматически.',
                      alignLabelWithHint: true,
                    ),
                    minLines: 4,
                    maxLines: 12,
                  ),
                const SizedBox(height: 8),
                TextField(
                  controller: _minHeightController,
                  decoration: const InputDecoration(
                    labelText: 'Начальная высота (px)',
                    helperText: '60..2000. Iframe перерастёт iframe при resize.',
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (v) =>
                      _minHeight = int.tryParse(v) ?? _minHeight,
                ),
                if (!_useStaticHtml) ...[
                  const SizedBox(height: 8),
                  SwitchListTile(
                    title: const Text('Ждать завершения предыдущего блока'),
                    subtitle: const Text(
                      'Получает вывод предыдущего блока как контекст',
                    ),
                    value: _dependsOnPrevious,
                    onChanged: (v) =>
                        setState(() => _dependsOnPrevious = v),
                    contentPadding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 16),
                  _SectionLabel('История чата для блока'),
                  TextField(
                    decoration: const InputDecoration(
                      labelText: 'Сколько последних сообщений чата передать',
                      helperText:
                          'Считается от сообщения, на котором висит блок (не от конца чата).',
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(signed: true),
                    controller: TextEditingController(
                        text: _contextMessageCount.toString()),
                    onChanged: (v) => _contextMessageCount =
                        int.tryParse(v) ?? _contextMessageCount,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _contextSystemPromptController,
                    decoration: const InputDecoration(
                      labelText: 'Текст перед историей чата',
                      helperText:
                          'Добавляется в user-сообщение перед логом чата. '
                          'Макросы: {{char}}, {{user}}, {{description}}, {{personality}}',
                      alignLabelWithHint: true,
                    ),
                    maxLines: 5,
                    minLines: 2,
                  ),
                  const SizedBox(height: 16),
                  _SectionLabel('API'),
                  _ApiConfigSelector(
                    selectedId: _apiConfigController.text,
                    onSelected: (id) {
                      setState(() {
                        _apiConfigController.text = id ?? '';
                        _modelController.clear();
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  _ModelField(
                    controller: _modelController,
                    apiConfigId: _apiConfigController.text,
                    fetching: _fetchingModels,
                    onFetchStart: () =>
                        setState(() => _fetchingModels = true),
                    onFetchEnd: () =>
                        setState(() => _fetchingModels = false),
                  ),
                  const SizedBox(height: 4),
                  SwitchListTile(
                    title: const Text('Стриминг в панель'),
                    subtitle: const Text(
                      'HTML от модели появляется в панели по мере генерации',
                    ),
                    value: _streamToPanel,
                    onChanged: (v) =>
                        setState(() => _streamToPanel = v),
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    'Панель отрисуется под сообщением ассистента как persistent '
                    'sandboxed iframe island. JS-код внутри неё может вызывать '
                    'glaze.setVariables, glaze.generateText, glaze.injectPrompt и т.д. '
                    'Вызовы идут через тот же bridge, что и в других блоках.',
                    style: TextStyle(
                      fontSize: 12,
                      color: context.cs.onSurfaceVariant.withValues(alpha: 0.85),
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('Сохранить'),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, left: 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: context.cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _ApiConfigSelector extends ConsumerWidget {
  const _ApiConfigSelector({
    required this.selectedId,
    required this.onSelected,
  });

  final String selectedId;
  final ValueChanged<String?> onSelected;

  String _displayName(List<ApiConfig> configs) {
    if (selectedId.isEmpty) return 'Использовать основной';
    final cfg = configs.where((c) => c.id == selectedId).firstOrNull;
    if (cfg == null) return 'Не найдено';
    return cfg.name.isNotEmpty ? cfg.name : 'Без имени';
  }

  Future<void> _open(BuildContext context, List<ApiConfig> configs) async {
    String? pendingSelection;
    await GlazeBottomSheet.show<void>(
      context,
      title: 'Выберите API',
      items: [
        BottomSheetItem(
          label: 'Использовать основной',
          icon: selectedId.isEmpty
              ? Icons.radio_button_checked
              : Icons.radio_button_off,
          iconColor: selectedId.isEmpty
              ? context.cs.primary
              : context.cs.onSurfaceVariant,
          onTap: () {
            pendingSelection = null;
            Navigator.of(context, rootNavigator: true).pop();
          },
        ),
        ...configs.map(
          (cfg) {
            final name = cfg.name.isNotEmpty ? cfg.name : 'Без имени';
            return BottomSheetItem(
              label: name,
              icon: selectedId == cfg.id
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off,
              iconColor: selectedId == cfg.id
                  ? context.cs.primary
                  : context.cs.onSurfaceVariant,
              onTap: () {
                pendingSelection = cfg.id;
                Navigator.of(context, rootNavigator: true).pop();
              },
            );
          },
        ),
      ],
    );
    onSelected(pendingSelection);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configsAsync = ref.watch(apiListProvider);
    final configs = configsAsync.valueOrNull ?? const <ApiConfig>[];

    return Material(
      color: Colors.white.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => _open(context, configs),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.cloud_outlined,
                size: 20,
                color: Color(0xFF99A2AD),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _displayName(configs),
                  style: TextStyle(
                    fontSize: 14,
                    color: context.cs.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 20,
                color: context.cs.onSurfaceVariant.withValues(alpha: 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModelField extends ConsumerWidget {
  const _ModelField({
    required this.controller,
    required this.apiConfigId,
    required this.fetching,
    required this.onFetchStart,
    required this.onFetchEnd,
  });

  final TextEditingController controller;
  final String apiConfigId;
  final bool fetching;
  final VoidCallback onFetchStart;
  final VoidCallback onFetchEnd;

  Future<void> _fetchAndPick(BuildContext context, WidgetRef ref) async {
    if (apiConfigId.isEmpty) {
      GlazeToast.show(context, 'Сначала выберите API');
      return;
    }
    final configs = ref.read(apiListProvider).valueOrNull ?? const <ApiConfig>[];
    final cfg = configs.where((c) => c.id == apiConfigId).firstOrNull;
    if (cfg == null) {
      GlazeToast.show(context, 'API не найден');
      return;
    }
    if (cfg.endpoint.isEmpty) {
      GlazeToast.show(context, 'У API не задан endpoint');
      return;
    }

    onFetchStart();
    try {
      final models = await SseClient().fetchModels(
        endpoint: cfg.endpoint,
        apiKey: cfg.apiKey,
      );
      if (!context.mounted) return;
      if (models.isEmpty) {
        GlazeToast.show(context, 'Модели не найдены');
        return;
      }
      final ids = models
          .map((m) => m['id'] as String?)
          .where((id) => id != null)
          .cast<String>()
          .toList()
        ..sort();
      String? pendingSelection;
      await GlazeBottomSheet.show<void>(
        context,
        title: 'Выберите модель',
        items: ids.map((id) {
          return BottomSheetItem(
            label: id,
            icon: id == controller.text
                ? Icons.radio_button_checked
                : Icons.radio_button_off,
            iconColor: id == controller.text
                ? context.cs.primary
                : context.cs.onSurfaceVariant,
            onTap: () {
              pendingSelection = id;
              Navigator.of(context, rootNavigator: true).pop();
            },
          );
        }).toList(),
      );
      if (pendingSelection != null) {
        controller.text = pendingSelection!;
      }
    } catch (e) {
      if (context.mounted) {
        GlazeToast.show(context, 'Ошибка загрузки моделей: $e');
      }
    } finally {
      onFetchEnd();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TextField(
      controller: controller,
      style: TextStyle(color: context.cs.onSurface, fontSize: 14),
      decoration: InputDecoration(
        labelText: 'Модель (опционально)',
        labelStyle: TextStyle(
          color: context.cs.onSurfaceVariant,
          fontSize: 12,
        ),
        hintText: 'Оставьте пустым для модели из API',
        hintStyle: TextStyle(
          color: context.cs.onSurfaceVariant.withValues(alpha: 0.4),
        ),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: context.cs.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: context.cs.primary.withValues(alpha: 0.5)),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        suffixIcon: IconButton(
          icon: fetching
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: context.cs.primary,
                  ),
                )
              : Icon(
                  Icons.download_rounded,
                  size: 20,
                  color: context.cs.onSurfaceVariant,
                ),
          tooltip: 'Загрузить список моделей',
          onPressed: fetching ? null : () => _fetchAndPick(context, ref),
        ),
      ),
    );
  }
}
