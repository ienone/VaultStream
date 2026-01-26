import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:frontend/core/utils/media_utils.dart';
import '../../../../../core/network/image_headers.dart';
import '../../../models/content.dart';
import '../components/media_gallery_item.dart';
import '../components/content_side_info_card.dart';

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
                ? _buildAvatarFallback(context)
                : _buildMediaArea(context),
          ),
        ),
        // Right: Content Info Area (Supporting Pane)
        Expanded(
          flex: 4,
          child: Container(
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
              child: ContentSideInfoCard(
                detail: detail,
                contentColor: contentColor,
                padding: const EdgeInsets.all(28),
                showDescription: true,
              ),
            ),
          ),
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
                  return Center(
                    child: MediaGalleryItem(
                      images: images,
                      index: index,
                      apiBaseUrl: apiBaseUrl,
                      apiToken: apiToken,
                      contentId: detail.id,
                      contentColor: contentColor,
                      heroTag: index == 0
                          ? 'content-image-${detail.id}'
                          : 'image-$index-${detail.id}',
                      fit: BoxFit.contain,
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
                      child: isVideo(img)
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

  Widget _buildAvatarFallback(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    // 无图片时显示头像作为视觉焦点（正文在右侧ContentSideInfoCard中显示）
    final avatarUrl = detail.authorAvatarUrl;
    
    if (avatarUrl == null || avatarUrl.isEmpty) {
      return Center(
        child: Icon(
          Icons.text_fields,
          size: 64,
          color: colorScheme.outline,
        ),
      );
    }
    
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(32),
          child: CachedNetworkImage(
            imageUrl: mapUrl(avatarUrl, apiBaseUrl),
            httpHeaders: buildImageHeaders(
              imageUrl: mapUrl(avatarUrl, apiBaseUrl),
              baseUrl: apiBaseUrl,
              apiToken: apiToken,
            ),
            width: 200,
            height: 200,
            fit: BoxFit.cover,
            placeholder: (context, url) => Container(
              width: 200,
              height: 200,
              color: colorScheme.surfaceContainerHighest,
            ),
            errorWidget: (context, url, error) => Container(
              width: 200,
              height: 200,
              color: colorScheme.surfaceContainerHighest,
              child: Icon(
                Icons.person,
                size: 80,
                color: colorScheme.outline,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
