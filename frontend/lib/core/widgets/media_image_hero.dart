import 'package:material_ui/material_ui.dart';

import '../media/media_asset.dart';
import '../motion/shared_transition.dart';

enum MediaPresentation { gallery, body }

typedef MediaImageIdentity = ({
  int contentId,
  Object asset,
  MediaPresentation presentation,
});

MediaImageIdentity mediaImageIdentity({
  required int contentId,
  required String url,
  MediaAsset? asset,
  MediaPresentation presentation = MediaPresentation.gallery,
}) => (
  contentId: contentId,
  asset: asset == null ? url : asset.id,
  presentation: presentation,
);

/// Keep one image at its decoded aspect ratio while its visible crop expands.
class MediaImageHero extends StatelessWidget {
  const MediaImageHero({
    super.key,
    required this.identity,
    required this.child,
    this.session,
    this.borderRadius = BorderRadius.zero,
  });

  final MediaImageIdentity identity;
  final SharedTransitionSession? session;
  final Widget child;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) => SharedElement(
    identity: identity,
    session: session,
    flightShuttleBuilder: (context, animation, direction, from, to) {
      final fromImage = (from.widget as Hero).child as ClipRRect;
      final toImage = (to.widget as Hero).child as ClipRRect;
      final expanded = direction == HeroFlightDirection.push ? to : from;
      final size = (expanded.findRenderObject()! as RenderBox).size;
      // The departing endpoint already has decoded pixels, including on the
      // first open when the destination requests a higher-resolution image.
      return ExcludeSemantics(
        child: IgnorePointer(
          child: AnimatedBuilder(
            animation: animation,
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox.fromSize(size: size, child: fromImage.child),
            ),
            builder: (context, child) {
              final progress = direction == HeroFlightDirection.push
                  ? animation.value
                  : 1 - animation.value;
              return ClipRRect(
                borderRadius: BorderRadiusGeometry.lerp(
                  fromImage.borderRadius,
                  toImage.borderRadius,
                  progress,
                )!,
                child: child,
              );
            },
          ),
        ),
      );
    },
    child: ClipRRect(borderRadius: borderRadius, child: child),
  );
}
