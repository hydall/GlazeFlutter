import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../shared/theme/app_colors.dart';
import '../catalog_models.dart';

class CatalogCard extends StatelessWidget {
  final CatalogItem item;
  final VoidCallback onTap;

  const CatalogCard({super.key, required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildImage(),
            const Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: 150,
              child: _BottomGradient(),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _CardInfo(item: item),
            ),
            if (item.tokens > 0)
              Positioned(
                top: 8,
                left: 8,
                child: _TokenBadge(tokens: item.tokens),
              ),
            Positioned(
              top: 8,
              right: 8,
              child: _NsfwBadge(nsfw: item.nsfw),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.05),
                    width: 2,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImage() {
    if (item.avatarUrl != null && item.avatarUrl!.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: item.avatarUrl!,
        fit: BoxFit.cover,
        placeholder: (_, _) => _buildPlaceholder(),
        errorWidget: (_, _, _) => _buildPlaceholder(),
      );
    }
    return _buildPlaceholder();
  }

  Widget _buildPlaceholder() {
    return Container(
      color: AppColors.accent.withValues(alpha: 0.2),
      child: Center(
        child: Text(
          item.name.isNotEmpty ? item.name[0].toUpperCase() : '?',
          style: const TextStyle(
            fontSize: 48,
            color: AppColors.accent,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

class _BottomGradient extends StatelessWidget {
  const _BottomGradient();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Color(0xF2000000),
            Color(0x99000000),
            Colors.transparent,
          ],
          stops: [0.0, 0.5, 1.0],
        ),
      ),
    );
  }
}

class _CardInfo extends StatelessWidget {
  final CatalogItem item;

  const _CardInfo({required this.item});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            item.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: Colors.white,
              shadows: [Shadow(blurRadius: 4, color: Colors.black54)],
            ),
          ),
          if (item.creator != null && item.creator!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              '@${item.creator}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: Colors.white.withValues(alpha: 0.6),
                shadows: const [Shadow(blurRadius: 4, color: Colors.black87)],
              ),
            ),
          ],
          if (item.tags.isNotEmpty) ...[
            const SizedBox(height: 4),
            _TagChips(tags: item.tags.take(3).toList()),
          ],
        ],
      ),
    );
  }
}

class _TagChips extends StatelessWidget {
  final List<String> tags;

  const _TagChips({required this.tags});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4,
      runSpacing: 2,
      children: tags.map((tag) {
        final isNsfw = tag.toUpperCase() == 'NSFW';
        final isSfw = tag.toUpperCase() == 'SFW';
        final isCustom = tag.startsWith('#');
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: isNsfw
                ? Colors.red.withValues(alpha: 0.3)
                : isSfw
                    ? Colors.green.withValues(alpha: 0.2)
                    : isCustom
                        ? Colors.cyan.withValues(alpha: 0.2)
                        : AppColors.accent.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            tag,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: isNsfw
                  ? Colors.redAccent
                  : isSfw
                      ? Colors.greenAccent
                      : isCustom
                          ? Colors.cyanAccent
                          : AppColors.accent,
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _TokenBadge extends StatelessWidget {
  final int tokens;

  const _TokenBadge({required this.tokens});

  String _formatTokens(int t) {
    if (t >= 1000) return '${(t / 1000).toStringAsFixed(1)}k';
    return '$t';
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.description_outlined, size: 11, color: Colors.white70),
              const SizedBox(width: 4),
              Text(
                '${_formatTokens(tokens)} tokens',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NsfwBadge extends StatelessWidget {
  final bool nsfw;

  const _NsfwBadge({required this.nsfw});

  @override
  Widget build(BuildContext context) {
    if (!nsfw) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Text(
        'NSFW',
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}
