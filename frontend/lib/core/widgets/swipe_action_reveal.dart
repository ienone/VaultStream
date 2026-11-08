import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/semantics.dart';

import '../../theme/design_tokens.dart';

class SwipeAction {
  const SwipeAction({
    required this.label,
    required this.icon,
    required this.onPressed,
    required this.background,
    required this.foreground,
  });
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final Color background, foreground;
}

/// 拖动露出操作，松手吸附；操作本身仍由按钮明确提交。
class SwipeActionReveal extends StatefulWidget {
  const SwipeActionReveal({
    super.key,
    required this.actions,
    required this.builder,
    this.resetKey,
  });
  final List<SwipeAction> actions;
  final Widget Function(BuildContext, VoidCallback showActions) builder;
  final Object? resetKey;
  @override
  State<SwipeActionReveal> createState() => _SwipeActionRevealState();
}

class _SwipeActionRevealState extends State<SwipeActionReveal>
    with SingleTickerProviderStateMixin {
  late final _reveal = AnimationController(
    vsync: this,
    duration: AppMotion.standard,
  );
  void _settle(bool open) => _reveal.animateTo(
    open ? 1 : 0,
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : AppMotion.standard,
    curve: AppMotion.standardCurve,
  );
  @override
  void didUpdateWidget(SwipeActionReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resetKey != widget.resetKey || widget.actions.isEmpty) {
      _settle(false);
    }
  }

  @override
  void dispose() {
    _reveal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final direction = Directionality.of(context) == TextDirection.ltr
        ? -1.0
        : 1.0;
    final reduced = MediaQuery.disableAnimationsOf(context);
    final enabled = widget.actions.isNotEmpty;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.min(
          constraints.maxWidth * .82,
          widget.actions.length *
              76.0 *
              MediaQuery.textScalerOf(context).scale(1).clamp(1, 1.4),
        );
        return TapRegion(
          onTapOutside: (_) => _settle(false),
          child: Semantics(
            customSemanticsActions: enabled
                ? {
                    const CustomSemanticsAction(label: '显示操作'): () =>
                        _settle(true),
                    for (final action in widget.actions)
                      CustomSemanticsAction(label: action.label):
                          action.onPressed,
                  }
                : null,
            child: GestureDetector(
              onHorizontalDragStart: enabled ? (_) => _reveal.stop() : null,
              onHorizontalDragUpdate: enabled
                  ? (d) => _reveal.value += d.delta.dx * direction / width
                  : null,
              onHorizontalDragEnd: enabled
                  ? (d) {
                      final speed = (d.primaryVelocity ?? 0) * direction;
                      _settle(
                        speed.abs() > 300 ? speed > 0 : _reveal.value > .4,
                      );
                    }
                  : null,
              onHorizontalDragCancel: enabled
                  ? () => _settle(_reveal.value > .4)
                  : null,
              child: ClipRRect(
                borderRadius: AppShape.cardBorder,
                child: AnimatedBuilder(
                  animation: _reveal,
                  child: RepaintBoundary(
                    child: widget.builder(context, () => _settle(true)),
                  ),
                  builder: (context, child) {
                    final progress = _reveal.value;
                    return Stack(
                      children: [
                        if (progress > 0 && enabled)
                          PositionedDirectional(
                            end: 0,
                            top: 0,
                            bottom: 0,
                            width: width,
                            child: ClipRect(
                              child: Align(
                                alignment: AlignmentDirectional.centerEnd,
                                child: Row(
                                  children: [
                                    for (
                                      var i = 0;
                                      i < widget.actions.length;
                                      i++
                                    )
                                      Expanded(
                                        child: _action(
                                          widget.actions[i],
                                          i,
                                          progress,
                                          reduced,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        Transform.translate(
                          key: const ValueKey('content'),
                          offset: Offset(direction * width * progress, 0),
                          child: GestureDetector(
                            onTap: progress > 0 ? () => _settle(false) : null,
                            child: IgnorePointer(
                              ignoring: progress > 0,
                              child: child,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _action(SwipeAction action, int index, double progress, bool reduced) {
    final phase = reduced
        ? 1.0
        : ((progress - index * .06) / (1 - index * .06)).clamp(0.0, 1.0);
    final eased = Curves.easeOutCubic.transform(phase);
    final radius = reduced ? 20.0 : 48 - 28 * eased;
    return Padding(
      padding: EdgeInsetsDirectional.only(
        start: 4 * progress,
        top: 4,
        bottom: 4,
      ),
      child: Transform.scale(
        scale: reduced ? 1 : .8 + .2 * eased,
        child: Material(
          color: action.background,
          borderRadius: BorderRadius.circular(radius),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              _settle(false);
              action.onPressed();
            },
            child: Center(
              child: Opacity(
                opacity: reduced ? 1 : (phase * 2).clamp(0, 1),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Transform.translate(
                      offset: Offset(0, reduced ? 0 : 10 * (1 - eased)),
                      child: Transform.rotate(
                        angle: reduced ? 0 : -.18 * (1 - eased),
                        child: Transform.scale(
                          scale: reduced ? 1 : .55 + .45 * eased,
                          child: Icon(
                            action.icon,
                            color: action.foreground,
                            size: 24,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      action.label,
                      maxLines: 1,
                      style: Theme.of(context).textTheme.labelMedium
                          ?.copyWith(color: action.foreground),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
