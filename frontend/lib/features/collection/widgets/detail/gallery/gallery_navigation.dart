import 'package:flutter/material.dart';

import '../../../../../core/media/media_asset.dart';
import '../../../../../theme/design_tokens.dart';
import 'full_screen_gallery.dart';

/// A media overlay has its own drag dismissal; it is not a page transition.
class _GalleryRoute extends PageRouteBuilder<void> {
  _GalleryRoute({required WidgetBuilder builder, required bool reduceMotion})
    : super(
        opaque: false,
        transitionDuration: reduceMotion
            ? Duration.zero
            : AppMotion.surfaceEnter,
        reverseTransitionDuration: reduceMotion
            ? Duration.zero
            : AppMotion.standard,
        pageBuilder: (context, animation, secondaryAnimation) =>
            builder(context),
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            child,
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
