import 'package:flutter/material.dart';

import '../../../../../core/media/media_asset.dart';
import 'full_screen_gallery.dart';

/// A media overlay has its own drag dismissal; it is not a page transition.
class _GalleryRoute extends PageRouteBuilder<void> {
  _GalleryRoute({required WidgetBuilder builder, required bool reduceMotion})
    : super(
        opaque: false,
        transitionDuration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 260),
        reverseTransitionDuration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 240),
        pageBuilder: (context, animation, secondaryAnimation) =>
            builder(context),
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            FadeTransition(opacity: animation, child: child),
      );

  @override
  bool get popGestureEnabled => false;
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
      reduceMotion: MediaQuery.disableAnimationsOf(context),
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
