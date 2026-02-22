import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../../../core/constants/platform_constants.dart';
import '../../../models/content.dart';
import '../../../utils/content_parser.dart';
import '../components/author_header.dart';
import '../components/bvid_card.dart';
import '../components/rich_content.dart';
import '../components/tags_section.dart';
import '../components/unified_stats.dart';
import '../components/media_gallery_item.dart';
import '../../renderers/context_card_renderer.dart';
import '../../renderers/payload_block_renderer.dart';

class PortraitLayout extends StatelessWidget {
  final ContentDetail detail;
  final String apiBaseUrl;
  final String? apiToken;
  final Map<String, GlobalKey> headerKeys;
  final Color? contentColor;

  const PortraitLayout({
    super.key,
    required this.detail,
    required this.apiBaseUrl,
    this.apiToken,
    required this.headerKeys,
    this.contentColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final bool isVideoLayout = detail.layoutType == 'video';
    final mediaUrls = ContentParser.extractAllMedia(detail, apiBaseUrl);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Media at top for Video layout
          if (isVideoLayout && mediaUrls.isNotEmpty) ...[
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: MediaGalleryItem(
                images: mediaUrls,
                index: 0,
                apiBaseUrl: apiBaseUrl,
                apiToken: apiToken,
                contentId: detail.id,
                contentColor: contentColor,
                heroTag: 'content-image-${detail.id}',
                fit: BoxFit.cover,
                borderRadius: BorderRadius.circular(24),
              ),
            ),
            const SizedBox(height: 24),
          ],

          // 2. Info Container
          Container(
                decoration: BoxDecoration(
                  color: isDark
                      ? colorScheme.surfaceContainer
                      : colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.2),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: (contentColor ?? colorScheme.primary).withValues(
                        alpha: 0.08,
                      ),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ContextCardRenderer(content: detail),
                    if (detail.contextData != null) const SizedBox(height: 16),
                    AuthorHeader(detail: detail),
                    const SizedBox(height: 24),
                    if (detail.layoutType != 'gallery' &&
                        (detail.title != null && detail.title!.isNotEmpty))
                      Text(
                            detail.title ?? '无标题内容',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w900,
                              height: 1.2,
                              letterSpacing: -0.8,
                              color: colorScheme.onSurface,
                            ),
                          )
                          .animate()
                          .fadeIn(delay: 200.ms)
                          .slideX(begin: -0.05, end: 0),
                    const SizedBox(height: 24),
                    UnifiedStats(detail: detail, useContainer: false),
                    const SizedBox(height: 20),
                    if (detail.platform.isBilibili && detail.platformId != null)
                      BvidCard(detail: detail),
                    const SizedBox(height: 20),
                    TagsSection(detail: detail),
                  ],
                ),
              )
              .animate()
              .fadeIn(duration: 500.ms)
              .scale(
                begin: const Offset(0.98, 0.98),
                curve: Curves.easeOutCubic,
              ),

          const SizedBox(height: 32),

          // 3. Rich Content (Description)
          RichContent(
            detail: detail,
            apiBaseUrl: apiBaseUrl,
            apiToken: apiToken,
            headerKeys: headerKeys,
            contentColor: contentColor,
            hideMedia: isVideoLayout, // Don't show cover twice for video layout
          ).animate().fadeIn(delay: 400.ms).slideY(begin: 0.05, end: 0),

          const SizedBox(height: 24),
          PayloadBlockRenderer(content: detail),
          const SizedBox(height: 48),
        ],
      ),
    );
  }
}
