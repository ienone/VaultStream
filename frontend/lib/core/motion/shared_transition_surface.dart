import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import 'shared_transition.dart';

/// Route progress and the feature's interactive dismissal drive one surface.
class SharedTransitionSurface extends StatelessWidget {
  const SharedTransitionSurface({
    super.key,
    required this.session,
    required this.dismissal,
    required this.child,
    this.backdrop = false,
  });

  final SharedTransitionSession session;
  final ValueListenable<double> dismissal;
  final Widget child;
  final bool backdrop;

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    return AnimatedBuilder(
      animation: Listenable.merge([session.progress, dismissal]),
      child: child,
      builder: (context, child) {
        final amount = session.progress.value * (1 - dismissal.value);
        if (!backdrop) return Opacity(opacity: amount, child: child);
        return ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12 * amount, sigmaY: 12 * amount),
            child: ColoredBox(
              color: surface.withValues(alpha: .2 * amount),
              child: child,
            ),
          ),
        );
      },
    );
  }
}
