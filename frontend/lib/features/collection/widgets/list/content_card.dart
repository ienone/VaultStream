import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:frontend/core/utils/media_utils.dart';
import '../../../../core/layout/responsive_layout.dart';
import '../../models/content.dart';
import '../../../../core/widgets/platform_badge.dart';
import '../../utils/content_parser.dart';
import '../../../../core/utils/dynamic_color_helper.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/image_headers.dart';

class ContentCard extends ConsumerWidget {
  final ShareCard content;
  final VoidCallback? onTap;
  final int index;

  const ContentCard({
    super.key,
    required this.content,
    this.onTap,
    this.index = 0,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final dio = ref.watch(apiClientProvider);
    final apiBaseUrl = dio.options.baseUrl;
    final apiToken = dio.options.headers['X-API-Token']?.toString();

    final imageUrl = ContentParser.getDisplayImageUrl(content, apiBaseUrl);
    final imageHeaders = buildImageHeaders(
      imageUrl: imageUrl,
      baseUrl: apiBaseUrl,
      apiToken: apiToken,
    );
    final layoutType = content.layoutType;
    final isGallery = layoutType == 'gallery';
    final hasImage = imageUrl.isNotEmpty;

    final double cardWidth = ResponsiveLayout.getCardWidth(context);
    final bool isTinyCard = cardWidth < 220;

    final bool isLandscapeCover = content.isLandscapeCover;
    final double imageAspectRatio = isLandscapeCover ? 1.77 : 0.85;
    final double cardAspectRatio = isLandscapeCover
        ? (isTinyCard ? 0.82 : 0.92)
        : (isTinyCard ? 0.48 : 0.54);

    Color? displayColor;
    final backendColor = content.coverColor;

    if (backendColor != null && backendColor.isNotEmpty) {
      displayColor = DynamicColorHelper.getContentColor(backendColor, context);
      if (displayColor == theme.colorScheme.primary) {
        displayColor = null;
      }
    }

    return _ContentCardInternal(
      content: content,
      onTap: onTap,
      index: index,
      imageUrl: imageUrl,
      imageHeaders: imageHeaders ?? {},
      hasImage: hasImage,
      isGallery: isGallery,
      isTinyCard: isTinyCard,
      imageAspectRatio: imageAspectRatio,
      cardAspectRatio: cardAspectRatio,
      displayColor: displayColor,
      apiBaseUrl: apiBaseUrl,
      apiToken: apiToken,
    );
  }
}

class _ContentCardInternal extends StatefulWidget {
  final ShareCard content;
  final VoidCallback? onTap;
  final int index;
  final String imageUrl;
  final Map<String, String> imageHeaders;
  final bool hasImage;
  final bool isGallery;
  final bool isTinyCard;
  final double imageAspectRatio;
  final double cardAspectRatio;
  final Color? displayColor;
  final String apiBaseUrl;
  final String? apiToken;

  const _ContentCardInternal({
    required this.content,
    this.onTap,
    required this.index,
    required this.imageUrl,
    required this.imageHeaders,
    required this.hasImage,
    required this.isGallery,
    required this.isTinyCard,
    required this.imageAspectRatio,
    required this.cardAspectRatio,
    this.displayColor,
    required this.apiBaseUrl,
    this.apiToken,
  });

  @override
  State<_ContentCardInternal> createState() => _ContentCardInternalState();
}

class _ContentCardInternalState extends State<_ContentCardInternal> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final content = widget.content;
    final displayColor = widget.displayColor;

    return MouseRegion(
          onEnter: (_) => setState(() => _isHovered = true),

          onExit: (_) => setState(() => _isHovered = false),

          child: AnimatedScale(
            scale: _isHovered ? 1.03 : 1.0,

            duration: 300.ms,

            curve: Curves.easeOutBack,

            child: AspectRatio(
              aspectRatio: widget.cardAspectRatio,

              child: Stack(
                children: [
                  // Background Hero
                  Positioned.fill(
                    child: Hero(
                      tag: 'card-bg-${content.id}',

                      child: AnimatedContainer(
                        duration: 300.ms,

                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(28),

                          color: _isHovered && displayColor != null
                              ? Color.alphaBlend(
                                  displayColor.withValues(alpha: 0.1),
                                  colorScheme.surfaceContainerHigh,
                                )
                              : colorScheme.surfaceContainerLow,

                          boxShadow: _isHovered
                              ? [
                                  BoxShadow(
                                    color: (displayColor ?? colorScheme.primary)
                                        .withValues(alpha: 0.15),

                                    blurRadius: 24,

                                    spreadRadius: 2,

                                    offset: const Offset(0, 8),
                                  ),
                                ]
                              : null,

                          border: Border.all(
                            color: _isHovered && displayColor != null
                                ? displayColor.withValues(alpha: 0.5)
                                : colorScheme.outlineVariant.withValues(
                                    alpha: 0.3,
                                  ),

                            width: _isHovered ? 1.5 : 1,
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Content Overlay
                  Positioned.fill(
                    child: Material(
                      color: Colors.transparent,

                      borderRadius: BorderRadius.circular(28),

                      clipBehavior: Clip.antiAlias,

                      child: InkWell(
                        onTap: widget.onTap,

                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,

                          children: [
                            if (widget.hasImage)
                              _CardCover(
                                content: content,

                                imageUrl: widget.imageUrl,

                                imageHeaders: widget.imageHeaders,

                                imageAspectRatio: widget.imageAspectRatio,
                              ),

                            Expanded(
                              child: Padding(
                                padding: EdgeInsets.all(
                                  widget.isTinyCard ? 12 : 16,
                                ),

                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,

                                  children: [
                                    _CardAuthor(
                                      content: content,

                                      apiBaseUrl: widget.apiBaseUrl,

                                      apiToken: widget.apiToken,

                                      isHovered: _isHovered,

                                      displayColor: displayColor,

                                      isTinyCard: widget.isTinyCard,
                                    ),

                                    const SizedBox(height: 10),

                                    Expanded(
                                      child: _CardContentSnippet(
                                        content: content,

                                        isGallery: widget.isGallery,

                                        isTinyCard: widget.isTinyCard,
                                      ),
                                    ),

                                    const SizedBox(height: 8),

                                    _CardFooter(
                                      content: content,

                                      isTinyCard: widget.isTinyCard,

                                      isHovered: _isHovered,

                                      displayColor: displayColor,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        )
        .animate()
        .fadeIn(delay: (widget.index % 10 * 100).ms, duration: 500.ms)
        .slideY(
          begin: 0.2,
          end: 0,
          curve: Curves.easeOutCubic,
          delay: (widget.index % 10 * 100).ms,
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
    final colorScheme = Theme.of(context).colorScheme;
    return AspectRatio(
      aspectRatio: imageAspectRatio,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Hero(
            tag: 'content-image-${content.id}',
            child: CachedNetworkImage(
              imageUrl: content.thumbnailUrl ?? imageUrl, // 优先使用缩略图
              httpHeaders: imageHeaders,
              fit: BoxFit.cover,
              maxHeightDiskCache: 800,
              placeholder: (context, url) => Container(
                color: colorScheme.surfaceContainerHighest,
                child: const Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
              errorWidget: (context, url, error) => Container(
                color: colorScheme.errorContainer,
                child: Center(
                  child: Icon(
                    Icons.broken_image_rounded,
                    color: colorScheme.error,
                  ),
                ),
              ),
            ),
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
              child: CachedNetworkImage(
                imageUrl: mapUrl(content.authorAvatarUrl!, apiBaseUrl),
                httpHeaders: buildImageHeaders(
                  imageUrl: mapUrl(content.authorAvatarUrl!, apiBaseUrl),
                  baseUrl: apiBaseUrl,
                  apiToken: apiToken,
                ),
                width: 18,
                height: 18,
                fit: BoxFit.cover,
                placeholder: (context, url) =>
                    Container(color: colorScheme.surfaceContainerHighest),
                errorWidget: (context, url, error) =>
                    const Icon(Icons.person_rounded, size: 12),
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
      // Use backend-generated smart title if available
      final text = (title.isNotEmpty && title != '-') ? title : '';
      if (text.isEmpty) return const SizedBox.shrink();
      return Text(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontSize: isTinyCard
              ? 11
              : 13, // Slightly smaller to prevent overflow
          height: 1.3,
          fontWeight: FontWeight.w500,
          color: colorScheme.onSurface,
        ),
        maxLines: isTinyCard ? 3 : 4,
        overflow: TextOverflow.ellipsis,
      );
    } else {
      // For other platforms, show title more prominently
      final text = title.isNotEmpty ? title : '';
      if (text.isEmpty) return const SizedBox.shrink();
      return Text(
        text,
        style: theme.textTheme.titleMedium?.copyWith(
          fontSize: isTinyCard
              ? 12
              : 14, // Slightly smaller to prevent overflow
          fontWeight: FontWeight.w800,
          height: 1.25,
          color: colorScheme.onSurface,
          letterSpacing: -0.4,
        ),
        maxLines: isTinyCard ? 2 : 3,
        overflow: TextOverflow.ellipsis,
      );
    }
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
