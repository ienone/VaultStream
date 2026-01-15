import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:frontend/core/utils/media_utils.dart';
import '../../../core/layout/responsive_layout.dart';
import '../../../theme/app_theme.dart';
import '../models/content.dart';
import '../../../core/widgets/platform_badge.dart';
import '../utils/content_media_helper.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/image_headers.dart';

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

    final imageUrl = ContentMediaHelper.getDisplayImageUrl(content, apiBaseUrl);
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
    final double imageAspectRatio = isLandscapeCover ? 16 / 9 : 0.8;
    final double cardAspectRatio = isLandscapeCover
        ? (isTinyCard ? 16 / 20 : 16 / 18)
        : (isTinyCard ? 0.46 : 0.52);

    // 优先使用后端预提取的颜色
    Color? displayColor;
    String? backendColor =
        content.coverColor ??
        content.rawMetadata?['archive']?['dominant_color'];

    if (backendColor != null && backendColor.startsWith('#')) {
      displayColor = AppTheme.getAdjustedColor(
        AppTheme.parseHexColor(backendColor),
        theme.brightness,
      );
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
                    // Image Section
                    if (widget.hasImage)
                      AspectRatio(
                        aspectRatio: widget.imageAspectRatio,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Hero(
                              tag: 'content-image-${content.id}',
                              child: CachedNetworkImage(
                                imageUrl: widget.imageUrl,
                                httpHeaders: widget.imageHeaders,
                                fit: BoxFit.cover,
                                maxHeightDiskCache: 800,
                                placeholder: (context, url) => Container(
                                  color: colorScheme.surfaceContainerHighest,
                                  child: const Center(
                                    child: SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  ),
                                ),
                                errorWidget: (context, url, error) => Container(
                                  color: colorScheme.errorContainer,
                                  child: Center(
                                    child: Icon(
                                      Icons.broken_image,
                                      color: colorScheme.error,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            if (content.mediaUrls.length > 1)
                              Positioned(
                                right: 12,
                                bottom: 12,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
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
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
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
                      ),

                    // 内容区域
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                PlatformBadge(platform: content.platform),
                                const SizedBox(width: 8),
                                if (content.authorAvatarUrl != null) ...[
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: CachedNetworkImage(
                                      imageUrl: mapUrl(
                                        content.authorAvatarUrl!,
                                        widget.apiBaseUrl,
                                      ),
                                      httpHeaders: buildImageHeaders(
                                        imageUrl: mapUrl(
                                          content.authorAvatarUrl!,
                                          widget.apiBaseUrl,
                                        ),
                                        baseUrl: widget.apiBaseUrl,
                                        apiToken: widget.apiToken,
                                      ),
                                      width: 16,
                                      height: 16,
                                      fit: BoxFit.cover,
                                      placeholder: (context, url) => Container(
                                        color:
                                            colorScheme.surfaceContainerHighest,
                                      ),
                                      errorWidget: (context, url, error) =>
                                          const Icon(Icons.person, size: 12),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                ],
                                Expanded(
                                  child: Text(
                                    content.authorName ?? '未知作者',
                                    style: theme.textTheme.labelMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.w700,
                                          color:
                                              _isHovered && displayColor != null
                                              ? displayColor
                                              : colorScheme.onSurfaceVariant,
                                          letterSpacing: 0.1,
                                          fontSize: widget.isTinyCard ? 11 : 12,
                                        ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Expanded(
                              child: (widget.isTwitter || content.isWeibo)
                                  ? (content.description != null &&
                                            content.description!.isNotEmpty
                                        ? Text(
                                            content.description!.trim(),
                                            style: theme.textTheme.bodyMedium
                                                ?.copyWith(
                                                  fontSize: widget.isTinyCard
                                                      ? 12
                                                      : 13,
                                                  height: 1.4,
                                                  fontWeight: FontWeight.w500,
                                                  color: colorScheme.onSurface,
                                                ),
                                            maxLines: widget.isTinyCard ? 3 : 4,
                                            overflow: TextOverflow.ellipsis,
                                          )
                                        : const SizedBox.shrink())
                                  : (content.title != null
                                        ? Text(
                                            content.title!,
                                            style: theme.textTheme.titleMedium
                                                ?.copyWith(
                                                  fontSize: widget.isTinyCard
                                                      ? 13
                                                      : 14,
                                                  fontWeight: FontWeight.w800,
                                                  height: 1.3,
                                                  color: colorScheme.onSurface,
                                                  letterSpacing: -0.2,
                                                ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          )
                                        : const SizedBox.shrink()),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                if (content.tags.isNotEmpty)
                                  Expanded(
                                    child: Wrap(
                                      spacing: 4,
                                      runSpacing: 4,
                                      children: content.tags
                                          .take(widget.isTinyCard ? 1 : 2)
                                          .map(
                                            (tag) => Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 2,
                                                  ),
                                              decoration: BoxDecoration(
                                                color:
                                                    (displayColor ??
                                                            colorScheme.primary)
                                                        .withAlpha(25),
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                '#$tag',
                                                style: theme
                                                    .textTheme
                                                    .labelSmall
                                                    ?.copyWith(
                                                      color:
                                                          displayColor ??
                                                          colorScheme.primary,
                                                      fontWeight:
                                                          FontWeight.w700,
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
                                    if (!widget.isTinyCard &&
                                        content.publishedAt != null)
                                      Text(
                                        DateFormat('yyyy-MM-dd').format(
                                          content.publishedAt!.toLocal(),
                                        ),
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                              color: colorScheme.outline
                                                  .withAlpha(150),
                                              fontSize: 10,
                                            ),
                                      ),
                                    const SizedBox(height: 2),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (content.viewCount > 0) ...[
                                          Icon(
                                            Icons.remove_red_eye_outlined,
                                            size: 12,
                                            color:
                                                _isHovered &&
                                                    displayColor != null
                                                ? displayColor
                                                : colorScheme.outline,
                                          ),
                                          const SizedBox(width: 2),
                                          Text(
                                            ContentMediaHelper.formatCount(
                                              content.viewCount,
                                            ),
                                            style: theme.textTheme.labelSmall
                                                ?.copyWith(
                                                  color:
                                                      _isHovered &&
                                                          displayColor != null
                                                      ? displayColor
                                                      : colorScheme.outline,
                                                  fontSize: 10,
                                                ),
                                          ),
                                        ],
                                        if (content.commentCount > 0) ...[
                                          if (content.viewCount > 0)
                                            const SizedBox(width: 6),
                                          Icon(
                                            Icons.chat_bubble_outline,
                                            size: 11,
                                            color:
                                                _isHovered &&
                                                    displayColor != null
                                                ? displayColor
                                                : colorScheme.outline,
                                          ),
                                          const SizedBox(width: 2),
                                          Text(
                                            ContentMediaHelper.formatCount(
                                              content.commentCount,
                                            ),
                                            style: theme.textTheme.labelSmall
                                                ?.copyWith(
                                                  color:
                                                      _isHovered &&
                                                          displayColor != null
                                                      ? displayColor
                                                      : colorScheme.outline,
                                                  fontSize: 10,
                                                ),
                                          ),
                                        ],
                                        if (content.likeCount > 0) ...[
                                          if (content.viewCount > 0 ||
                                              content.commentCount > 0)
                                            const SizedBox(width: 6),
                                          Icon(
                                            Icons.favorite_border,
                                            size: 11,
                                            color:
                                                _isHovered &&
                                                    displayColor != null
                                                ? displayColor
                                                : colorScheme.outline,
                                          ),
                                          const SizedBox(width: 2),
                                          Text(
                                            ContentMediaHelper.formatCount(
                                              content.likeCount,
                                            ),
                                            style: theme.textTheme.labelSmall
                                                ?.copyWith(
                                                  color:
                                                      _isHovered &&
                                                          displayColor != null
                                                      ? displayColor
                                                      : colorScheme.outline,
                                                  fontSize: 10,
                                                ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ],
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
