import 'package:material_ui/material_ui.dart';

import '../../theme/design_tokens.dart';

/// Related panes and their handles consume one interpolated layout value.
class SharedLayoutTransition extends StatelessWidget {
  const SharedLayoutTransition({
    super.key,
    required this.value,
    required this.animate,
    required this.builder,
    this.onEnd,
  });

  final double value;
  final bool animate;
  final Widget Function(BuildContext context, double value) builder;
  final VoidCallback? onEnd;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(end: value),
    duration: animate && !MediaQuery.disableAnimationsOf(context)
        ? AppMotion.standard
        : Duration.zero,
    curve: AppMotion.standardCurve,
    onEnd: onEnd,
    builder: (context, value, _) => builder(context, value),
  );
}
