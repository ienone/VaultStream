import 'package:flutter/material.dart';

/// Keep one image at its decoded aspect ratio while its visible crop expands.
class MediaImageHero extends StatelessWidget {
  const MediaImageHero({
    super.key,
    required this.tag,
    required this.child,
    this.borderRadius = BorderRadius.zero,
  });

  final Object tag;
  final Widget child;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) => Hero(
    tag: tag,
    flightShuttleBuilder: (context, animation, direction, from, to) {
      final fromImage = (from.widget as Hero).child as ClipRRect;
      final toImage = (to.widget as Hero).child as ClipRRect;
      final expanded = direction == HeroFlightDirection.push ? to : from;
      final size = (expanded.findRenderObject()! as RenderBox).size;
      final image = direction == HeroFlightDirection.push ? toImage : fromImage;
      return AnimatedBuilder(
        animation: animation,
        builder: (context, _) {
          final progress = direction == HeroFlightDirection.push
              ? animation.value
              : 1 - animation.value;
          return ClipRRect(
            borderRadius: BorderRadiusGeometry.lerp(
              fromImage.borderRadius,
              toImage.borderRadius,
              progress,
            )!,
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox.fromSize(size: size, child: image.child),
            ),
          );
        },
      );
    },
    child: ClipRRect(borderRadius: borderRadius, child: child),
  );
}
