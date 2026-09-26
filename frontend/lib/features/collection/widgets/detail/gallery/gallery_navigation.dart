import 'package:flutter/material.dart';

import '../../../../../core/media/media_asset.dart';
import '../../../../../theme/design_tokens.dart';
import 'full_screen_gallery.dart';

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
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.transparent,
      transitionDuration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : AppMotion.surfaceEnter,
      reverseTransitionDuration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : AppMotion.standard,
      // The image Hero owns the geometry; never slide or scale the whole page.
      transitionsBuilder: (context, animation, secondary, child) => child,
      pageBuilder: (context, animation, secondary) => FullScreenGallery(
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
