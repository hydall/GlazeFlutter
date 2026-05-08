import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/theme/app_colors.dart';
import '../../../shared/widgets/glaze_toast.dart';
import '../catalog_models.dart';
import '../catalog_provider.dart';
import '../services/datacat_provider.dart';
import '../services/janitor_provider.dart';
import '../services/janny_provider.dart';
import '../services/chub_provider.dart';

class CatalogPreviewSheet extends ConsumerStatefulWidget {
  final CatalogItem item;
  const CatalogPreviewSheet({super.key, required this.item});

  @override
  ConsumerState<CatalogPreviewSheet> createState() => _CatalogPreviewSheetState();
}

class _CatalogPreviewSheetState extends ConsumerState<CatalogPreviewSheet> {
  bool _loading = false;
  bool _importing = false;
  DownloadedCharacter? _downloaded;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchCharacter();
  }

  Future<void> _fetchCharacter() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final state = ref.read(catalogProvider);
      final provider = state.activeProvider;
      DownloadedCharacter result;
      switch (provider) {
        case CatalogProvider.janitor:
          result = await janitorFetchCharacter(widget.item.id);
        case CatalogProvider.janny:
          result = await jannyFetchCharacter(widget.item.id, widget.item.slug);
        case CatalogProvider.datacat:
          result = await datacatGetCharacter(widget.item.id);
        case CatalogProvider.chub:
          result = await chubGetCharacter(
            widget.item.fullPath ?? widget.item.id,
          );
      }
      if (mounted)
        setState(() {
          _downloaded = result;
          _loading = false;
        });
    } catch (e) {
      if (mounted)
        setState(() {
          _error = e.toString();
          _loading = false;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading)
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(
          child: CircularProgressIndicator(color: AppColors.accent),
        ),
      );
    if (_error != null) return _buildError();
    if (_downloaded == null) return const SizedBox.shrink();
    return _buildPreview();
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 48,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 16),
            Text(
              _error ?? 'Unknown error',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: _fetchCharacter,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Retry',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview() {
    final char = _downloaded!.charData;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(
                  width: 120,
                  height: 160,
                  child: _downloaded!.avatarUrl != null
                      ? CachedNetworkImage(
                          imageUrl: _downloaded!.avatarUrl!,
                          fit: BoxFit.cover,
                          errorWidget: (_, _, _) => _avatarPlaceholder(),
                        )
                      : _avatarPlaceholder(),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      char.name,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if (char.creator.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        'by @${char.creator}',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                    if (char.tags.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: char.tags.take(6).map((t) {
                          final isNsfw = t.toUpperCase() == 'NSFW';
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: isNsfw
                                  ? Colors.red.withValues(alpha: 0.2)
                                  : AppColors.accent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              t,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: isNsfw
                                    ? Colors.redAccent
                                    : AppColors.accent,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (char.creatorNotes.isNotEmpty) ...[
            _sectionTitle('Short Description'),
            const SizedBox(height: 4),
            Text(
              char.creatorNotes,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (char.description.isNotEmpty) ...[
            _sectionTitle('Description'),
            const SizedBox(height: 4),
            Text(
              char.description,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (char.scenario.isNotEmpty) ...[
            _sectionTitle('Scenario'),
            const SizedBox(height: 4),
            Text(
              char.scenario,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (char.firstMes.isNotEmpty) ...[
            _sectionTitle('First Message'),
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                char.firstMes,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          _ImportButton(importing: _importing, onTap: _doImport),
        ],
      ),
    );
  }

  Widget _avatarPlaceholder() {
    return Container(
      color: AppColors.accent.withValues(alpha: 0.2),
      child: Center(
        child: Text(
          _downloaded!.charData.name.isNotEmpty
              ? _downloaded!.charData.name[0].toUpperCase()
              : '?',
          style: const TextStyle(
            fontSize: 40,
            color: AppColors.accent,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: AppColors.textPrimary,
        fontSize: 14,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Future<void> _doImport() async {
    if (_downloaded == null || _importing) return;
    setState(() => _importing = true);
    try {
      await ref.read(catalogProvider.notifier).importCharacter(_downloaded!);
      if (mounted) {
        Navigator.pop(context);
        GlazeToast.show(context, 'Imported ${_downloaded!.charData.name}');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _importing = false);
        GlazeToast.error(context, 'Import failed: ', e);
      }
    }
  }
}

class _ImportButton extends StatelessWidget {
  final bool importing;
  final VoidCallback onTap;

  const _ImportButton({required this.importing, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: importing ? null : onTap,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: importing
              ? AppColors.accent.withValues(alpha: 0.5)
              : AppColors.accent,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Center(
          child: importing
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                )
              : const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.download_rounded, color: Colors.white, size: 22),
                    SizedBox(width: 8),
                    Text(
                      'Import Character',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
