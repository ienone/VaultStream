import 'package:material_ui/material_ui.dart';

import '../../../../../core/media/media_asset.dart';
import '../../../../../core/motion/shared_transition.dart';
import '../../../../../core/widgets/media_image_hero.dart';
import 'full_screen_gallery.dart';

Future<void> pushFullScreenGallery({
  required BuildContext context,
  required List<String> images,
  Map<String, List<String>> fallbackUrlsByImage = const {},
  Map<String, MediaAsset> mediaAssetsByImage = const {},
  required int initialIndex,
  required int contentId,
  MediaPresentation presentation = MediaPresentation.gallery,
  void Function(int)? onPageChanged,
}) {
  assert(
    images.isNotEmpty && initialIndex >= 0 && initialIndex < images.length,
  );
  final identities = [
    for (final url in images)
      mediaImageIdentity(
        contentId: contentId,
        url: url,
        asset: mediaAssetsByImage[url],
        presentation: presentation,
      ),
  ];
  return SharedTransition.openOverlay(
    context: context,
    identity: identities[initialIndex],
    builder: (session) => FullScreenGallery(
      images: images,
      fallbackUrlsByImage: fallbackUrlsByImage,
      mediaAssetsByImage: mediaAssetsByImage,
      initialIndex: initialIndex,
      contentId: contentId,
      identities: identities,
      transition: session,
      onPageChanged: onPageChanged,
    ),
  );
}
