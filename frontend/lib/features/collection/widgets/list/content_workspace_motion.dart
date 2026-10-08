import 'package:flutter/material.dart';

import '../../../../theme/design_tokens.dart';

/// Local shared-element flights: the reader itself is never moved or recreated.
class ContentWorkspaceMotion extends InheritedWidget {
  const ContentWorkspaceMotion({
    super.key,
    required this.controller,
    required super.child,
  });
  final ContentMorphController controller;
  static ContentMorphController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<ContentWorkspaceMotion>()
      ?.controller;
  @override
  bool updateShouldNotify(ContentWorkspaceMotion oldWidget) =>
      controller != oldWidget.controller;
}

class ContentMorphController {
  ContentMorphController({required TickerProvider vsync})
    : animation = AnimationController(
        vsync: vsync,
        duration: AppMotion.containerTransform,
      );
  final AnimationController animation;
  final anchors = <(int, bool), GlobalKey>{};
  final layoutOrigins = <int, Rect>{};
  int layoutEpoch = 0;
  OverlayEntry? _entry;
  final flightChildren = <(int, bool), Widget>{};
  int _revision = 0;
  bool _disposed = false;

  Future<void> navigate(
    BuildContext context,
    int id,
    VoidCallback change, {
    bool reverse = false,
  }) async {
    final revision = ++_revision;
    animation.stop();
    _clear();
    final from = anchors[(id, reverse)]?.currentContext?.findRenderObject();
    final child = flightChildren[(id, reverse)];
    if (!context.mounted || _disposed || revision != _revision) return;
    if (MediaQuery.disableAnimationsOf(context) ||
        from is! RenderBox ||
        !from.hasSize ||
        child == null) {
      change();
      return;
    }
    final overlay = Overlay.of(context);
    final overlayBox = overlay.context.findRenderObject() as RenderBox;
    final origin = overlayBox.localToGlobal(Offset.zero);
    final start = (from.localToGlobal(Offset.zero) - origin) & from.size;
    // Keep the source at its measured size; no GPU readback before navigation.
    final flight = RepaintBoundary(
      child: SizedBox.fromSize(size: from.size, child: child),
    );
    layoutOrigins.clear();
    for (final entry in anchors.entries) {
      if (entry.key.$2) continue;
      final box = entry.value.currentContext?.findRenderObject();
      if (box is RenderBox && box.hasSize) {
        layoutOrigins[entry.key.$1] = box.localToGlobal(Offset.zero) & box.size;
      }
    }
    layoutEpoch++;
    change();
    await WidgetsBinding.instance.endOfFrame;
    if (_disposed || revision != _revision || !context.mounted) {
      return;
    }
    final target = anchors[(id, !reverse)]?.currentContext?.findRenderObject();
    if (target is! RenderBox || !target.hasSize) {
      layoutOrigins.clear();
      return;
    }
    final end = (target.localToGlobal(Offset.zero) - origin) & target.size;
    _entry = OverlayEntry(
      builder: (_) => IgnorePointer(
        child: AnimatedBuilder(
          animation: animation,
          builder: (context, _) {
            final t = AppMotion.emphasizedCurve.transform(animation.value);
            final currentTarget = anchors[(id, !reverse)]?.currentContext
                ?.findRenderObject();
            final destination =
                currentTarget is RenderBox &&
                    currentTarget.attached &&
                    currentTarget.hasSize
                ? (currentTarget.localToGlobal(Offset.zero) - origin) &
                      currentTarget.size
                : end;
            final rect = Rect.lerp(start, destination, t)!;
            return Stack(
              children: [
                Positioned.fromRect(
                  rect: rect,
                  child: Opacity(
                    opacity: 1 - const Interval(.55, 1).transform(t),
                    child: ClipRRect(
                      borderRadius: AppShape.cardBorder,
                      child: FittedBox(
                        fit: BoxFit.cover,
                        alignment: Alignment.topLeft,
                        child: flight,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
    overlay.insert(_entry!);
    try {
      await animation.forward(from: 0).orCancel;
    } on TickerCanceled {
      // A newer navigation owns the overlay.
    } finally {
      if (revision == _revision) _clear();
    }
  }

  void _clear() {
    layoutOrigins.clear();
    _entry?.remove();
    _entry?.dispose();
    _entry = null;
  }

  void dispose() {
    _disposed = true;
    _revision++;
    _clear();
    animation.dispose();
  }
}

class ContentMotionAnchor extends StatefulWidget {
  const ContentMotionAnchor({
    super.key,
    required this.controller,
    required this.id,
    required this.destination,
    required this.child,
  });
  final ContentMorphController controller;
  final int id;
  final bool destination;
  final Widget child;
  @override
  State<ContentMotionAnchor> createState() => _ContentMotionAnchorState();
}

class _ContentMotionAnchorState extends State<ContentMotionAnchor>
    with SingleTickerProviderStateMixin {
  late final _reflow = AnimationController(
    vsync: this,
    duration: AppMotion.standard,
  );
  Offset _origin = Offset.zero;
  int _epoch = -1;

  void _scheduleReflow() {
    if (widget.destination || _epoch == widget.controller.layoutEpoch) return;
    _epoch = widget.controller.layoutEpoch;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || MediaQuery.disableAnimationsOf(context)) return;
      final old = widget.controller.layoutOrigins[widget.id];
      final box = _boundary.currentContext?.findRenderObject();
      if (old == null || box is! RenderBox || !box.hasSize) return;
      _origin = old.topLeft - box.localToGlobal(Offset.zero);
      _reflow.forward(from: 0);
    });
  }

  final _boundary = GlobalKey();
  @override
  void initState() {
    super.initState();
    widget.controller.anchors[(widget.id, widget.destination)] = _boundary;
    widget.controller.flightChildren[(widget.id, widget.destination)] =
        widget.child;
    _scheduleReflow();
  }

  @override
  void didUpdateWidget(ContentMotionAnchor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller.anchors[(oldWidget.id, oldWidget.destination)] ==
        _boundary) {
      oldWidget.controller.flightChildren.remove((
        oldWidget.id,
        oldWidget.destination,
      ));
      oldWidget.controller.anchors.remove((
        oldWidget.id,
        oldWidget.destination,
      ));
    }
    widget.controller.anchors[(widget.id, widget.destination)] = _boundary;
    widget.controller.flightChildren[(widget.id, widget.destination)] =
        widget.child;
    _scheduleReflow();
  }

  @override
  void dispose() {
    if (widget.controller.anchors[(widget.id, widget.destination)] ==
        _boundary) {
      widget.controller.anchors.remove((widget.id, widget.destination));
      widget.controller.flightChildren.remove((widget.id, widget.destination));
    }
    _reflow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _reflow,
    child: RepaintBoundary(key: _boundary, child: widget.child),
    builder: (context, child) => Transform.translate(
      offset: _origin * (1 - AppMotion.standardCurve.transform(_reflow.value)),
      child: child,
    ),
  );
}
