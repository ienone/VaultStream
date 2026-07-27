import 'package:flutter/material.dart';
import '../../../../../core/network/image_headers.dart';
import '../../../../../core/widgets/network_thumbnail.dart';
import '../../common/video_player_widget.dart';
import '../../../../../theme/design_tokens.dart';
import '../gallery/gallery_navigation.dart';
import '../../../../../core/utils/media_utils.dart';

class MediaGalleryItem extends StatelessWidget {
  final List<String> images;
  final int index;
  final Map<String, List<String>> fallbackUrlsByImage;
  final String apiBaseUrl;
  final String? apiToken;
  final int contentId;
  final Color? contentColor;
  final bool isVideoItem;
  final String heroTag;
  final BoxFit fit;
  final double? height;
  final double? width;
  final BorderRadius? borderRadius;
  final Function(int)? onPageChanged;

  const MediaGalleryItem({
    super.key,
    required this.images,
    required this.index,
    this.fallbackUrlsByImage = const {},
    required this.apiBaseUrl,
    this.apiToken,
    required this.contentId,
    this.contentColor,
    this.isVideoItem = false,
    required this.heroTag,
    this.fit = BoxFit.cover,
    this.height,
    this.width,
    this.borderRadius,
    this.onPageChanged,
  });

  String get url => images[index];

  @override
  Widget build(BuildContext context) {
    final effectiveBorderRadius =
        borderRadius ?? BorderRadius.circular(AppRadius.xxl);

    if (isVideoItem || isVideo(url)) {
      return ClipRRect(
        borderRadius: effectiveBorderRadius,
        child: Stack(
          children: [
            VideoPlayerWidget(
              videoUrl: url,
              headers: buildImageHeaders(
                imageUrl: url,
                baseUrl: apiBaseUrl,
                apiToken: apiToken,
              ),
            ),
            // We can add a play overlay here if needed for grid view
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: () => _showFullScreenImage(context),
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(borderRadius: effectiveBorderRadius),
        child: ClipRRect(
          borderRadius: effectiveBorderRadius,
          child: Hero(
            tag: heroTag,
            child: NetworkThumbnail(
              imageUrl: url,
              fallbackUrls: fallbackUrlsByImage[url] ?? const [],
              httpHeaders: buildImageHeaders(
                imageUrl: url,
                baseUrl: apiBaseUrl,
                apiToken: apiToken,
              ),
              width: width,
              height: height,
              fit: fit,
              errorIcon: Icons.broken_image,
            ),
          ),
        ),
      ),
    );
  }

  void _showFullScreenImage(BuildContext context) {
    pushFullScreenGallery(
      context: context,
      images: images,
      fallbackUrlsByImage: fallbackUrlsByImage,
      initialIndex: index,
      apiBaseUrl: apiBaseUrl,
      apiToken: apiToken,
      contentId: contentId,
      contentColor: contentColor,
      customHeroTag: heroTag,
      onPageChanged: onPageChanged,
    );
  }
}
