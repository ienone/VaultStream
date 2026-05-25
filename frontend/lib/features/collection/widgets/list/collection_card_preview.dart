import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/layout/responsive_layout.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/image_headers.dart';
import '../../../../core/utils/dynamic_color_helper.dart';
import '../../../../core/utils/media_utils.dart' as media_utils;
import '../../../../core/widgets/network_thumbnail.dart';
import '../../../../core/widgets/platform_badge.dart';
import '../../models/content.dart';
import '../../utils/content_parser.dart';

String collectionCardHeroTag(int contentId) => 'card-shell-$contentId';

enum CollectionCardPreviewMode { grid, flight, detailLoading }

class CollectionCardPreview extends ConsumerWidget {
  final ShareCard content;
  final VoidCallback? onTap;
  final bool isHovered;
  final bool? isTinyCardOverride;
  final double? imageAspectRatioOverride;
  final CollectionCardPreviewMode mode;

  const CollectionCardPreview({
    super.key,
    required this.content,
    this.onTap,
    this.isHovered = false,
    this.isTinyCardOverride,
    this.imageAspectRatioOverride,
    this.mode = CollectionCardPreviewMode.grid,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final dio = ref.watch(apiClientProvider);
    final apiBaseUrl = dio.options.baseUrl;
    final apiToken = dio.options.headers['X-API-Token']?.toString();

    final imageUrl = ContentParser.getDisplayImageUrl(content, apiBaseUrl);
    final imageHeaders =
        buildImageHeaders(
          imageUrl: imageUrl,
          baseUrl: apiBaseUrl,
          apiToken: apiToken,
        ) ??
        const <String, String>{};
    final hasImage = imageUrl.isNotEmpty;
    final isGallery = content.layoutType == 'gallery';
    final cardWidth = ResponsiveLayout.getCardWidth(context);
    final isTinyCard = isTinyCardOverride ?? cardWidth < 220;
    final imageAspectRatio =
        imageAspectRatioOverride ?? (content.isLandscapeCover ? 1.77 : 0.85);

    Color? displayColor;
    final backendColor = content.coverColor;
    if (backendColor != null && backendColor.isNotEmpty) {
      displayColor = DynamicColorHelper.getContentColor(backendColor, context);
      if (displayColor == theme.colorScheme.primary) {
        displayColor = null;
      }
    }

    final child = _PreviewSurface(
      content: content,
      imageUrl: imageUrl,
      imageHeaders: imageHeaders,
      hasImage: hasImage,
      isGallery: isGallery,
      isTinyCard: isTinyCard,
      imageAspectRatio: imageAspectRatio,
      displayColor: displayColor,
      apiBaseUrl: apiBaseUrl,
      apiToken: apiToken,
      isHovered: isHovered,
      mode: mode,
    );

    if (onTap == null) {
      return child;
    }

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(28),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: child),
    );
  }
}

HeroFlightShuttleBuilder collectionCardFlightShuttleBuilder({
  required ShareCard content,
  required bool isTinyCard,
}) {
  return (
    BuildContext flightContext,
    Animation<double> animation,
    HeroFlightDirection flightDirection,
    BuildContext fromHeroContext,
    BuildContext toHeroContext,
  ) {
    return Material(
      color: Colors.transparent,
      child: CollectionCardPreview(
        content: content,
        isTinyCardOverride: isTinyCard,
        mode: CollectionCardPreviewMode.flight,
      ),
    );
  };
}

class _PreviewSurface extends StatelessWidget {
  final ShareCard content;
  final String imageUrl;
  final Map<String, String> imageHeaders;
  final bool hasImage;
  final bool isGallery;
  final bool isTinyCard;
  final double imageAspectRatio;
  final Color? displayColor;
  final String apiBaseUrl;
  final String? apiToken;
  final bool isHovered;
  final CollectionCardPreviewMode mode;

  const _PreviewSurface({
    required this.content,
    required this.imageUrl,
    required this.imageHeaders,
    required this.hasImage,
    required this.isGallery,
    required this.isTinyCard,
    required this.imageAspectRatio,
    this.displayColor,
    required this.apiBaseUrl,
    this.apiToken,
    required this.isHovered,
    required this.mode,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final animateChanges = mode == CollectionCardPreviewMode.grid;
    final showHover = animateChanges && isHovered;

    final decoration = BoxDecoration(
      borderRadius: BorderRadius.circular(28),
      color: showHover && displayColor != null
          ? Color.alphaBlend(
              displayColor!.withValues(alpha: 0.1),
              colorScheme.surfaceContainerHigh,
            )
          : colorScheme.surfaceContainerLow,
      boxShadow: showHover
          ? [
              BoxShadow(
                color: (displayColor ?? colorScheme.primary).withValues(
                  alpha: 0.15,
                ),
                blurRadius: 24,
                spreadRadius: 2,
                offset: const Offset(0, 8),
              ),
            ]
          : null,
      border: Border.all(
        color: showHover && displayColor != null
            ? displayColor!.withValues(alpha: 0.5)
            : colorScheme.outlineVariant.withValues(alpha: 0.3),
        width: showHover ? 1.5 : 1,
      ),
    );

    final contentChild = ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: DecoratedBox(
        decoration: decoration,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (hasImage)
              _CardCover(
                content: content,
                imageUrl: imageUrl,
                imageHeaders: imageHeaders,
                imageAspectRatio: imageAspectRatio,
              ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.all(isTinyCard ? 12 : 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _CardAuthor(
                      content: content,
                      apiBaseUrl: apiBaseUrl,
                      apiToken: apiToken,
                      isHovered: showHover,
                      displayColor: displayColor,
                      isTinyCard: isTinyCard,
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: _CardContentSnippet(
                        content: content,
                        isGallery: isGallery,
                        isTinyCard: isTinyCard,
                      ),
                    ),
                    if (content.hasSemanticMatch && !isTinyCard) ...[
                      const SizedBox(height: 8),
                      _SemanticMatchBadge(content: content),
                    ],
                    const SizedBox(height: 8),
                    _CardFooter(
                      content: content,
                      isTinyCard: isTinyCard,
                      isHovered: showHover,
                      displayColor: displayColor,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (!animateChanges) return contentChild;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      child: contentChild,
    );
  }
}

class _CardCover extends StatelessWidget {
  final ShareCard content;
  final String imageUrl;
  final Map<String, String> imageHeaders;
  final double imageAspectRatio;

  const _CardCover({
    required this.content,
    required this.imageUrl,
    required this.imageHeaders,
    required this.imageAspectRatio,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: imageAspectRatio,
      child: Stack(
        fit: StackFit.expand,
        children: [
          NetworkThumbnail(
            imageUrl: content.thumbnailUrl ?? imageUrl,
            httpHeaders: imageHeaders,
            fit: BoxFit.cover,
            maxHeightDiskCache: 800,
            errorIcon: Icons.broken_image_rounded,
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.1),
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.05),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CardAuthor extends StatelessWidget {
  final ShareCard content;
  final String apiBaseUrl;
  final String? apiToken;
  final bool isHovered;
  final Color? displayColor;
  final bool isTinyCard;

  const _CardAuthor({
    required this.content,
    required this.apiBaseUrl,
    this.apiToken,
    required this.isHovered,
    this.displayColor,
    required this.isTinyCard,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Row(
      children: [
        PlatformBadge(platform: content.platform),
        const SizedBox(width: 8),
        if (content.authorAvatarUrl != null && !isTinyCard) ...[
          Container(
            padding: const EdgeInsets.all(1),
            decoration: BoxDecoration(
              color: (displayColor ?? colorScheme.primary).withValues(
                alpha: 0.2,
              ),
              shape: BoxShape.circle,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: NetworkThumbnail(
                imageUrl: media_utils.mapUrl(
                  content.authorAvatarUrl!,
                  apiBaseUrl,
                ),
                httpHeaders: buildImageHeaders(
                  imageUrl: media_utils.mapUrl(
                    content.authorAvatarUrl!,
                    apiBaseUrl,
                  ),
                  baseUrl: apiBaseUrl,
                  apiToken: apiToken,
                ),
                width: 18,
                height: 18,
                fit: BoxFit.cover,
                errorIcon: Icons.person_rounded,
              ),
            ),
          ),
          const SizedBox(width: 6),
        ],
        Expanded(
          child: Text(
            content.authorName ?? '未知作者',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: isHovered && displayColor != null
                  ? displayColor
                  : colorScheme.onSurfaceVariant,
              fontSize: isTinyCard ? 10 : 12,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _CardContentSnippet extends StatelessWidget {
  final ShareCard content;
  final bool isGallery;
  final bool isTinyCard;

  const _CardContentSnippet({
    required this.content,
    required this.isGallery,
    required this.isTinyCard,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final title = content.title?.trim() ?? '';

    if (isGallery) {
      final text = (title.isNotEmpty && title != '-') ? title : '';
      if (text.isEmpty) return const SizedBox.shrink();
      return Text(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontSize: isTinyCard ? 11 : 13,
          height: 1.3,
          fontWeight: FontWeight.w500,
          color: colorScheme.onSurface,
        ),
        maxLines: isTinyCard ? 3 : 4,
        overflow: TextOverflow.ellipsis,
      );
    }

    final text = title.isNotEmpty ? title : '';
    if (text.isEmpty) return const SizedBox.shrink();
    return Text(
      text,
      style: theme.textTheme.titleMedium?.copyWith(
        fontSize: isTinyCard ? 12 : 14,
        fontWeight: FontWeight.w800,
        height: 1.25,
        color: colorScheme.onSurface,
        letterSpacing: 0,
      ),
      maxLines: isTinyCard ? 2 : 3,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _SemanticMatchBadge extends StatelessWidget {
  final ShareCard content;

  const _SemanticMatchBadge({required this.content});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final score = content.semanticScore;
    final source = switch (content.semanticMatchSource) {
      'hybrid' => '混合命中',
      'vector' => '语义命中',
      'fts' => '关键词命中',
      _ => '检索命中',
    };
    final chunk = content.semanticChunkTitle?.trim();
    final tooltip = [
      if (chunk != null && chunk.isNotEmpty) chunk,
      if (content.semanticSourceText != null &&
          content.semanticSourceText!.trim().isNotEmpty)
        content.semanticSourceText!.trim(),
    ].join('\n\n');

    return Tooltip(
      message: tooltip.isEmpty ? source : tooltip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: colorScheme.secondaryContainer.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.psychology_alt_rounded,
              size: 14,
              color: colorScheme.onSecondaryContainer,
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                score == null
                    ? source
                    : '$source ${score.toStringAsFixed(2)}'
                          '${chunk == null || chunk.isEmpty ? '' : ' • $chunk'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSecondaryContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CardFooter extends StatelessWidget {
  final ShareCard content;
  final bool isTinyCard;
  final bool isHovered;
  final Color? displayColor;

  const _CardFooter({
    required this.content,
    required this.isTinyCard,
    required this.isHovered,
    this.displayColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        if (content.tags.isNotEmpty)
          Expanded(
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              children: content.tags
                  .take(isTinyCard ? 1 : 2)
                  .map(
                    (tag) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: (displayColor ?? colorScheme.primary).withValues(
                          alpha: 0.1,
                        ),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '#$tag',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: displayColor ?? colorScheme.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 9,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        const SizedBox(width: 4),
        if (!isTinyCard && content.publishedAt != null)
          Text(
            DateFormat('MM-dd').format(content.publishedAt!.toLocal()),
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.outline.withValues(alpha: 0.6),
              fontWeight: FontWeight.w500,
            ),
          ),
      ],
    );
  }
}
