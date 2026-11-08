import 'dart:ui' show ImageFilter;

import 'package:material_ui/material_ui.dart';

/// High-contrast controls over photographs, shared by detail and fullscreen.
/// A stadium follows the control group's actual height, including large text.
class MediaOverlaySurface extends StatelessWidget {
  const MediaOverlaySurface({
    super.key,
    required this.child,
    this.shape = const StadiumBorder(),
  });

  final Widget child;
  final OutlinedBorder shape;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ClipPath(
      clipper: ShapeBorderClipper(shape: shape),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Material(
          color: colors.primaryContainer.withValues(alpha: .35),
          shape: shape.copyWith(
            side: BorderSide(
              color: colors.onPrimaryContainer.withValues(alpha: .15),
              width: .5,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: IconButtonTheme(
            data: IconButtonThemeData(
              style: IconButton.styleFrom(
                foregroundColor: colors.onPrimaryContainer,
                disabledForegroundColor: colors.onPrimaryContainer.withValues(
                  alpha: .38,
                ),
                minimumSize: const Size.square(48),
                padding: const EdgeInsets.all(12),
                shape: const StadiumBorder(),
              ),
            ),
            child: IconTheme.merge(
              data: IconThemeData(color: colors.onPrimaryContainer, size: 24),
              child: DefaultTextStyle.merge(
                style: TextStyle(color: colors.onPrimaryContainer),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
