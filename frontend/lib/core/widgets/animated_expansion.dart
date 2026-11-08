import 'package:material_ui/material_ui.dart';

import '../../theme/design_tokens.dart';

/// Keeps content mounted through collapse and reverses from its current size.
class AnimatedExpansion extends StatelessWidget {
  const AnimatedExpansion({
    super.key,
    required this.expanded,
    required this.child,
    this.alignment = Alignment.topCenter,
  });

  final bool expanded;
  final Widget child;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: expanded ? 1 : 0),
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : AppMotion.stateChange,
    curve: AppMotion.standardCurve,
    builder: (context, value, _) => value == 0
        ? const SizedBox.shrink()
        : IgnorePointer(
            ignoring: !expanded,
            child: ExcludeSemantics(
              excluding: !expanded,
              child: ClipRect(
                child: Align(
                  alignment: alignment,
                  heightFactor: value,
                  child: child,
                ),
              ),
            ),
          ),
  );
}
