import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/character.dart';
import '../../../core/state/character_provider.dart';
import '../../../core/utils/platform_paths.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/widgets/glaze_bottom_sheet.dart';
import '../../../shared/widgets/sheet_view.dart';

/// Manages the variations of one character group: list, add (copy of the
/// current card), rename, set-as-cover, and delete. Opened from the character
/// detail sheet. Each variation is a full character card sharing a
/// [Character.variantGroupId]; the representative (order 0) is the list cover.
class CharacterVariationsSheet extends ConsumerWidget {
  final String groupId;

  const CharacterVariationsSheet({super.key, required this.groupId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final variantsAsync = ref.watch(characterVariantsProvider(groupId));
    final variants = variantsAsync.value ?? const <Character>[];

    return SheetView(
      title: 'variations_title'.tr(),
      showHandle: true,
      bodyPadding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      body: ListView(
        children: [
          const SizedBox(height: 8),
          _AddVariationTile(
            onTap: variants.isEmpty
                ? null
                : () => _promptAdd(context, ref, variants.first),
          ),
          for (var i = 0; i < variants.length; i++)
            _VariationTile(
              variant: variants[i],
              isCover: i == 0,
              onTap: () {
                Navigator.of(context, rootNavigator: true).pop();
                context.push('/character/${variants[i].id}/edit');
              },
              onMore: () => _variantActions(context, ref, variants, i),
            ),
        ],
      ),
    );
  }

  void _promptAdd(BuildContext context, WidgetRef ref, Character source) {
    GlazeBottomSheet.show<void>(
      context,
      title: 'variation_add'.tr(),
      input: BottomSheetInput(
        placeholder: 'variation_name'.tr(),
        confirmLabel: 'btn_create'.tr(),
        onConfirm: (val) async {
          Navigator.of(context, rootNavigator: true).pop();
          await ref
              .read(charactersProvider.notifier)
              .addVariant(source, val.trim());
        },
      ),
    );
  }

  void _variantActions(
    BuildContext context,
    WidgetRef ref,
    List<Character> variants,
    int index,
  ) {
    final variant = variants[index];
    final isCover = index == 0;
    GlazeBottomSheet.show<void>(
      context,
      title: variant.variantName?.trim().isNotEmpty == true
          ? variant.variantName!.trim()
          : 'variation_original'.tr(),
      items: [
        BottomSheetItem(
          icon: Icons.drive_file_rename_outline,
          label: 'action_rename'.tr(),
          onTap: () {
            Navigator.of(context, rootNavigator: true).pop();
            _promptRename(context, ref, variant);
          },
        ),
        if (!isCover)
          BottomSheetItem(
            icon: Icons.star_outline_rounded,
            label: 'variation_make_cover'.tr(),
            onTap: () {
              Navigator.of(context, rootNavigator: true).pop();
              final ordered = [
                variant.id,
                for (final v in variants)
                  if (v.id != variant.id) v.id,
              ];
              ref
                  .read(charactersProvider.notifier)
                  .reorderVariants(groupId, ordered);
            },
          ),
        BottomSheetItem(
          icon: Icons.delete_outline,
          label: 'variation_delete'.tr(),
          isDestructive: true,
          onTap: () {
            Navigator.of(context, rootNavigator: true).pop();
            _confirmDelete(context, ref, variant);
          },
        ),
      ],
    );
  }

  void _promptRename(BuildContext context, WidgetRef ref, Character variant) {
    GlazeBottomSheet.show<void>(
      context,
      title: 'action_rename'.tr(),
      input: BottomSheetInput(
        placeholder: 'variation_name'.tr(),
        value: variant.variantName ?? '',
        confirmLabel: 'btn_save'.tr(),
        onConfirm: (val) {
          Navigator.of(context, rootNavigator: true).pop();
          ref
              .read(charactersProvider.notifier)
              .renameVariant(variant.id, val.trim());
        },
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, Character variant) {
    GlazeBottomSheet.show<void>(
      context,
      title: 'variation_delete'.tr(),
      bigInfo: BottomSheetBigInfo(
        icon: Icons.delete_outline,
        description: 'variation_delete_confirm'.tr(),
      ),
      items: [
        BottomSheetItem(
          label: 'btn_delete'.tr(),
          isDestructive: true,
          centered: true,
          onTap: () {
            Navigator.of(context, rootNavigator: true).pop();
            ref.read(charactersProvider.notifier).remove(variant.id);
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

class _AddVariationTile extends StatelessWidget {
  final VoidCallback? onTap;
  const _AddVariationTile({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: context.cs.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                Icon(Icons.add_rounded, size: 20, color: context.cs.primary),
                const SizedBox(width: 12),
                Text(
                  'variation_add'.tr(),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: context.cs.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VariationTile extends StatelessWidget {
  final Character variant;
  final bool isCover;
  final VoidCallback onTap;
  final VoidCallback onMore;

  const _VariationTile({
    required this.variant,
    required this.isCover,
    required this.onTap,
    required this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    final label = variant.variantName?.trim().isNotEmpty == true
        ? variant.variantName!.trim()
        : 'variation_original'.tr();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          onLongPress: onMore,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                _avatar(context),
                const SizedBox(width: 12),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            color: context.cs.onSurface,
                          ),
                        ),
                      ),
                      if (isCover) ...[
                        const SizedBox(width: 8),
                        Icon(
                          Icons.star_rounded,
                          size: 16,
                          color: context.cs.primary,
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.more_horiz_rounded,
                    color: context.cs.onSurfaceVariant,
                  ),
                  onPressed: onMore,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _avatar(BuildContext context) {
    final path = variant.avatarPath;
    final resolved =
        (path != null && path.isNotEmpty) ? resolveGlazeFilePath(path) : null;
    return ClipOval(
      child: SizedBox.square(
        dimension: 44,
        child: resolved != null
            ? Image.file(
                File(resolved),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _placeholder(context),
              )
            : _placeholder(context),
      ),
    );
  }

  Widget _placeholder(BuildContext context) {
    return Container(
      color: context.cs.primary,
      alignment: Alignment.center,
      child: Text(
        variant.name.isNotEmpty ? variant.name[0].toUpperCase() : '?',
        style: const TextStyle(color: Colors.black, fontSize: 16),
      ),
    );
  }
}
