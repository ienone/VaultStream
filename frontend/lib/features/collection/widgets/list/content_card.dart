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

  const ContentCard({super.key, required this.content, this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    // 获取 API Base URL
    final dio = ref.watch(apiClientProvider);
    final apiBaseUrl = dio.options.baseUrl;
    final apiToken = dio.options.headers['X-API-Token']?.toString();

    final imageUrl = ContentParser.getDisplayImageUrl(content, apiBaseUrl);
    final imageHeaders = buildImageHeaders(
      imageUrl: imageUrl,
      baseUrl: apiBaseUrl,
      apiToken: apiToken,
    );
    final isTwitter = content.isTwitter;
    final hasImage = imageUrl.isNotEmpty;

    final double cardWidth = ResponsiveLayout.getCardWidth(context);
    final bool isTinyCard = cardWidth < 220;

    final bool isLandscapeCover = content.isLandscapeCover;
    final double imageAspectRatio = isLandscapeCover ? 16 / 9 : 0.85;
    final double cardAspectRatio = isLandscapeCover
        ? (isTinyCard ? 16 / 19 : 16 / 17)
        : (isTinyCard ? 0.50 : 0.56);

    // 使用 DynamicColorHelper 获取动态颜色
    Color? displayColor;
    String? backendColor =
        content.coverColor ??
        content.rawMetadata?['archive']?['dominant_color'];

    if (backendColor != null && backendColor.isNotEmpty) {
      displayColor = DynamicColorHelper.getContentColor(backendColor, context);

      // 如果返回的是系统 primary，表示回退了，设置为 null
      final systemPrimary = theme.colorScheme.primary;
      if (displayColor == systemPrimary) {
        displayColor = null;
      }
    }

    return _ContentCardInternal(
      content: content,
      onTap: onTap,
      imageUrl: imageUrl,
      imageHeaders: imageHeaders ?? {},
      hasImage: hasImage,
      isTwitter: isTwitter,
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
  final String imageUrl;
  final Map<String, String> imageHeaders;
  final bool hasImage;
  final bool isTwitter;
  final bool isTinyCard;
  final double imageAspectRatio;
  final double cardAspectRatio;
  final Color? displayColor;
  final String apiBaseUrl;
  final String? apiToken;

  const _ContentCardInternal({
    required this.content,
    this.onTap,
    required this.imageUrl,
    required this.imageHeaders,
    required this.hasImage,
    required this.isTwitter,
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
        scale: _isHovered ? 1.02 : 1.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutBack,
        child: AspectRatio(
          aspectRatio: widget.cardAspectRatio,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: _isHovered
                  ? [
                      BoxShadow(
                        color: (displayColor ?? colorScheme.primary).withAlpha(
                          40,
                        ),
                        blurRadius: 15,
                        spreadRadius: 1,
                        offset: const Offset(0, 6),
                      ),
                    ]
                  : null,
            ),
            child: Card(
              elevation: 0,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: _isHovered && displayColor != null
                      ? displayColor.withAlpha(120)
                      : colorScheme.outlineVariant.withAlpha(80),
                  width: _isHovered ? 1.5 : 1,
                ),
              ),
              color: _isHovered && displayColor != null
                  ? Color.alphaBlend(
                      displayColor.withAlpha(20),
                      colorScheme.surfaceContainer,
                    )
                  : colorScheme.surfaceContainer,
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
                        padding: const EdgeInsets.all(12),
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
                            const SizedBox(height: 8),
                            _CardContentSnippet(
                              content: content,
                              isTwitter: widget.isTwitter,
                              isTinyCard: widget.isTinyCard,
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
        ),
      ),
    ).animate().fadeIn().slideY(begin: 0.1);
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
              imageUrl: imageUrl,
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
                  child: Icon(Icons.broken_image, color: colorScheme.error),
                ),
              ),
            ),
          ),
          if (content.mediaUrls.length > 1)
            Positioned(
              right: 12,
              bottom: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(150),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.filter_none_outlined,
                      size: 12,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${content.mediaUrls.length}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ],
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
        if (content.authorAvatarUrl != null) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CachedNetworkImage(
              imageUrl: mapUrl(content.authorAvatarUrl!, apiBaseUrl),
              httpHeaders: buildImageHeaders(
                imageUrl: mapUrl(content.authorAvatarUrl!, apiBaseUrl),
                baseUrl: apiBaseUrl,
                apiToken: apiToken,
              ),
              width: 16,
              height: 16,
              fit: BoxFit.cover,
              placeholder: (context, url) =>
                  Container(color: colorScheme.surfaceContainerHighest),
              errorWidget: (context, url, error) =>
                  const Icon(Icons.person, size: 12),
            ),
          ),
          const SizedBox(width: 6),
        ],
        Expanded(
          child: Text(
            content.authorName ?? '未知作者',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: isHovered && displayColor != null
                  ? displayColor
                  : colorScheme.onSurfaceVariant,
              letterSpacing: 0.1,
              fontSize: isTinyCard ? 11 : 12,
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
  final bool isTwitter;
  final bool isTinyCard;

  const _CardContentSnippet({
    required this.content,
    required this.isTwitter,
    required this.isTinyCard,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (isTwitter || content.isWeibo) {
      if (content.description == null || content.description!.isEmpty) {
        return const SizedBox.shrink();
      }
      return Expanded(
        child: Text(
          content.description!.trim(),
          style: theme.textTheme.bodyMedium?.copyWith(
            fontSize: isTinyCard ? 12 : 13,
            height: 1.4,
            fontWeight: FontWeight.w500,
            color: colorScheme.onSurface,
          ),
          maxLines: isTinyCard ? 3 : 4,
          overflow: TextOverflow.ellipsis,
        ),
      );
    } else {
      if (content.title == null) return const SizedBox.shrink();
      return Expanded(
        child: Text(
          content.title!,
          style: theme.textTheme.titleMedium?.copyWith(
            fontSize: isTinyCard ? 13 : 14,
            fontWeight: FontWeight.w800,
            height: 1.3,
            color: colorScheme.onSurface,
            letterSpacing: -0.2,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
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
      crossAxisAlignment: CrossAxisAlignment.end,
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
                        color: (displayColor ?? colorScheme.primary).withAlpha(
                          25,
                        ),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '#$tag',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: displayColor ?? colorScheme.primary,
                          fontWeight: FontWeight.w700,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          )
        else
          const SizedBox.shrink(),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!isTinyCard && content.publishedAt != null)
              Text(
                DateFormat('yyyy-MM-dd').format(content.publishedAt!.toLocal()),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.outline.withAlpha(150),
                  fontSize: 10,
                ),
              ),
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (content.viewCount > 0) ...[
                  _StatItem(
                    icon: Icons.remove_red_eye_outlined,
                    count: content.viewCount,
                    isHovered: isHovered,
                    displayColor: displayColor,
                  ),
                ],
                if (content.commentCount > 0) ...[
                  if (content.viewCount > 0) const SizedBox(width: 6),
                  _StatItem(
                    icon: Icons.chat_bubble_outline,
                    count: content.commentCount,
                    isHovered: isHovered,
                    displayColor: displayColor,
                  ),
                ],
                if (content.likeCount > 0) ...[
                  if (content.viewCount > 0 || content.commentCount > 0)
                    const SizedBox(width: 6),
                  _StatItem(
                    icon: Icons.favorite_border,
                    count: content.likeCount,
                    isHovered: isHovered,
                    displayColor: displayColor,
                  ),
                ],
              ],
            ),
          ],
        ),
      ],
    );
  }
}

class _StatItem extends StatelessWidget {
  final IconData icon;
  final int count;
  final bool isHovered;
  final Color? displayColor;

  const _StatItem({
    required this.icon,
    required this.count,
    required this.isHovered,
    this.displayColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final color = isHovered && displayColor != null
        ? displayColor
        : colorScheme.outline;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: color),
        const SizedBox(width: 2),
        Text(
          ContentParser.formatCount(count),
          style: theme.textTheme.labelSmall?.copyWith(
            color: color,
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}
