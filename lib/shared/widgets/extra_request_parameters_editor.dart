import 'package:flutter/material.dart';

import '../../core/models/extra_request_parameter.dart';

class ExtraRequestParametersEditor extends StatefulWidget {
  final List<ExtraRequestParameter> parameters;
  final ValueChanged<List<ExtraRequestParameter>> onChanged;
  final String title;
  final String description;
  final String keyLabel;
  final String valueLabel;
  final String addLabel;

  const ExtraRequestParametersEditor({
    super.key,
    required this.parameters,
    required this.onChanged,
    required this.title,
    required this.description,
    required this.keyLabel,
    required this.valueLabel,
    required this.addLabel,
  });

  @override
  State<ExtraRequestParametersEditor> createState() =>
      _ExtraRequestParametersEditorState();
}

class _ExtraRequestParametersEditorState
    extends State<ExtraRequestParametersEditor> {
  late final List<_EditableParameter> _parameters;

  @override
  void initState() {
    super.initState();
    _parameters = widget.parameters.map(_EditableParameter.new).toList();
  }

  @override
  void dispose() {
    for (final parameter in _parameters) {
      parameter.dispose();
    }
    super.dispose();
  }

  void _notifyChanged() {
    widget.onChanged(
      _parameters.map((parameter) => parameter.value).toList(growable: false),
    );
  }

  void _add() {
    setState(() {
      _parameters.add(_EditableParameter(const ExtraRequestParameter()));
    });
    _notifyChanged();
  }

  void _remove(int index) {
    setState(() {
      _parameters.removeAt(index).dispose();
    });
    _notifyChanged();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: Card(
        margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        clipBehavior: Clip.antiAlias,
        child: ExpansionTile(
          title: Text(widget.title),
          subtitle: Text(widget.description),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          children: [
            for (var index = 0; index < _parameters.length; index++) ...[
              _buildParameter(context, colors, index),
              if (index != _parameters.length - 1) const Divider(height: 16),
            ],
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _add,
                icon: const Icon(Icons.add_rounded),
                label: Text(widget.addLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildParameter(BuildContext context, ColorScheme colors, int index) {
    final parameter = _parameters[index];
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Switch(
              value: parameter.enabled,
              onChanged: (value) {
                setState(() => parameter.enabled = value);
                _notifyChanged();
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              children: [
                TextField(
                  controller: parameter.keyController,
                  decoration: InputDecoration(
                    labelText: widget.keyLabel,
                    hintText: 'reasoning_effort',
                    isDense: true,
                  ),
                  onChanged: (_) => _notifyChanged(),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: parameter.valueController,
                  decoration: InputDecoration(
                    labelText: widget.valueLabel,
                    hintText: 'xhigh',
                    helperText: 'JSON: true, 42, [1, 2], {"key": "value"}',
                    isDense: true,
                  ),
                  onChanged: (_) => _notifyChanged(),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _remove(index),
            tooltip: MaterialLocalizations.of(context).deleteButtonTooltip,
            color: colors.error,
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
    );
  }
}

class _EditableParameter {
  final TextEditingController keyController;
  final TextEditingController valueController;
  bool enabled;

  _EditableParameter(ExtraRequestParameter parameter)
    : keyController = TextEditingController(text: parameter.key),
      valueController = TextEditingController(text: parameter.value),
      enabled = parameter.enabled;

  ExtraRequestParameter get value => ExtraRequestParameter(
    key: keyController.text,
    value: valueController.text,
    enabled: enabled,
  );

  void dispose() {
    keyController.dispose();
    valueController.dispose();
  }
}
