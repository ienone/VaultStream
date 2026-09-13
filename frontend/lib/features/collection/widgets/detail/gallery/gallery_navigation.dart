import 'package:flutter/material.dart';

import '../../../../../core/media/media_asset.dart';
import 'full_screen_gallery.dart';

/// Keep the source visible during drag dismissal while using platform back motion.
class _GalleryRoute extends PageRoute<void>
    with MaterialRouteTransitionMixin<void> {
  _GalleryRoute({required this.builder});

  final WidgetBuilder builder;

  @override
  Widget buildContent(BuildContext context) => builder(context);

  @override
  bool get maintainState => true;

  @override
  bool get opaque => false;
}

Future<void> pushFullScreenGallery({
  required BuildContext context,
  required List<String> images,
  Map<String, List<String>> fallbackUrlsByImage = const {},
  Map<String, MediaAsset> mediaAssetsByImage = const {},
  required int initialIndex,
  required int contentId,
  Color? contentColor,
  String? customHeroTag,
  void Function(int)? onPageChanged,
}) {
  return Navigator.of(context, rootNavigator: true).push(
    _GalleryRoute(
      builder: (context) => FullScreenGallery(
        images: images,
        fallbackUrlsByImage: fallbackUrlsByImage,
        mediaAssetsByImage: mediaAssetsByImage,
        initialIndex: initialIndex,
        contentId: contentId,
        contentColor: contentColor,
        customHeroTag: customHeroTag,
        onPageChanged: onPageChanged,
      ),
    ),
  );
}
