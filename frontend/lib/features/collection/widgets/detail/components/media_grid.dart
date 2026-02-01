import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:frontend/core/utils/media_utils.dart';
import '../../../../../core/network/image_headers.dart';
import 'media_gallery_item.dart';

/// 通用媒体网格组件
/// 
/// 用于 GalleryLayout 的图片/视频展示，支持自适应布局：
/// - 竖屏：单图大图、双图对半、三图以上九宫格
/// - 横屏：单图大图，底部横向滚动预览
/// 
/// 符合 Material 3 Expressive Design 规范
class MediaGrid extends StatelessWidget {
  final List<String> images;
  final String apiBaseUrl;
  final String? apiToken;
  final int contentId;
  final Color? contentColor;
  final Function(int index)? onImageTap;
  final Function(int index)? onPageChanged;
  
  /// 是否为横屏模式（由外部 LayoutBuilder 决定）
  final bool isLandscape;
  
  /// 横屏模式下使用的 PageController
  final PageController? pageController;
  
  /// 当前选中的图片索引（横屏模式）
  final int currentIndex;

  const MediaGrid({
    super.key,
    required this.images,
    required this.apiBaseUrl,
    this.apiToken,
    required this.contentId,
    this.contentColor,
    this.onImageTap,
    this.onPageChanged,
    this.isLandscape = false,
    this.pageController,
    this.currentIndex = 0,
  });

  @override
  Widget build(BuildContext context) {
    if (images.isEmpty) {
      return const SizedBox.shrink();
    }

    if (isLandscape) {
      return _buildLandscapeLayout(context);
    } else {
      return _buildPortraitLayout(context);
    }
  }

  /// 横屏布局：主图 + 底部缩略图条
  Widget _buildLandscapeLayout(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      children: [
        // 主图区域
        Expanded(
          child: Stack(
            children: [
              PageView.builder(
                controller: pageController,
                itemCount: images.length,
                onPageChanged: onPageChanged,
                itemBuilder: (context, index) {
                  return Center(
                    child: MediaGalleryItem(
                      images: images,
                      index: index,
                      apiBaseUrl: apiBaseUrl,
                      apiToken: apiToken,
                      contentId: contentId,
                      contentColor: contentColor,
                      heroTag: _getHeroTag(index),
                      fit: BoxFit.contain,
                      onPageChanged: onPageChanged,
                    ),
                  );
                },
              ),
              // 左右导航按钮
              if (images.length > 1) ...[
                if (currentIndex > 0)
                  Positioned(
                    left: 16,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: IconButton.filledTonal(
                        icon: const Icon(Icons.chevron_left),
                        onPressed: () {
                          pageController?.previousPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          );
                        },
                      ),
                    ),
                  ),
                if (currentIndex < images.length - 1)
                  Positioned(
                    right: 16,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: IconButton.filledTonal(
                        icon: const Icon(Icons.chevron_right),
                        onPressed: () {
                          pageController?.nextPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          );
                        },
                      ),
                    ),
                  ),
              ],
              // 页码指示器
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
                      '${currentIndex + 1} / ${images.length}',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ),
            ],
          ),
        ),
        // 底部缩略图条
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
                final isSelected = index == currentIndex;
                return GestureDetector(
                  onTap: () {
                    pageController?.animateToPage(
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
                              color: contentColor ?? colorScheme.primary,
                              width: 3,
                            )
                          : Border.all(
                              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                              width: 1,
                            ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: (contentColor ?? colorScheme.primary).withValues(alpha: 0.2),
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
                                color: colorScheme.surfaceContainerHighest,
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

  /// 竖屏布局：单图/双图/九宫格自适应
  Widget _buildPortraitLayout(BuildContext context) {
    if (images.length == 1) {
      // 单图：大图展示
      return _buildSingleImage(context, images[0], 0);
    }

    if (images.length == 2) {
      // 双图：对半布局
      return Row(
        children: [
          Expanded(child: _buildGridImage(context, images[0], 0)),
          const SizedBox(width: 4),
          Expanded(child: _buildGridImage(context, images[1], 1)),
        ],
      );
    }

    // 三图以上：九宫格
    return _buildNineGrid(context);
  }

  /// 单图大图展示
  Widget _buildSingleImage(BuildContext context, String imageUrl, int index) {
    return GestureDetector(
      onTap: () => onImageTap?.call(index),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Hero(
          tag: _getHeroTag(index),
          child: isVideo(imageUrl)
              ? _buildVideoThumbnail(context, imageUrl)
              : CachedNetworkImage(
                  imageUrl: imageUrl,
                  httpHeaders: buildImageHeaders(
                    imageUrl: imageUrl,
                    baseUrl: apiBaseUrl,
                    apiToken: apiToken,
                  ),
                  fit: BoxFit.cover,
                  width: double.infinity,
                  placeholder: (context, url) => AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Container(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  /// 网格图片（用于双图和九宫格）
  Widget _buildGridImage(BuildContext context, String imageUrl, int index) {
    return GestureDetector(
      onTap: () => onImageTap?.call(index),
      child: AspectRatio(
        aspectRatio: 1,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Hero(
            tag: _getHeroTag(index),
            child: isVideo(imageUrl)
                ? _buildVideoThumbnail(context, imageUrl)
                : CachedNetworkImage(
                    imageUrl: imageUrl,
                    httpHeaders: buildImageHeaders(
                      imageUrl: imageUrl,
                      baseUrl: apiBaseUrl,
                      apiToken: apiToken,
                    ),
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  /// 九宫格布局
  Widget _buildNineGrid(BuildContext context) {
    final displayCount = images.length > 9 ? 9 : images.length;
    final hasMore = images.length > 9;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemCount: displayCount,
      itemBuilder: (context, index) {
        final isLast = index == displayCount - 1 && hasMore;
        
        return GestureDetector(
          onTap: () => onImageTap?.call(index),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Hero(
                  tag: _getHeroTag(index),
                  child: isVideo(images[index])
                      ? _buildVideoThumbnail(context, images[index])
                      : CachedNetworkImage(
                          imageUrl: images[index],
                          httpHeaders: buildImageHeaders(
                            imageUrl: images[index],
                            baseUrl: apiBaseUrl,
                            apiToken: apiToken,
                          ),
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Container(
                            color: colorScheme.surfaceContainerHighest,
                          ),
                        ),
                ),
                if (isLast)
                  Container(
                    color: Colors.black.withValues(alpha: 0.6),
                    child: Center(
                      child: Text(
                        '+${images.length - 9}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 视频缩略图占位
  Widget _buildVideoThumbnail(BuildContext context, String videoUrl) {
    return Container(
      color: Colors.black,
      child: Center(
        child: Icon(
          Icons.play_circle_outline,
          size: 48,
          color: Colors.white.withValues(alpha: 0.8),
        ),
      ),
    );
  }

  String _getHeroTag(int index) {
    return index == 0 ? 'content-image-$contentId' : 'image-$index-$contentId';
  }
}
