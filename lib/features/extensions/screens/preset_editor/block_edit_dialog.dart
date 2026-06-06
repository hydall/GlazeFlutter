import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/block_config.dart';
import 'widgets/api_config_selector.dart';
import 'widgets/block_trigger_picker.dart';
import 'widgets/block_type_picker.dart';
import 'widgets/model_field.dart';
import 'widgets/section_label.dart';

class BlockEditDialog extends ConsumerStatefulWidget {
  const BlockEditDialog({required this.block, required this.onSave, super.key});

  final BlockConfig block;
  final void Function(BlockConfig) onSave;

  @override
  ConsumerState<BlockEditDialog> createState() => _BlockEditDialogState();
}

class _BlockEditDialogState extends ConsumerState<BlockEditDialog> {
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
  late bool _useStaticHtml;
  bool _fetchingModels = false;

  @override
  void initState() {
    super.initState();
    final b = widget.block;
    _nameController = TextEditingController(text: b.name);
    _templateController = TextEditingController(text: b.template);
    final promptText =
        b.type == BlockType.imageGen &&
            b.prompt.isEmpty &&
            b.imagePromptInstruction.isNotEmpty
        ? b.imagePromptInstruction
        : b.prompt;
    _promptController = TextEditingController(text: promptText);
    _apiConfigController = TextEditingController(text: b.apiConfigId);
    _modelController = TextEditingController(text: b.model);
    _contextSystemPromptController = TextEditingController(
      text: b.contextSystemPrompt,
    );
    _injectPrefixController = TextEditingController(text: b.injectPrefix);
    _staticHtmlController = TextEditingController(text: b.script);
    _minHeightController = TextEditingController(text: '120');
    _type = b.type;
    _trigger = b.trigger;
    _inject = b.inject;
    _injectLastN = b.injectLastN;
    _dependsOnPrevious = b.dependsOnPrevious;
    _contextMessageCount = b.contextMessageCount;
    _streamToPanel = b.streamToPanel;
    _useStaticHtml =
        b.type == BlockType.interactive && b.script.trim().isNotEmpty;
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
    final usesLlm =
        isInfoblock || isImage || isJs || (isInteractive && !_useStaticHtml);
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
              BlockTypePicker(selected: _type, onChanged: _onTypeChanged),
              const SizedBox(height: 16),
              BlockTriggerPicker(
                selected: _trigger,
                onChanged: (v) => setState(() => _trigger = v),
              ),
              if (_type == BlockType.infoblock ||
                  _type == BlockType.imageGen ||
                  _type == BlockType.jsRunner) ...[
                const SizedBox(height: 8),
                _DependsOnPreviousSwitch(
                  type: _type,
                  value: _dependsOnPrevious,
                  onChanged: (v) => setState(() => _dependsOnPrevious = v),
                ),
              ],
              if (_type == BlockType.infoblock) ...[
                const SizedBox(height: 16),
                _InfoblockInjectFields(
                  inject: _inject,
                  injectPrefixController: _injectPrefixController,
                  onInjectChanged: (v) => setState(() => _inject = v),
                  onLastNChanged: (v) => _injectLastN = v,
                  initialLastN: _injectLastN,
                ),
              ],
              if (_usesStandardLlmFields) ...[
                const SizedBox(height: 16),
                _PromptFields(type: _type, controller: _promptController),
              ],
              if (_type == BlockType.infoblock) ...[
                const SizedBox(height: 8),
                _TemplateField(controller: _templateController),
              ],
              if (_usesStandardLlmFields) ...[
                const SizedBox(height: 16),
                _LlmOptionsFields(
                  type: _type,
                  apiConfigController: _apiConfigController,
                  modelController: _modelController,
                  contextSystemPromptController: _contextSystemPromptController,
                  contextMessageCount: _contextMessageCount,
                  streamToPanel: _streamToPanel,
                  fetchingModels: _fetchingModels,
                  onContextMessageCountChanged: (v) => _contextMessageCount = v,
                  onStreamToPanelChanged: (v) =>
                      setState(() => _streamToPanel = v),
                  onApiChanged: (id) {
                    setState(() {
                      _apiConfigController.text = id ?? '';
                      _modelController.clear();
                    });
                  },
                  onFetchStart: () => setState(() => _fetchingModels = true),
                  onFetchEnd: () => setState(() => _fetchingModels = false),
                ),
              ],
              if (_type == BlockType.imageGen) const _ImageGenHelpText(),
              if (_type == BlockType.jsRunner) const _JsRunnerHelpText(),
              if (_type == BlockType.interactive) ...[
                const SizedBox(height: 16),
                _InteractiveFields(
                  useStaticHtml: _useStaticHtml,
                  staticHtmlController: _staticHtmlController,
                  promptController: _promptController,
                  minHeightController: _minHeightController,
                  dependsOnPrevious: _dependsOnPrevious,
                  contextMessageCount: _contextMessageCount,
                  contextSystemPromptController: _contextSystemPromptController,
                  apiConfigController: _apiConfigController,
                  modelController: _modelController,
                  fetchingModels: _fetchingModels,
                  streamToPanel: _streamToPanel,
                  onUseStaticHtmlChanged: (v) =>
                      setState(() => _useStaticHtml = v),
                  onMinHeightChanged: (_) {},
                  onDependsOnPreviousChanged: (v) =>
                      setState(() => _dependsOnPrevious = v),
                  onContextMessageCountChanged: (v) => _contextMessageCount = v,
                  onApiChanged: (id) {
                    setState(() {
                      _apiConfigController.text = id ?? '';
                      _modelController.clear();
                    });
                  },
                  onFetchStart: () => setState(() => _fetchingModels = true),
                  onFetchEnd: () => setState(() => _fetchingModels = false),
                  onStreamToPanelChanged: (v) =>
                      setState(() => _streamToPanel = v),
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
        FilledButton(onPressed: _save, child: const Text('Сохранить')),
      ],
    );
  }

  bool get _usesStandardLlmFields =>
      _type == BlockType.infoblock ||
      _type == BlockType.imageGen ||
      _type == BlockType.jsRunner;
}

class _DependsOnPreviousSwitch extends StatelessWidget {
  const _DependsOnPreviousSwitch({
    required this.type,
    required this.value,
    required this.onChanged,
  });

  final BlockType type;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      title: const Text('Ждать завершения предыдущего блока'),
      subtitle: Text(
        type == BlockType.imageGen
            ? 'Ledger/infoblock передаётся agent\'у как previousOutput'
            : type == BlockType.jsRunner
            ? 'Вывод предыдущего блока доступен в context.previousOutput'
            : 'Получает вывод предыдущего блока как контекст',
      ),
      value: value,
      onChanged: onChanged,
      contentPadding: EdgeInsets.zero,
    );
  }
}

class _InfoblockInjectFields extends StatelessWidget {
  const _InfoblockInjectFields({
    required this.inject,
    required this.injectPrefixController,
    required this.onInjectChanged,
    required this.onLastNChanged,
    required this.initialLastN,
  });

  final bool inject;
  final TextEditingController injectPrefixController;
  final ValueChanged<bool> onInjectChanged;
  final ValueChanged<int> onLastNChanged;
  final int initialLastN;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SwitchListTile(
          title: const Text('Инжектировать в промпт'),
          subtitle: const Text(
            'Дописывать вывод блока к последним N assistant-сообщениям в истории чата',
          ),
          value: inject,
          onChanged: onInjectChanged,
          contentPadding: EdgeInsets.zero,
        ),
        if (inject) ...[
          const SizedBox(height: 8),
          TextField(
            controller: TextEditingController(text: initialLastN.toString()),
            decoration: const InputDecoration(
              labelText: 'Сколько последних assistant-сообщений',
              helperText:
                  '0 = не инжектировать. К каждому из N сообщений дописывается только его блок.',
            ),
            keyboardType: TextInputType.number,
            onChanged: (v) => onLastNChanged(int.tryParse(v) ?? initialLastN),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: injectPrefixController,
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
    );
  }
}

class _PromptFields extends StatelessWidget {
  const _PromptFields({required this.type, required this.controller});

  final BlockType type;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SectionLabel(switch (type) {
          BlockType.imageGen => 'Image agent (LLM)',
          BlockType.jsRunner => 'JS agent (LLM)',
          _ => 'Промпт и формат',
        }),
        TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: switch (type) {
              BlockType.imageGen => 'Инструкции agent\'а (<image_prompt>…)',
              BlockType.jsRunner => 'Инструкции: что должен сделать JS-скрипт',
              _ => 'Инструкции для модели',
            },
            hintText: switch (type) {
              BlockType.imageGen => 'Правила HTML-карточки, [IMG:GEN], JSON…',
              BlockType.jsRunner =>
                'Модель пишет ```js … ``` с return "…". context: messages, character, previousOutput',
              _ => 'Что именно сгенерировать в этом блоке…',
            },
            helperText: switch (type) {
              BlockType.imageGen =>
                'System prompt для LLM: HTML с data-iig-instruction',
              BlockType.jsRunner =>
                'Модель генерирует код; sandbox выполняет return строки/HTML',
              _ => 'Уходит в system-сообщение к LLM (главные правила блока)',
            },
            alignLabelWithHint: true,
          ),
          maxLines: type == BlockType.infoblock ? 4 : 12,
          minLines: type == BlockType.infoblock ? 2 : 6,
        ),
      ],
    );
  }
}

class _TemplateField extends StatelessWidget {
  const _TemplateField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
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
      style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
    );
  }
}

class _LlmOptionsFields extends StatelessWidget {
  const _LlmOptionsFields({
    required this.type,
    required this.apiConfigController,
    required this.modelController,
    required this.contextSystemPromptController,
    required this.contextMessageCount,
    required this.streamToPanel,
    required this.fetchingModels,
    required this.onContextMessageCountChanged,
    required this.onStreamToPanelChanged,
    required this.onApiChanged,
    required this.onFetchStart,
    required this.onFetchEnd,
  });

  final BlockType type;
  final TextEditingController apiConfigController;
  final TextEditingController modelController;
  final TextEditingController contextSystemPromptController;
  final int contextMessageCount;
  final bool streamToPanel;
  final bool fetchingModels;
  final ValueChanged<int> onContextMessageCountChanged;
  final ValueChanged<bool> onStreamToPanelChanged;
  final ValueChanged<String?> onApiChanged;
  final VoidCallback onFetchStart;
  final VoidCallback onFetchEnd;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SectionLabel('История чата для блока'),
        _ContextMessageCountField(
          value: contextMessageCount,
          onChanged: onContextMessageCountChanged,
          fullHelper: true,
        ),
        const SizedBox(height: 8),
        _ContextSystemPromptField(controller: contextSystemPromptController),
        const SizedBox(height: 16),
        SectionLabel(switch (type) {
          BlockType.imageGen => 'API agent\'а',
          BlockType.jsRunner => 'API agent\'а',
          _ => 'API',
        }),
        ApiConfigSelector(
          selectedId: apiConfigController.text,
          onSelected: onApiChanged,
        ),
        const SizedBox(height: 8),
        ModelField(
          controller: modelController,
          apiConfigId: apiConfigController.text,
          fetching: fetchingModels,
          onFetchStart: onFetchStart,
          onFetchEnd: onFetchEnd,
        ),
        const SizedBox(height: 4),
        SwitchListTile(
          title: const Text('Стриминг в панель'),
          subtitle: Text(switch (type) {
            BlockType.imageGen =>
              'HTML agent\'а по мере генерации LLM (до Image Gen)',
            BlockType.jsRunner =>
              'Код от модели по мере генерации LLM (до sandbox)',
            _ => 'Текст блока появляется по мере генерации LLM',
          }),
          value: streamToPanel,
          onChanged: onStreamToPanelChanged,
          contentPadding: EdgeInsets.zero,
        ),
      ],
    );
  }
}

class _InteractiveFields extends StatelessWidget {
  const _InteractiveFields({
    required this.useStaticHtml,
    required this.staticHtmlController,
    required this.promptController,
    required this.minHeightController,
    required this.dependsOnPrevious,
    required this.contextMessageCount,
    required this.contextSystemPromptController,
    required this.apiConfigController,
    required this.modelController,
    required this.fetchingModels,
    required this.streamToPanel,
    required this.onUseStaticHtmlChanged,
    required this.onMinHeightChanged,
    required this.onDependsOnPreviousChanged,
    required this.onContextMessageCountChanged,
    required this.onApiChanged,
    required this.onFetchStart,
    required this.onFetchEnd,
    required this.onStreamToPanelChanged,
  });

  final bool useStaticHtml;
  final TextEditingController staticHtmlController;
  final TextEditingController promptController;
  final TextEditingController minHeightController;
  final bool dependsOnPrevious;
  final int contextMessageCount;
  final TextEditingController contextSystemPromptController;
  final TextEditingController apiConfigController;
  final TextEditingController modelController;
  final bool fetchingModels;
  final bool streamToPanel;
  final ValueChanged<bool> onUseStaticHtmlChanged;
  final ValueChanged<int> onMinHeightChanged;
  final ValueChanged<bool> onDependsOnPreviousChanged;
  final ValueChanged<int> onContextMessageCountChanged;
  final ValueChanged<String?> onApiChanged;
  final VoidCallback onFetchStart;
  final VoidCallback onFetchEnd;
  final ValueChanged<bool> onStreamToPanelChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SectionLabel('Источник HTML'),
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
          selected: {useStaticHtml},
          onSelectionChanged: (s) => onUseStaticHtmlChanged(s.first),
          style: ButtonStyle(visualDensity: VisualDensity.compact),
        ),
        const SizedBox(height: 8),
        if (useStaticHtml)
          TextField(
            controller: staticHtmlController,
            decoration: const InputDecoration(
              labelText: 'HTML-разметка панели',
              helperText:
                  'Голый HTML без <html>/<body>: рендерится в sandboxed iframe. '
                  'JS внутри имеет доступ к window.glaze.* (setVariables, generateText, triggerGeneration и т.д.).',
              alignLabelWithHint: true,
            ),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            minLines: 6,
            maxLines: 18,
          )
        else
          TextField(
            controller: promptController,
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
          controller: minHeightController,
          decoration: const InputDecoration(
            labelText: 'Начальная высота (px)',
            helperText: '60..2000. Iframe перерастёт iframe при resize.',
          ),
          keyboardType: TextInputType.number,
          onChanged: (v) => onMinHeightChanged(int.tryParse(v) ?? 120),
        ),
        if (!useStaticHtml) ...[
          const SizedBox(height: 8),
          SwitchListTile(
            title: const Text('Ждать завершения предыдущего блока'),
            subtitle: const Text(
              'Получает вывод предыдущего блока как контекст',
            ),
            value: dependsOnPrevious,
            onChanged: onDependsOnPreviousChanged,
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 16),
          const SectionLabel('История чата для блока'),
          _ContextMessageCountField(
            value: contextMessageCount,
            onChanged: onContextMessageCountChanged,
            fullHelper: false,
          ),
          const SizedBox(height: 8),
          _ContextSystemPromptField(controller: contextSystemPromptController),
          const SizedBox(height: 16),
          const SectionLabel('API'),
          ApiConfigSelector(
            selectedId: apiConfigController.text,
            onSelected: onApiChanged,
          ),
          const SizedBox(height: 8),
          ModelField(
            controller: modelController,
            apiConfigId: apiConfigController.text,
            fetching: fetchingModels,
            onFetchStart: onFetchStart,
            onFetchEnd: onFetchEnd,
          ),
          const SizedBox(height: 4),
          SwitchListTile(
            title: const Text('Стриминг в панель'),
            subtitle: const Text(
              'HTML от модели появляется в панели по мере генерации',
            ),
            value: streamToPanel,
            onChanged: onStreamToPanelChanged,
            contentPadding: EdgeInsets.zero,
          ),
        ],
        const _InteractiveHelpText(),
      ],
    );
  }
}

class _ContextMessageCountField extends StatelessWidget {
  const _ContextMessageCountField({
    required this.value,
    required this.onChanged,
    required this.fullHelper,
  });

  final int value;
  final ValueChanged<int> onChanged;
  final bool fullHelper;

  @override
  Widget build(BuildContext context) {
    return TextField(
      decoration: InputDecoration(
        labelText: 'Сколько последних сообщений чата передать',
        helperText: fullHelper
            ? 'Считается от сообщения, на котором висит блок (не от конца чата).\n'
                  '1 — только это сообщение (ответ ассистента на панели).\n'
                  '2 — user+assistant, заканчивая этим сообщением.\n'
                  '4 — ~2 хода (2×U+A) перед ним.\n'
                  '0 — без лога чата. -1 — вся история до этого сообщения.'
            : 'Считается от сообщения, на котором висит блок (не от конца чата).',
      ),
      keyboardType: const TextInputType.numberWithOptions(signed: true),
      controller: TextEditingController(text: value.toString()),
      onChanged: (v) => onChanged(int.tryParse(v) ?? value),
    );
  }
}

class _ContextSystemPromptField extends StatelessWidget {
  const _ContextSystemPromptField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
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
    );
  }
}

class _ImageGenHelpText extends StatelessWidget {
  const _ImageGenHelpText();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 12),
      child: Text(
        'Провайдер и ключ Image Gen — в Settings → Image Gen. '
        'Блок сначала вызывает LLM agent, затем рендерит картинку по [IMG:GEN].',
        style: TextStyle(fontSize: 12, height: 1.4),
      ),
    );
  }
}

class _JsRunnerHelpText extends StatelessWidget {
  const _JsRunnerHelpText();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 12),
      child: Text(
        'LLM пишет JavaScript по промпту → код извлекается из ```js``` → '
        'sandbox выполняет скрипт (context.messages, context.character, context.previousOutput). '
        'Результат — return строки или HTML.',
        style: TextStyle(fontSize: 12, height: 1.4),
      ),
    );
  }
}

class _InteractiveHelpText extends StatelessWidget {
  const _InteractiveHelpText();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 12),
      child: Text(
        'Панель отрисуется под сообщением ассистента как persistent sandboxed iframe island. '
        'JS-код внутри неё может вызывать glaze.setVariables, glaze.generateText, '
        'glaze.injectPrompt и т.д. Вызовы идут через тот же bridge, что и в других блоках.',
        style: TextStyle(fontSize: 12, height: 1.4),
      ),
    );
  }
}
