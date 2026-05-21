import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'glaze_bottom_sheet.dart';

class GenericEditorField {
  final String key;
  final String label;
  final String type; // 'text', 'number', 'tags', 'textarea', 'greeting_list', 'select', 'info'
  final bool expandable;
  final String? helpTerm;
  final String? placeholder;
  final int? rows;
  final List<Map<String, dynamic>>? options; // [{'label': 'System', 'value': 'system'}]
  final String? text;
  final bool Function(Map<String, dynamic> item)? showIf;

  const GenericEditorField({
    required this.key,
    required this.label,
    this.type = 'text',
    this.expandable = false,
    this.helpTerm,
    this.placeholder,
    this.rows,
    this.options,
    this.text,
    this.showIf,
  });
}

class GenericEditorSection {
  final String? title;
  final List<GenericEditorField> fields;

  const GenericEditorSection({
    this.title,
    required this.fields,
  });
}

class GenericEditor extends StatefulWidget {
  final Map<String, dynamic> item;
  final List<GenericEditorSection> config;
  final bool showAvatar;
  final String avatarField;
  final String avatarHint;
  final String avatarPlaceholder;
  final Future<void> Function()? onAvatarTap;
  final void Function(Map<String, dynamic> values) onChanged;
  final void Function(String field, int index)? onOpenFsEditor;
  final bool useWindows;
  final bool scrollable;
  final void Function(Map<String, dynamic> values)? onSave;
  final Duration debounceDuration;
  final EdgeInsetsGeometry? padding;

  const GenericEditor({
    super.key,
    required this.item,
    required this.config,
    this.showAvatar = false,
    this.avatarField = 'avatarPath',
    this.avatarHint = 'Tap to change avatar',
    this.avatarPlaceholder = '?',
    this.onAvatarTap,
    required this.onChanged,
    this.onOpenFsEditor,
    this.useWindows = true,
    this.scrollable = true,
    this.onSave,
    this.debounceDuration = const Duration(milliseconds: 1000),
    this.padding,
  });

  @override
  State<GenericEditor> createState() => _GenericEditorState();
}

class _GenericEditorState extends State<GenericEditor> {
  late Map<String, dynamic> _localItem;
  final Map<String, TextEditingController> _controllers = {};
  Timer? _saveTimer;
  bool _hasPendingSave = false;

  @override
  void initState() {
    super.initState();
    _localItem = Map.from(widget.item);
    _initControllers();
  }

  @override
  void didUpdateWidget(GenericEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Minimal sync to prevent controller overwrites, usually item shouldn't change identity often
    bool changed = false;
    for (final k in widget.item.keys) {
      if (widget.item[k] != _localItem[k]) {
        _localItem[k] = widget.item[k];
        changed = true;
      }
    }
    if (changed) {
      for (final section in widget.config) {
        for (final field in section.fields) {
          if (field.type == 'text' || field.type == 'textarea' || field.type == 'number') {
            final val = _localItem[field.key]?.toString() ?? '';
            if (_controllers[field.key]?.text != val) {
              _controllers[field.key]?.text = val;
            }
          } else if (field.type == 'tags') {
            final val = _localItem[field.key];
            final strVal = (val is List) ? val.join(', ') : '';
            if (_controllers[field.key]?.text != strVal) {
              _controllers[field.key]?.text = strVal;
            }
          }
        }
      }
    }
  }

  void _initControllers() {
    for (final section in widget.config) {
      for (final field in section.fields) {
        if (['text', 'number', 'textarea', 'tags'].contains(field.type)) {
          final val = _localItem[field.key];
          String strVal = '';
          if (field.type == 'tags' && val is List) {
            strVal = val.join(', ');
          } else if (val != null) {
            strVal = val.toString();
          }
          final ctrl = TextEditingController(text: strVal);
          ctrl.addListener(() {
            _updateField(field.key, field.type, ctrl.text);
          });
          _controllers[field.key] = ctrl;
        }
      }
    }
  }

  void _updateField(String key, String type, String text) {
    if (type == 'number') {
      _localItem[key] = num.tryParse(text) ?? _localItem[key];
    } else if (type == 'tags') {
      _localItem[key] = text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    } else {
      _localItem[key] = text;
    }
    widget.onChanged(_localItem);
    _scheduleSave();
  }

  void _scheduleSave() {
    if (widget.onSave == null) return;
    _hasPendingSave = true;
    _saveTimer?.cancel();
    _saveTimer = Timer(widget.debounceDuration, () {
      _hasPendingSave = false;
      widget.onSave!(_localItem);
    });
  }

  @override
  void dispose() {
    for (final ctrl in _controllers.values) {
      ctrl.dispose();
    }
    if (_hasPendingSave) {
      _saveTimer?.cancel();
      widget.onSave?.call(_localItem);
    }
    super.dispose();
  }

  // --- Greetings Logic ---

  List<String> get _allGreetings {
    final list = <String>[];
    list.add((_localItem['first_mes'] as String?) ?? '');
    final alt = _localItem['alternate_greetings'];
    if (alt is List) {
      list.addAll(alt.cast<String>());
    }
    return list;
  }

  void _addGreeting() {
    if (_localItem['alternate_greetings'] == null) {
      _localItem['alternate_greetings'] = <String>[];
    }
    final alt = _localItem['alternate_greetings'] as List;
    alt.add('');
    widget.onChanged(_localItem);
    _scheduleSave();
    setState(() {});
    if (widget.onOpenFsEditor != null) {
      widget.onOpenFsEditor!('alternate_greetings', alt.length); // index represents position
    }
  }

  void _confirmDeleteGreeting(int index) {
    GlazeBottomSheet.show(
      context,
      title: 'Delete?',
      items: [
        BottomSheetItem(
          label: 'Yes',
          icon: Icons.check,
          iconColor: const Color(0xFFFF4444),
          isDestructive: true,
          onTap: () {
            Navigator.pop(context);
            _performDeleteGreeting(index);
          },
        ),
        BottomSheetItem(
          label: 'No',
          icon: Icons.close,
          onTap: () => Navigator.pop(context),
        ),
      ],
    );
  }

  void _performDeleteGreeting(int index) {
    if (index == 0) {
      final alt = _localItem['alternate_greetings'];
      if (alt is List && alt.isNotEmpty) {
        _localItem['first_mes'] = alt.removeAt(0);
      } else {
        _localItem['first_mes'] = '';
      }
    } else {
      final altIndex = index - 1;
      final alt = _localItem['alternate_greetings'];
      if (alt is List && alt.length > altIndex) {
        alt.removeAt(altIndex);
      }
    }
    widget.onChanged(_localItem);
    _scheduleSave();
    setState(() {});
  }

  // --- Selectors ---

  void _openSelectSelector(GenericEditorField field) {
    final currentVal = _localItem[field.key];
    final items = field.options?.map((opt) {
      final isSelected = currentVal == opt['value'];
      return BottomSheetItem(
        label: opt['label'] as String? ?? opt['value'].toString(),
        icon: isSelected ? Icons.check : null,
        onTap: () {
          Navigator.pop(context);
          _localItem[field.key] = opt['value'];
          widget.onChanged(_localItem);
          _scheduleSave();
          setState(() {});
        },
      );
    }).toList() ?? [];

    GlazeBottomSheet.show(
      context,
      title: field.label,
      items: items,
    );
  }

  String _getSelectedLabel(GenericEditorField field) {
    final val = _localItem[field.key];
    final opt = field.options?.firstWhere((o) => o['value'] == val, orElse: () => {});
    return (opt?['label'] as String?) ?? val?.toString() ?? '';
  }

  // --- UI ---

  @override
  Widget build(BuildContext context) {
    final children = [
      if (widget.showAvatar) _buildAvatarCard(),
      for (int sIdx = 0; sIdx < widget.config.length; sIdx++) _buildSection(widget.config[sIdx]),
    ];

    Widget body;
    if (widget.scrollable) {
      body = ListView(
        padding: widget.padding ?? EdgeInsets.fromLTRB(
          16, 
          MediaQuery.of(context).padding.top + 16, 
          16, 
          MediaQuery.of(context).padding.bottom + 60
        ),
        children: children,
      );
    } else {
      body = Padding(
        padding: widget.padding ?? EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      );
    }

    return Material(
      type: MaterialType.transparency,
      child: body,
    );
  }

  Widget _buildAvatarCard() {
    final avatarPath = _localItem[widget.avatarField] as String?;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: GestureDetector(
        onTap: widget.onAvatarTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: Container(
                  color: context.cs.surfaceContainerHighest,
                  child: avatarPath != null && avatarPath.isNotEmpty
                      ? Image.file(File(avatarPath), fit: BoxFit.cover)
                      : Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFF66CCFF), context.cs.primary],
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            widget.avatarPlaceholder.toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 96,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 30),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.black54, Colors.transparent],
                    ),
                  ),
                  child: const Text(
                    'AVATAR',
                    style: TextStyle(
                      color: Color(0xE6FFFFFF),
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 30, 16, 20),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Colors.black54, Colors.transparent],
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    widget.avatarHint,
                    style: const TextStyle(
                      color: Color(0xE6FFFFFF),
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSection(GenericEditorSection section) {
    final visibleFields = section.fields
        .where((f) => f.showIf == null || f.showIf!(_localItem))
        .toList();

    if (visibleFields.isEmpty && (section.title == null || section.title!.isEmpty)) {
      return const SizedBox();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: widget.useWindows
          ? BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: context.cs.outlineVariant),
            )
          : null,
      clipBehavior: widget.useWindows ? Clip.antiAlias : Clip.none,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (section.title != null && section.title!.isNotEmpty)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.03))),
              ),
              child: Text(
                section.title!.toUpperCase(),
                style: TextStyle(
                  color: context.cs.primary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          for (int fIdx = 0; fIdx < visibleFields.length; fIdx++)
            _buildField(visibleFields[fIdx], fIdx == visibleFields.length - 1),
        ],
      ),
    );
  }

  Widget _buildField(GenericEditorField field, bool isLast) {
    if (field.showIf != null && !field.showIf!(_localItem)) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: widget.useWindows 
          ? const EdgeInsets.all(16)
          : const EdgeInsets.symmetric(vertical: 12),
      decoration: (isLast || !widget.useWindows)
          ? null
          : BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (field.type != 'greeting_list') _buildLabelRow(field),
          if (field.type != 'greeting_list') const SizedBox(height: 10),
          _buildInput(field),
        ],
      ),
    );
  }

  Widget _buildLabelRow(GenericEditorField field) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Text(
              field.label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                 color: context.cs.onSurface,
              ),
            ),
            if (field.helpTerm != null) ...[
              const SizedBox(width: 8),
              Icon(Icons.help_outline, size: 16, color: context.cs.onSurfaceVariant),
            ]
          ],
        ),
        if (field.expandable && widget.onOpenFsEditor != null)
          GestureDetector(
            onTap: () => widget.onOpenFsEditor!(field.key, -1),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.open_in_full, size: 20, color: context.cs.primary),
            ),
          )
      ],
    );
  }

  Widget _buildInput(GenericEditorField field) {
    switch (field.type) {
      case 'text':
      case 'number':
      case 'tags':
      case 'textarea':
        return _buildTextField(field);
      case 'greeting_list':
        return _buildGreetingList(field);
      case 'select':
        return _buildSelect(field);
      case 'info':
        return Text(
          field.text ?? _localItem[field.key]?.toString() ?? '',
          style: TextStyle(
            color: context.cs.onSurfaceVariant,
            fontSize: 14,
            height: 1.5,
          ),
        );
      default:
        return const SizedBox();
    }
  }

  Widget _buildTextField(GenericEditorField field) {
    final ctrl = _controllers[field.key];
    if (ctrl == null) return const SizedBox();

    final isTextarea = field.type == 'textarea';
    return TextField(
      controller: ctrl,
      maxLines: isTextarea ? (field.rows ?? 3) : 1,
      minLines: isTextarea ? (field.rows ?? 3) : 1,
      keyboardType: field.type == 'number'
          ? TextInputType.number
          : isTextarea
              ? TextInputType.multiline
              : TextInputType.text,
      textInputAction: isTextarea ? TextInputAction.newline : null,
      style: TextStyle(fontSize: 15, color: context.cs.onSurface),
      decoration: InputDecoration(
        hintText: field.placeholder,
        hintStyle: TextStyle(color: context.cs.onSurfaceVariant.withValues(alpha: 0.5)),
        filled: true,
        fillColor: Colors.black.withValues(alpha: 0.2),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: context.cs.primary),
        ),
      ),
    );
  }

  Widget _buildGreetingList(GenericEditorField field) {
    final greets = _allGreetings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildLabelRow(field),
        const SizedBox(height: 10),
        for (int gIdx = 0; gIdx < greets.length; gIdx++)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              border: Border.all(color: context.cs.outlineVariant),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '#${gIdx + 1}',
                      style: TextStyle(
                        fontSize: 13,
                        color: context.cs.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Row(
                      children: [
                        GestureDetector(
                          onTap: () {
                            if (widget.onOpenFsEditor != null) {
                              widget.onOpenFsEditor!('first_mes', gIdx);
                            }
                          },
                          child: Icon(Icons.edit, size: 18, color: context.cs.primary),
                        ),
                        const SizedBox(width: 12),
                        GestureDetector(
                          onTap: () => _confirmDeleteGreeting(gIdx),
                          child: const Icon(Icons.delete, size: 18, color: Color(0xFFFF4444)),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: () {
                    if (widget.onOpenFsEditor != null) {
                      widget.onOpenFsEditor!('first_mes', gIdx);
                    }
                  },
                  child: Text(
                    greets[gIdx].isEmpty ? 'Empty' : greets[gIdx],
                    style: TextStyle(
                      fontSize: 14,
                        color: context.cs.onSurface.withValues(alpha: 0.9),
                      height: 1.4,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        GestureDetector(
          onTap: _addGreeting,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.cs.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add, size: 20, color: context.cs.primary),
                SizedBox(width: 8),
                Text(
                  'Add Message',
                  style: TextStyle(
                    color: context.cs.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSelect(GenericEditorField field) {
    return GestureDetector(
      onTap: () => _openSelectSelector(field),
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: context.cs.surfaceContainerHighest,
          border: Border.all(color: context.cs.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _getSelectedLabel(field),
              style: TextStyle(fontSize: 15, color: context.cs.onSurface),
            ),
            Icon(Icons.arrow_drop_down, color: context.cs.onSurfaceVariant.withValues(alpha: 0.5)),
          ],
        ),
      ),
    );
  }
}
