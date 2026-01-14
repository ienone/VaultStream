import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../../core/network/image_headers.dart';
import '../../../models/content.dart';
import '../../../utils/content_parser.dart';
import '../components/author_header.dart';

import '../components/tags_section.dart';
import '../components/unified_stats.dart';
import '../components/zhihu_top_answers.dart';
import '../../video_player_widget.dart';

class TwitterLandscapeLayout extends StatelessWidget {
  final ContentDetail detail;
  final String apiBaseUrl;
  final String? apiToken;
  final List<String> images;
  final PageController imagePageController;
  final int currentImageIndex;
  final Function(int) onImageTap;
  final Function(int) onPageChanged;
  final Map<String, GlobalKey> headerKeys;
  final Color? contentColor;

  const TwitterLandscapeLayout({
    super.key,
    required this.detail,
    required this.apiBaseUrl,
    this.apiToken,
    required this.images,
    required this.imagePageController,
    required this.currentImageIndex,
    required this.onImageTap,
    required this.onPageChanged,
    required this.headerKeys,
    this.contentColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      children: [
        // Left: Media Area (Main Content)
        Expanded(
          flex: 6,
          child: Container(
            color: colorScheme.surface,
            child: images.isEmpty
                ? const Center(
                    child: Icon(
                      Icons.text_fields,
                      size: 64,
                      color: Colors.grey,
                    ),
                  )
                : _buildMediaArea(context),
          ),
        ),
        // Right: Content Info Area (Supporting Pane)
        Expanded(
          flex: 4,
          child: _buildSideInfo(context),
        ),
      ],
    );
  }

  Widget _buildMediaArea(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              PageView.builder(
                controller: imagePageController,
                itemCount: images.length,
                onPageChanged: onPageChanged,
                itemBuilder: (context, index) {
                  final img = images[index];
                  if (ContentParser.isVideo(img)) {
                    return Center(
                      child: VideoPlayerWidget(
                        videoUrl: img,
                        headers: buildImageHeaders(
                          imageUrl: img,
                          baseUrl: apiBaseUrl,
                          apiToken: apiToken,
                        ),
                      ),
                    );
                  }
                  return Center(
                    child: GestureDetector(
                      onTap: () => onImageTap(index),
                      child: InteractiveViewer(
                        minScale: 1.0,
                        maxScale: 3.0,
                        child: Hero(
                          tag: index == 0
                              ? 'content-image-${detail.id}'
                              : 'image-$index-${detail.id}',
                          child: CachedNetworkImage(
                            imageUrl: img,
                            httpHeaders: buildImageHeaders(
                              imageUrl: img,
                              baseUrl: apiBaseUrl,
                              apiToken: apiToken,
                            ),
                            fit: BoxFit.contain,
                            placeholder: (c, u) => const Center(
                              child: CircularProgressIndicator(),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              if (images.length > 1) ...[
                if (currentImageIndex > 0)
                  Positioned(
                    left: 16,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: IconButton.filledTonal(
                        icon: const Icon(Icons.chevron_left),
                        onPressed: () {
                          imagePageController.previousPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          );
                        },
                      ),
                    ),
                  ),
                if (currentImageIndex < images.length - 1)
                  Positioned(
                    right: 16,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: IconButton.filledTonal(
                        icon: const Icon(Icons.chevron_right),
                        onPressed: () {
                          imagePageController.nextPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          );
                        },
                      ),
                    ),
                  ),
              ],
              if (images.length > 1)
                Positioned(
                  top: 16,
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${currentImageIndex + 1} / ${images.length}',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (images.length > 1)
          Container(
            height: 90,
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: images.length,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              itemBuilder: (context, index) {
                final img = images[index];
                final isSelected = index == currentImageIndex;
                return GestureDetector(
                  onTap: () {
                    imagePageController.animateToPage(
                      index,
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.fastOutSlowIn,
                    );
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: isSelected ? 120 : 64,
                    height: 64,
                    margin: const EdgeInsets.only(right: 12),
                    decoration: BoxDecoration(
                      border: isSelected
                          ? Border.all(
                              color: Theme.of(context).colorScheme.primary,
                              width: 3,
                            )
                          : Border.all(
                              color: Theme.of(context)
                                  .colorScheme
                                  .outlineVariant
                                  .withValues(alpha: 0.5),
                              width: 1,
                            ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: Theme.of(
                                  context,
                                ).colorScheme.primary.withValues(alpha: 0.2),
                                blurRadius: 8,
                                spreadRadius: 2,
                              ),
                            ]
                          : null,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(13),
                      child: ContentParser.isVideo(img)
                          ? Container(
                              color: Colors.black,
                              child: const Center(
                                child: Icon(
                                  Icons.play_circle_fill,
                                  color: Colors.white,
                                  size: 24,
                                ),
                              ),
                            )
                          : CachedNetworkImage(
                              imageUrl: img,
                              httpHeaders: buildImageHeaders(
                                imageUrl: img,
                                baseUrl: apiBaseUrl,
                                apiToken: apiToken,
                              ),
                              fit: BoxFit.cover,
                              placeholder: (context, url) => Container(
                                color: Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHighest,
                              ),
                            ),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildSideInfo(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          left: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Container(
          decoration: BoxDecoration(
            color: isDark
                ? colorScheme.surfaceContainer
                : colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(28),
            border: isDark
                ? Border.all(
                    color: Colors.white.withValues(alpha: 0.05),
                    width: 1,
                  )
                : null,
            boxShadow: isDark
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ]
                : null,
          ),
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AuthorHeader(detail: detail),
              const SizedBox(height: 32),
              if (detail.title != null &&
                  detail.title!.isNotEmpty &&
                  !detail.isTwitter &&
                  !detail.isWeibo &&
                  !detail.isZhihuPin) ...[
                Text(
                  detail.title!,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 24),
              ],
              if (detail.description != null)
                MarkdownBody(
                  data: detail.description!,
                  selectable: true,
                  onTapLink: (text, href, title) {
                    if (href != null) {
                      launchUrl(
                        Uri.parse(href),
                        mode: LaunchMode.externalApplication,
                      );
                    }
                  },
                  styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                    p: theme.textTheme.headlineSmall?.copyWith(
                      height: 1.5,
                      letterSpacing: 0.1,
                      fontSize: 20,
                    ),
                  ),
                ),
              const SizedBox(height: 48),
              UnifiedStats(detail: detail),
              const SizedBox(height: 48),
              Text(
                '关联标签',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.primary,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 16),
              TagsSection(detail: detail),
              if (detail.isZhihuQuestion &&
                  detail.rawMetadata != null &&
                  detail.rawMetadata!['top_answers'] != null)
                ZhihuTopAnswers(
                  topAnswers: detail.rawMetadata!['top_answers'] as List<dynamic>,
                ),
            ],
          ),
        ),
      ),
    );
  }
}