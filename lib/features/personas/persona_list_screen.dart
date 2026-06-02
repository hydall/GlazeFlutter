import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../core/models/persona.dart';
import '../../core/state/active_selection_provider.dart';
import '../../core/state/db_provider.dart';
import 'persona_connections_sheet.dart';
import 'persona_list_provider.dart';
import '../../core/utils/id_generator.dart';
import '../../core/utils/time_helpers.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/widgets/generic_editor.dart';
import '../../shared/widgets/glaze_bottom_sheet.dart';
import '../../shared/widgets/glaze_scaffold.dart';
import '../../shared/widgets/help_tip.dart';
import '../../shared/widgets/sheet_view.dart';


class PersonaListScreen extends ConsumerWidget {
  final bool startExpanded;
  const PersonaListScreen({super.key, this.startExpanded = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final personas = ref.watch(personaListProvider);

    return SheetView(
      startExpanded: startExpanded,
      showRouteBackground: false,
      titleWidget: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'menu_personas'.tr(),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: context.cs.onSurface,
            ),
          ),
          const HelpTip(term: 'persona'),
        ],
      ),
      showBack: true,
      onBack: startExpanded
          ? () => context.go('/tools')
          : () => Navigator.of(context).maybePop(),
      actions: [
        SheetViewAction(
          icon: const Icon(Icons.add, size: 20),
          tooltip: "${'create_new'.tr()} ${'tab_personas'.tr()}",
          onPressed: () => _showEditor(context, ref),
        ),
      ],
      body: personas.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text("${'title_error'.tr()}: $e")),
        data: (list) => list.isEmpty
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('no_results'.tr()),
                    const SizedBox(height: 8),
                    FilledButton.tonal(
                      onPressed: () => _showEditor(context, ref),
                      child: Text("${'create_new'.tr()} ${'tab_personas'.tr()}"),
                    ),
                  ],
                ),
              )
            : Builder(
                builder: (context) => ListView.builder(
                  padding: EdgeInsets.fromLTRB(16, startExpanded ? 16 : 0, 16, 16).add(
                    EdgeInsets.only(
                      top: MediaQuery.paddingOf(context).top,
                      bottom: MediaQuery.paddingOf(context).bottom,
                    ),
                  ),
                  itemCount: list.length,
                  itemBuilder: (_, i) => _PersonaTile(persona: list[i]),
                ),
              ),
      ),
    );
  }

  void _showEditor(BuildContext context, WidgetRef ref, [Persona? existing]) {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => _PersonaEditorScreen(existing: existing),
      ),
    );
  }
}

class _PersonaTile extends ConsumerWidget {
  final Persona persona;
  const _PersonaTile({required this.persona});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeId = ref.watch(activePersonaIdProvider);
    final isActive = activeId == persona.id;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isActive
            ? context.cs.primary.withValues(alpha: 0.12)
            : Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isActive
              ? context.cs.primary.withValues(alpha: 0.5)
              : context.cs.outline,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        onTap: () =>
            setActivePersona(ref, isActive ? null : persona.id),
        leading: CircleAvatar(
          radius: 24,
          backgroundColor: context.cs.primary.withValues(alpha: 0.18),
          backgroundImage: persona.avatarPath != null
              ? FileImage(File(persona.avatarPath!))
              : null,
          child: persona.avatarPath == null
              ? Text(
                  persona.name.isNotEmpty ? persona.name[0].toUpperCase() : '?',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: context.cs.onSurface,
                  ),
                )
              : null,
        ),
        title: Text(persona.name),
        subtitle: persona.prompt != null && persona.prompt!.isNotEmpty
            ? Text(
                persona.prompt!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              )
            : Text(
                'no_prompt'.tr(),
                style: TextStyle(color: context.cs.onSurfaceVariant),
              ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.link, size: 18),
              tooltip: 'header_connections'.tr(),
              onPressed: () => showPersonaConnections(context, persona.id),
            ),
            IconButton(
              icon: const Icon(Icons.more_vert, size: 20),
              tooltip: 'header_more'.tr(),
              onPressed: () {
                GlazeBottomSheet.show(
                  context,
                  title: "${'tab_personas'.tr()} ${'header_more'.tr()}",
                  items: [
                    BottomSheetItem(
                      label: 'action_edit'.tr(),
                      icon: Icons.edit,
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.of(context, rootNavigator: true).push(
                          MaterialPageRoute<void>(
                            builder: (_) => _PersonaEditorScreen(existing: persona),
                          ),
                        );
                      },
                    ),
                    BottomSheetItem(
                      label: 'action_delete'.tr(),
                      icon: Icons.delete,
                      isDestructive: true,
                      onTap: () {
                        Navigator.pop(context);
                        ref.read(personaListProvider.notifier).remove(persona.id);
                      },
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _PersonaEditorScreen extends ConsumerStatefulWidget {
  final Persona? existing;
  const _PersonaEditorScreen({this.existing});

  @override
  ConsumerState<_PersonaEditorScreen> createState() =>
      _PersonaEditorScreenState();
}

class _PersonaEditorScreenState extends ConsumerState<_PersonaEditorScreen> {
  late Map<String, dynamic> _item;
  late final String _personaId;
  late final int _createdAt;

  List<GenericEditorSection> get _config => [
        GenericEditorSection(
          title: 'section_basic_info'.tr(),
          fields: [
            GenericEditorField(
              key: 'name',
              label: 'label_name'.tr(),
              placeholder: 'placeholder_enter_name'.tr(),
            ),
            GenericEditorField(
              key: 'prompt',
              label: "${'tab_personas'.tr()} ${'label_char_prompt'.tr().replaceAll(RegExp(r'Character |Персонажа ', caseSensitive: false), '')}",
              type: 'textarea',
              rows: 12,
              placeholder: 'placeholder_prompt_text'.tr(),
            ),
          ],
        ),
      ];

  @override
  void initState() {
    super.initState();
    _personaId = widget.existing?.id ?? generateId();
    _createdAt = widget.existing?.createdAt ?? currentTimestampSeconds();
    _item = {
      'name': widget.existing?.name ?? '',
      'prompt': widget.existing?.prompt ?? '',
      'avatarPath': widget.existing?.avatarPath,
    };
  }

  Future<void> _pickAvatar() async {
    final result = await FilePicker.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final filePath = result.files.first.path;
    if (filePath == null) return;

    final imageStorage = await ref.read(imageStorageProvider.future);
    final bytes = await File(filePath).readAsBytes();
    final savedPath = await imageStorage.saveAvatar('persona_$_personaId', bytes);
    await FileImage(File(savedPath)).evict();
    final thumbPath = imageStorage.thumbnailPath(savedPath);
    if (thumbPath != null) await FileImage(File(thumbPath)).evict();

    setState(() {
      _item['avatarPath'] = savedPath;
    });
    _save(_item);
  }

  void _save(Map<String, dynamic> values) {
    final name = (values['name'] as String?)?.trim() ?? '';
    final promptStr = (values['prompt'] as String?)?.trim() ?? '';

    final persona = Persona(
      id: _personaId,
      name: name.isEmpty ? 'unnamed_entry'.tr().split(' ')[0] : name,
      prompt: promptStr.isEmpty ? null : promptStr,
      avatarPath: values['avatarPath'] as String?,
      createdAt: _createdAt,
    );

    ref.read(personaListProvider.notifier).updatePersona(persona);
  }

  @override
  Widget build(BuildContext context) {
    return GlazeScaffold(
      title: widget.existing != null ? "${'action_edit'.tr()} ${'tab_personas'.tr()}" : "${'create_new'.tr()} ${'tab_personas'.tr()}",
      onBack: () => Navigator.of(context).pop(),
      body: GenericEditor(
        item: _item,
        config: _config,
        showAvatar: true,
        avatarHint: 'hint_change_avatar'.tr(),
        onAvatarTap: _pickAvatar,
        onChanged: (values) {
          _item = values;
        },
        onSave: (values) {
          _save(values);
        },
      ),
    );
  }
}
