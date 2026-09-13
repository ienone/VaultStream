import 'dart:ui';

import 'package:flutter/material.dart';

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
  Widget build(BuildContext context) => ClipPath(
    clipper: ShapeBorderClipper(shape: shape),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
      child: Material(
        color: const Color(0xFF1B1B1F).withValues(alpha: .88),
        shape: shape.copyWith(
          side: BorderSide(
            color: Colors.white.withValues(alpha: .16),
            width: .5,
          ),
        ),
        child: IconButtonTheme(
          data: IconButtonThemeData(
            style: IconButton.styleFrom(
              foregroundColor: Colors.white,
              disabledForegroundColor: Colors.white38,
              minimumSize: const Size.square(48),
              padding: const EdgeInsets.all(12),
              shape: const StadiumBorder(),
            ),
          ),
          child: IconTheme.merge(
            data: const IconThemeData(color: Colors.white, size: 24),
            child: DefaultTextStyle.merge(
              style: const TextStyle(color: Colors.white),
              child: child,
            ),
          ),
        ),
      ),
    ),
  );
}
