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
import '../models/extension_preset.dart';
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
              ...preset.blocks.map(
                (block) => MenuScriptItem(
                  name: block.name.isEmpty ? 'Без имени' : block.name,
                  subtitle: _blockSubtitle(block),
                  enabled: block.enabled,
                  onToggle: (v) => _toggleBlock(preset, block, v),
                  onTap: () => _editBlock(preset, block),
                  onMore: () => _showBlockActions(preset, block),
                ),
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
        ],
      ),
    );
  }

  String _blockSubtitle(BlockConfig block) {
    final type = block.type == BlockType.imageGen ? 'Генерация картинок' : 'Инфоблок';
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
  late TextEditingController _promptController;
  late TextEditingController _imagePromptController;
  late TextEditingController _apiConfigController;
  late TextEditingController _modelController;
  late BlockType _type;
  late BlockTrigger _trigger;
  late int _contextMessageCount;
  late int _contextBlockCount;
  late bool _inject;
  late int _injectDepth;
  late bool _imageGenEnabled;
  bool _fetchingModels = false;

  @override
  void initState() {
    super.initState();
    final b = widget.block;
    _nameController = TextEditingController(text: b.name);
    _promptController = TextEditingController(text: b.prompt);
    _imagePromptController = TextEditingController(text: b.imagePromptInstruction);
    _apiConfigController = TextEditingController(text: b.apiConfigId);
    _modelController = TextEditingController(text: b.model);
    _type = b.type;
    _trigger = b.trigger;
    _contextMessageCount = b.contextMessageCount;
    _contextBlockCount = b.contextBlockCount;
    _inject = b.inject;
    _injectDepth = b.injectDepth;
    _imageGenEnabled = b.imageGenEnabled;
  }

  void _save() {
    widget.onSave(widget.block.copyWith(
      name: _nameController.text.trim(),
      type: _type,
      trigger: _trigger,
      prompt: _promptController.text,
      contextMessageCount: _contextMessageCount,
      contextBlockCount: _contextBlockCount,
      inject: _inject,
      injectDepth: _injectDepth,
      apiConfigId: _apiConfigController.text.trim(),
      model: _modelController.text.trim(),
      imagePromptInstruction: _imagePromptController.text,
      imageGenEnabled: _imageGenEnabled,
    ));
    Navigator.pop(context);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _promptController.dispose();
    _imagePromptController.dispose();
    _apiConfigController.dispose();
    _modelController.dispose();
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
                ],
                selected: {_type},
                onSelectionChanged: (s) =>
                    setState(() => _type = s.first),
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
              const SizedBox(height: 16),
              SwitchListTile(
                title: const Text('Инжектировать в чат'),
                subtitle: const Text('Добавлять сгенерированный контент в историю'),
                value: _inject,
                onChanged: (v) => setState(() => _inject = v),
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _promptController,
                decoration: const InputDecoration(
                  labelText: 'Промпт для генерации',
                  hintText: 'Что запрашивать у LLM...',
                ),
                maxLines: 4,
                minLines: 2,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: TextEditingController(
                          text: _contextMessageCount.toString()),
                      decoration: const InputDecoration(labelText: 'Кол-во сообщений контекста'),
                      keyboardType: TextInputType.number,
                      onChanged: (v) =>
                          _contextMessageCount = int.tryParse(v) ?? _contextMessageCount,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: TextEditingController(
                          text: _contextBlockCount.toString()),
                      decoration: const InputDecoration(labelText: 'Кол-во блоков контекста'),
                      keyboardType: TextInputType.number,
                      onChanged: (v) =>
                          _contextBlockCount = int.tryParse(v) ?? _contextBlockCount,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: TextEditingController(text: _injectDepth.toString()),
                decoration: const InputDecoration(
                  labelText: 'Глубина инжекта',
                  helperText: '-1 = перед последним user, 1 = после 1-го assistant',
                ),
                keyboardType: TextInputType.number,
                onChanged: (v) => _injectDepth = int.tryParse(v) ?? _injectDepth,
              ),
              const SizedBox(height: 12),
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
                onFetchStart: () => setState(() => _fetchingModels = true),
                onFetchEnd: () => setState(() => _fetchingModels = false),
              ),
              if (_type == BlockType.imageGen) ...[
                const SizedBox(height: 16),
                SwitchListTile(
                  title: const Text('Генерация картинок включена'),
                  value: _imageGenEnabled,
                  onChanged: (v) => setState(() => _imageGenEnabled = v),
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _imagePromptController,
                  decoration: const InputDecoration(
                    labelText: 'Инструкция для картинки',
                    hintText: 'Описание картинки для генерации...',
                  ),
                  maxLines: 3,
                  minLines: 2,
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
