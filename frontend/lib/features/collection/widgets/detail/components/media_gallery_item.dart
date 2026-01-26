import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../../../core/network/image_headers.dart';
import '../../common/video_player_widget.dart';
import '../gallery/full_screen_gallery.dart';
import '../../../../../core/utils/media_utils.dart';

class MediaGalleryItem extends StatelessWidget {
  final List<String> images;
  final int index;
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

  const MediaGalleryItem({
    super.key,
    required this.images,
    required this.index,
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
  });

  String get url => images[index];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveBorderRadius = borderRadius ?? BorderRadius.circular(28);

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
        decoration: BoxDecoration(
          borderRadius: effectiveBorderRadius,
        ),
        child: ClipRRect(
          borderRadius: effectiveBorderRadius,
          child: Hero(
            tag: heroTag,
            child: CachedNetworkImage(
              imageUrl: url,
              httpHeaders: buildImageHeaders(
                imageUrl: url,
                baseUrl: apiBaseUrl,
                apiToken: apiToken,
              ),
              fit: fit,
              placeholder: (c, u) => Container(
                color: theme.colorScheme.surfaceContainerHighest,
                child: const Center(child: CircularProgressIndicator()),
              ),
              errorWidget: (c, u, e) => Container(
                color: theme.colorScheme.errorContainer,
                child: const Icon(Icons.broken_image),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showFullScreenImage(BuildContext context) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.transparent,
        pageBuilder: (context, animation, secondaryAnimation) => FullScreenGallery(
          images: images,
          initialIndex: index,
          apiBaseUrl: apiBaseUrl,
          apiToken: apiToken,
          contentId: contentId,
          contentColor: contentColor,
          customHeroTag: heroTag,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }
}
