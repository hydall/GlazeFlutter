import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/character.dart';
import '../../../core/models/character_folder.dart';
import '../../../core/state/character_folder_provider.dart';
import '../../../core/state/character_provider.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/widgets/glaze_bottom_sheet.dart';
import 'character_folder_card.dart';
import 'folder_name_dialog.dart';

/// Folders grid for the My Characters root view: a "+ New folder" tile followed
/// by one cover card per folder. Reactive on [characterFoldersProvider].
class CharacterFoldersSection extends ConsumerWidget {
  final ValueChanged<String> onOpenFolder;

  const CharacterFoldersSection({super.key, required this.onOpenFolder});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final folders = ref.watch(characterFoldersProvider).value ?? const [];
    final memberships =
        ref.watch(folderMembershipsProvider).value ?? FolderMemberships.empty;
    final allChars = ref.watch(charactersProvider).value ?? const [];
    final byId = {for (final c in allChars) c.id: c};

    List<Character> membersOf(String folderId) => memberships
        .charsIn(folderId)
        .map((id) => byId[id])
        .whereType<Character>()
        .toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'folders_section_title'.tr().toUpperCase(),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: context.cs.onSurfaceVariant,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 2 / 3.2,
            children: [
              NewFolderCard(onTap: () => _createFolder(context, ref)),
              for (final folder in folders)
                CharacterFolderCard(
                  folder: folder,
                  members: membersOf(folder.id),
                  onTap: () => onOpenFolder(folder.id),
                  onLongPress: () => _folderActions(context, ref, folder),
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _createFolder(BuildContext context, WidgetRef ref) {
    GlazeBottomSheet.show<void>(
      context,
      title: 'folder_create_title'.tr(),
      child: FolderNameDialog(
        confirmLabel: 'btn_create'.tr(),
        onSubmit: (name) =>
            ref.read(characterFolderRepoProvider).create(name: name),
      ),
    );
  }

  void _folderActions(
    BuildContext context,
    WidgetRef ref,
    CharacterFolder folder,
  ) {
    GlazeBottomSheet.show<void>(
      context,
      title: folder.name,
      items: [
        BottomSheetItem(
          icon: Icons.edit_rounded,
          label: 'folder_rename_title'.tr(),
          onTap: () {
            Navigator.of(context, rootNavigator: true).pop();
            _renameFolder(context, ref, folder);
          },
        ),
        BottomSheetItem(
          icon: Icons.delete_rounded,
          label: 'folder_delete_title'.tr(),
          isDestructive: true,
          onTap: () {
            Navigator.of(context, rootNavigator: true).pop();
            _confirmDelete(context, ref, folder);
          },
        ),
      ],
    );
  }

  void _renameFolder(
    BuildContext context,
    WidgetRef ref,
    CharacterFolder folder,
  ) {
    GlazeBottomSheet.show<void>(
      context,
      title: 'folder_rename_title'.tr(),
      child: FolderNameDialog(
        initialName: folder.name,
        confirmLabel: 'btn_save'.tr(),
        onSubmit: (name) =>
            ref.read(characterFolderRepoProvider).rename(folder.id, name),
      ),
    );
  }

  void _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    CharacterFolder folder,
  ) {
    GlazeBottomSheet.show<void>(
      context,
      title: 'folder_delete_title'.tr(),
      bigInfo: BottomSheetBigInfo(
        icon: Icons.delete_outline,
        description: 'folder_delete_confirm'.tr(),
      ),
      items: [
        BottomSheetItem(
          label: 'btn_delete'.tr(),
          isDestructive: true,
          centered: true,
          onTap: () {
            Navigator.of(context, rootNavigator: true).pop();
            ref.read(characterFolderRepoProvider).delete(folder.id);
          },
        ),
        BottomSheetItem(
          label: 'btn_cancel'.tr(),
          centered: true,
          onTap: () => Navigator.of(context, rootNavigator: true).pop(),
        ),
      ],
    );
  }
}
