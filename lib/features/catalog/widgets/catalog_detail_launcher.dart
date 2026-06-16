import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/character.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/widgets/glaze_error_dialog.dart';
import '../../character_list/character_detail_screen.dart';
import '../catalog_models.dart';
import '../catalog_provider.dart';
import '../services/chub_provider.dart';
import '../services/datacat_provider.dart';
import '../services/janitor_provider.dart';
import '../services/janny_provider.dart';

/// Fetches a catalog item's full character data and presents
/// `CharacterDetailScreen` in preview mode (Import FAB, no destructive
/// actions).
class CatalogDetailLauncher extends ConsumerStatefulWidget {
  final CatalogItem item;
  final CatalogProvider provider;

  const CatalogDetailLauncher({
    super.key,
    required this.item,
    required this.provider,
  });

  @override
  ConsumerState<CatalogDetailLauncher> createState() =>
      _CatalogDetailLauncherState();
}

class _CatalogDetailLauncherState
    extends ConsumerState<CatalogDetailLauncher> {
  DownloadedCharacter? _downloaded;
  String? _error;
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      DownloadedCharacter result;
      switch (widget.provider) {
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
      if (mounted) setState(() => _downloaded = result);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Character _toCharacter(DownloadedCharacter d) {
    final data = d.charData;
    return Character(
      id: 'preview:${widget.item.id}',
      name: data.name.isEmpty ? widget.item.name : data.name,
      description: data.description,
      personality: data.personality,
      scenario: data.scenario,
      firstMes: data.firstMes,
      mesExample: data.mesExample,
      systemPrompt: data.systemPrompt,
      postHistoryInstructions: data.postHistoryInstructions,
      creator:
          data.creator.isEmpty ? widget.item.creator : data.creator,
      creatorNotes: data.creatorNotes,
      tags: data.tags.isEmpty ? widget.item.tags : data.tags,
      alternateGreetings: data.alternateGreetings,
    );
  }

  Future<void> _doImport() async {
    final downloaded = _downloaded;
    if (downloaded == null || _importing) return;
    setState(() => _importing = true);
    try {
      final importedCharId = await ref
          .read(catalogProvider.notifier)
          .importCharacter(downloaded);
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop(importedCharId);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _importing = false);
        GlazeErrorDialog.show(context, e, prefix: 'Import failed: ');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return _ErrorView(message: _error!, onRetry: () {
        setState(() => _error = null);
        _fetch();
      });
    }
    final downloaded = _downloaded;
    if (downloaded == null) {
      return const _LoadingView();
    }
    final char = _toCharacter(downloaded);
    final avatarUrl =
        downloaded.avatarUrl ?? widget.item.avatarUrl;
    return CharacterDetailScreen(
      charId: char.id,
      previewCharacter: char,
      previewAvatarUrl: avatarUrl,
      previewSourceUrl: _sourceUrl(),
      previewAuthorUrl: _authorUrl(),
      onImport: _doImport,
      importing: _importing,
    );
  }

  /// External URL of the character's page on its source site. Only Janitor
  /// exposes a stable per-character web URL today; other providers return null
  /// (the "open in browser" button is then hidden).
  String? _sourceUrl() {
    if (widget.provider != CatalogProvider.janitor) return null;
    final id = widget.item.id;
    if (id.isEmpty) return null;
    final slug = widget.item.slug;
    if (slug != null && slug.isNotEmpty && slug != id) {
      return 'https://janitorai.com/characters/${id}_$slug';
    }
    return 'https://janitorai.com/characters/$id';
  }

  /// External URL of the creator's profile page on its source site.
  String? _authorUrl() {
    if (widget.provider != CatalogProvider.janitor) return null;
    final creatorId = widget.item.creatorId;
    if (creatorId == null || creatorId.isEmpty) return null;
    return 'https://janitorai.com/profiles/$creatorId';
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 360,
      decoration: BoxDecoration(
        color: context.cs.surfaceContainerHighest,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Center(
        child: CircularProgressIndicator(color: context.cs.primary),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 360,
      decoration: BoxDecoration(
        color: context.cs.surfaceContainerHighest,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline_rounded,
            size: 48,
            color: context.cs.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(
              color: context.cs.onSurfaceVariant,
              fontSize: 13,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: onRetry,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: context.cs.primary,
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
    );
  }
}
