import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../core/models/gallery_entry.dart';
import '../../shared/widgets/glaze_bottom_sheet.dart';
import '../../shared/widgets/glaze_scaffold.dart';
import '../../shared/widgets/glaze_error_dialog.dart';
import '../../shared/widgets/glaze_toast.dart';
import 'gallery_provider.dart';

class GalleryScreen extends ConsumerWidget {
  final String charId;
  const GalleryScreen({super.key, required this.charId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final galleryAsync = ref.watch(galleryProvider(charId));

    return GlazeScaffold(
      title: 'menu_image_viewer'.tr(),
      onBack: () {
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/characters');
        }
      },
      body: galleryAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('${'title_error'.tr()}: $e')),
        data: (entries) {
          if (entries.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.photo_library_outlined,
                      size: 64,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                  const SizedBox(height: 16),
                  Text('no_results'.tr(),
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          )),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: () => _addImage(context, ref),
                    icon: const Icon(Icons.add_photo_alternate),
                    label: Text('action_import'.tr()),
                  ),
                ],
              ),
            );
          }
          return Column(
            children: [
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.all(8),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 4,
                    mainAxisSpacing: 4,
                  ),
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    return _GalleryTile(
                      entry: entry,
                      charId: charId,
                      onTap: () =>
                          _openViewer(context, ref, entries, index),
                    );
                  },
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Row(
                    children: [
                      FilledButton.icon(
                        onPressed: () => _addImage(context, ref),
                        icon: const Icon(Icons.add_photo_alternate),
                        label: Text('action_import'.tr()),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _addImage(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final path = result.files.single.path;
    if (path == null) return;

    try {
      final service = await ref.read(galleryServiceProvider.future);
      await service.addImage(charId, path);
      ref.invalidate(galleryProvider(charId));
    } catch (e) {
      if (context.mounted) {
        GlazeErrorDialog.show(context, e, prefix: '${'settings_err_failed'.tr()} ');
      }
    }
  }

  void _openViewer(BuildContext context, WidgetRef ref,
      List<GalleryEntry> entries, int initialIndex) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _GalleryViewer(
          charId: charId,
          entries: entries,
          initialIndex: initialIndex,
        ),
      ),
    ).then((_) => ref.invalidate(galleryProvider(charId)));
  }
}

class _GalleryTile extends ConsumerWidget {
  final GalleryEntry entry;
  final String charId;
  final VoidCallback onTap;

  const _GalleryTile({
    required this.entry,
    required this.charId,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: () => _showActions(context, ref),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.file(
              File(entry.imagePath),
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Icon(Icons.broken_image,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
            if (entry.label != null && entry.label!.isNotEmpty)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  color: Colors.black54,
                  child: Text(
                    entry.label!,
                    style: const TextStyle(color: Colors.white, fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showActions(BuildContext context, WidgetRef ref) {
    GlazeBottomSheet.show<void>(
      context,
      title: 'avatar'.tr(),
      items: [
        BottomSheetItem(
          icon: Icons.face,
          label: 'avatar'.tr(),
          onTap: () async {
            Navigator.pop(context);
            try {
              final service =
                  await ref.read(galleryServiceProvider.future);
              await service.setAsAvatar(entry.characterId, entry.id);
              if (context.mounted) {
                GlazeToast.show(context, 'import_success'.tr());
              }
            } catch (e) {
              if (context.mounted) {
                GlazeErrorDialog.show(context, e, prefix: '${'settings_err_failed'.tr()} ');
              }
            }
          },
        ),
        BottomSheetItem(
          icon: Icons.delete,
          iconColor: Colors.red,
          label: 'action_delete_msg'.tr(),
          isDestructive: true,
          onTap: () async {
            Navigator.pop(context);
            try {
              final service =
                  await ref.read(galleryServiceProvider.future);
              await service.deleteImage(entry.characterId, entry.id);
              ref.invalidate(galleryProvider(charId));
            } catch (e) {
              if (context.mounted) {
                GlazeErrorDialog.show(context, e, prefix: '${'settings_err_failed'.tr()} ');
              }
            }
          },
        ),
      ],
    );
  }
}

class _GalleryViewer extends ConsumerStatefulWidget {
  final String charId;
  final List<GalleryEntry> entries;
  final int initialIndex;

  const _GalleryViewer({
    required this.charId,
    required this.entries,
    required this.initialIndex,
  });

  @override
  ConsumerState<_GalleryViewer> createState() => _GalleryViewerState();
}

class _GalleryViewerState extends ConsumerState<_GalleryViewer> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entries[_currentIndex];

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          '${_currentIndex + 1} / ${widget.entries.length}',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.face),
            tooltip: 'avatar'.tr(),
            onPressed: () async {
              try {
                final service =
                    await ref.read(galleryServiceProvider.future);
                await service.setAsAvatar(entry.characterId, entry.id);
                if (context.mounted) {
                  GlazeToast.show(context, 'import_success'.tr());
                }
              } catch (e) {
                if (context.mounted) {
                  GlazeErrorDialog.show(context, e, prefix: '${'settings_err_failed'.tr()} ');
                }
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            tooltip: 'action_delete_msg'.tr(),
            onPressed: () {
              GlazeBottomSheet.show<void>(
                context,
                title: '${'action_delete_msg'.tr()}?',
                bigInfo: BottomSheetBigInfo(
                  icon: Icons.delete_outline,
                  description: 'action_delete_msg'.tr(),
                ),
                items: [
                  BottomSheetItem(
                    label: 'action_delete_msg'.tr(),
                    isDestructive: true,
                    centered: true,
                    onTap: () async {
                      Navigator.pop(context);
                      try {
                        final service =
                            await ref.read(galleryServiceProvider.future);
                        await service.deleteImage(entry.characterId, entry.id);
                        ref.invalidate(galleryProvider(widget.charId));
                        if (context.mounted) Navigator.pop(context);
                      } catch (e) {
                        if (context.mounted) {
                          GlazeErrorDialog.show(context, e, prefix: '${'settings_err_failed'.tr()} ');
                        }
                      }
                    },
                  ),
                  BottomSheetItem(
                    label: 'btn_cancel'.tr(),
                    centered: true,
                    onTap: () => Navigator.pop(context),
                  ),
                ],
              );
            },
          ),
        ],
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.entries.length,
        onPageChanged: (index) => setState(() => _currentIndex = index),
        itemBuilder: (context, index) {
          final e = widget.entries[index];
          return InteractiveViewer(
            minScale: 0.5,
            maxScale: 4.0,
            child: Center(
              child: Image.file(
                File(e.imagePath),
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.broken_image, color: Colors.white54, size: 64),
                    const SizedBox(height: 8),
                    Text('no_results'.tr(),
                        style: const TextStyle(color: Colors.white54)),
                  ],
                ),
              ),
            ),
          );
        },
      ),
      bottomNavigationBar: entry.label != null && entry.label!.isNotEmpty
          ? BottomAppBar(
              color: Colors.black87,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  entry.label!,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : null,
    );
  }
}
