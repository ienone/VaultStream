import 'package:flutter/material.dart';
import '../../../../../core/media/media_asset.dart';
import '../../../../../core/widgets/network_thumbnail.dart';
import '../../../../player/global_playback_controller.dart';
import '../../../../player/global_player_widgets.dart';
import '../../../../../theme/design_tokens.dart';
import '../gallery/gallery_navigation.dart';
import '../../../../../core/utils/media_utils.dart';

class MediaGalleryItem extends StatelessWidget {
  final List<String> images;
  final int index;
  final Map<String, List<String>> fallbackUrlsByImage;
  final Map<String, MediaAsset> mediaAssetsByImage;
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
    this.mediaAssetsByImage = const {},
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
    final effectiveBorderRadius = borderRadius ?? AppShape.sheetBorder;
    final mediaAsset = mediaAssetsByImage[url];

    if (isVideoItem ||
        mediaAsset?.mediaType == MediaType.video ||
        isVideo(url)) {
      return ClipRRect(
        borderRadius: effectiveBorderRadius,
        child: GlobalPlaybackSurface(
          activateOnMount: false,
          request: PlaybackRequest(
            contentId: contentId,
            title:
                mediaAsset?.caption ?? mediaAsset?.altText ?? '视频 ${index + 1}',
            urls: [url, ...?fallbackUrlsByImage[url]],
            audioOnly: false,
            mediaAsset: mediaAsset,
          ),
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
              mediaAsset: mediaAssetsByImage[url],
              purpose: MediaPurpose.detail,
              fallbackUrls: fallbackUrlsByImage[url] ?? const [],
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
      mediaAssetsByImage: mediaAssetsByImage,
      initialIndex: index,
      contentId: contentId,
      contentColor: contentColor,
      customHeroTag: heroTag,
      onPageChanged: onPageChanged,
    );
  }
}
