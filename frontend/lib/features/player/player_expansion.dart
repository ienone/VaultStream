import 'dart:ui' show lerpDouble;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../../core/motion/shared_transition.dart';
import '../../theme/design_tokens.dart';
import 'player_page.dart';

/// The compact player expands above its source page without replacing the session.
Future<void> expandPlayer(BuildContext context) {
  final box = context.findRenderObject() as RenderBox;
  Rect origin() => box.attached && box.hasSize
      ? box.localToGlobal(Offset.zero) & box.size
      : Rect.zero;
  return SharedTransition.openOverlay(
    context: context,
    identity: 'playback-panel',
    builder: (session) => _PlayerExpansion(session: session, origin: origin),
  );
}

class _PlayerExpansion extends StatelessWidget {
  const _PlayerExpansion({required this.session, required this.origin});
  final SharedTransitionSession session;
  final Rect Function() origin;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final padding = MediaQuery.paddingOf(context);
      final inset = box.maxWidth >= 600 ? 16.0 : 0.0;
      final target = Rect.fromLTRB(
        inset,
        padding.top + inset,
        box.maxWidth - inset,
        box.maxHeight - padding.bottom - inset,
      );
      final surface = Theme.of(context).colorScheme.surface;
      final page = CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): session.close,
        },
        child: Focus(
          autofocus: true,
          child: PlayerPage(onCollapse: session.close),
        ),
      );
      return AnimatedBuilder(
        animation: session.progress,
        child: page,
        builder: (context, child) {
          final progress = AppMotion.standardCurve.transform(
            session.progress.value,
          );
          final source = origin();
          final bounds = Rect.lerp(
            source.isEmpty ? target : source,
            target,
            progress,
          )!;
          return Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  onTap: session.close,
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: .25 * progress),
                  ),
                ),
              ),
              Positioned.fromRect(
                rect: bounds,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(
                    lerpDouble(16, inset == 0 ? 0 : 24, progress)!,
                  ),
                  child: ColoredBox(
                    color: surface,
                    child: OverflowBox(
                      alignment: Alignment.bottomCenter,
                      minWidth: target.width,
                      maxWidth: target.width,
                      minHeight: target.height,
                      maxHeight: target.height,
                      child: Opacity(opacity: progress, child: child),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      );
    },
  );
}
