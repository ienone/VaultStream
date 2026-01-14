import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../../../core/network/image_headers.dart';
import '../../../models/content.dart';
import '../../../utils/content_parser.dart';
import '../components/author_header.dart';
import '../components/bvid_card.dart';
import '../components/tags_section.dart';
import '../components/unified_stats.dart';

class BilibiliLandscapeLayout extends StatelessWidget {
  final ContentDetail detail;
  final String apiBaseUrl;
  final String? apiToken;
  final Function(List<String>, int) onImageTap;

  const BilibiliLandscapeLayout({
    super.key,
    required this.detail,
    required this.apiBaseUrl,
    this.apiToken,
    required this.onImageTap,
  });

  @override
  Widget build(BuildContext context) {
    final images = ContentParser.extractAllImages(detail, apiBaseUrl);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Left: Media Area
        Expanded(
          flex: 6,
          child: Container(
            color: colorScheme.surface,
            child: images.isEmpty
                ? const Center(
                    child: Icon(
                      Icons.movie_outlined,
                      size: 64,
                      color: Colors.grey,
                    ),
                  )
                : (images.length == 1
                      ? Center(
                          child: GestureDetector(
                            onTap: () => onImageTap(images, 0),
                            child: Hero(
                              tag: 'content-image-${detail.id}',
                              child: CachedNetworkImage(
                                imageUrl: images.first,
                                httpHeaders: buildImageHeaders(
                                  imageUrl: images.first,
                                  baseUrl: apiBaseUrl,
                                  apiToken: apiToken,
                                ),
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                        )
                      : ListView.builder(
                          itemCount: images.length,
                          padding: const EdgeInsets.all(24),
                          itemBuilder: (context, index) => Padding(
                            padding: const EdgeInsets.only(bottom: 24),
                            child: GestureDetector(
                              onTap: () => onImageTap(images, index),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(24),
                                child: Hero(
                                  tag: index == 0
                                      ? 'content-image-${detail.id}'
                                      : 'image-$index-${detail.id}',
                                  child: CachedNetworkImage(
                                    imageUrl: images[index],
                                    httpHeaders: buildImageHeaders(
                                      imageUrl: images[index],
                                      baseUrl: apiBaseUrl,
                                      apiToken: apiToken,
                                    ),
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        )),
          ),
        ),
        // Right: Info Area
        Expanded(
          flex: 4,
          child: Container(
            decoration: BoxDecoration(
              color: colorScheme.surface,
              border: Border(
                left: BorderSide(color: colorScheme.outlineVariant),
              ),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Container(
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(28),
                ),
                padding: const EdgeInsets.all(28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AuthorHeader(detail: detail),
                    const SizedBox(height: 32),
                    Text(
                      detail.title ?? '无标题内容',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 24),
                    UnifiedStats(detail: detail),
                    const SizedBox(height: 16),
                    if (detail.platformId != null) BvidCard(detail: detail),
                    const SizedBox(height: 24),
                    TagsSection(detail: detail),
                    const SizedBox(height: 40),
                    if (detail.description != null &&
                        detail.description!.isNotEmpty &&
                        detail.description != '-') ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: colorScheme.primary.withValues(alpha: 0.1),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.notes_rounded,
                                  size: 18,
                                  color: colorScheme.primary,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '简介',
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    color: colorScheme.primary,
                                    letterSpacing: 1.0,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              detail.description!,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                height: 1.8,
                                fontSize: 15,
                                color: colorScheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
