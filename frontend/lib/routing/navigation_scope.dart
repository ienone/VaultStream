import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../theme/design_tokens.dart';
import 'page_origin.dart';

/// Carries the visibility of a shell route into its child Navigators.
/// A nested route can be locally current while a root dialog covers its shell.
class AppNavigationScope extends StatelessWidget {
  const AppNavigationScope({
    super.key,
    required this.child,
    this.active = true,
  });
  final Widget child;
  final bool active;

  static bool isActiveOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_NavigationVisibility>()
          ?.active ??
      true;

  @override
  Widget build(BuildContext context) => _NavigationVisibility(
    active:
        active &&
        isActiveOf(context) &&
        (ModalRoute.isCurrentOf(context) ?? true),
    child: child,
  );
}

class _NavigationVisibility extends InheritedWidget {
  const _NavigationVisibility({required this.active, required super.child});
  final bool active;
  @override
  bool updateShouldNotify(_NavigationVisibility oldWidget) =>
      active != oldWidget.active;
}

/// Page entrance, predictive preview and completion keep the same surface.
class AppPredictiveBackTransitionsBuilder extends PageTransitionsBuilder {
  const AppPredictiveBackTransitionsBuilder();

  @override
  Duration get transitionDuration => AppMotion.surfaceEnter;

  @override
  Duration get reverseTransitionDuration => AppMotion.standard;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final active =
        AppNavigationScope.isActiveOf(context) &&
        TickerMode.valuesOf(context).enabled;
    return NotificationListener<NavigationNotification>(
      onNotification: (_) => !active,
      child: PopScope<T>(
        canPop: active,
        child: _PageSurfaceTransition(
          route: route,
          animation: animation,
          active: active,
          child: child,
        ),
      ),
    );
  }
}

class _PageSurfaceTransition extends StatefulWidget {
  const _PageSurfaceTransition({
    required this.route,
    required this.animation,
    required this.active,
    required this.child,
  });
  final PageRoute<dynamic> route;
  final Animation<double> animation;
  final bool active;
  final Widget child;

  @override
  State<_PageSurfaceTransition> createState() => _PageSurfaceTransitionState();
}

class _PageSurfaceTransitionState extends State<_PageSurfaceTransition>
    with WidgetsBindingObserver {
  Rect? _lastRect, _previewStart, _settleFrom;
  double _lastRadius = 0, _settleRadius = 0;
  double _gestureStart = 1, _gestureProgress = 0, _settleAt = 1;
  bool _dragging = false, _committing = false;
  SwipeEdge _edge = SwipeEdge.left;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.animation.addStatusListener(_animationEnded);
  }

  @override
  void dispose() {
    widget.animation.removeStatusListener(_animationEnded);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _animationEnded(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      setState(() {
        _settleFrom = null;
        _previewStart = null;
        _committing = false;
      });
    }
  }

  @override
  bool handleStartBackGesture(PredictiveBackEvent event) {
    final route = widget.route;
    if (event.isButtonEvent ||
        !widget.active ||
        !route.isCurrent ||
        MediaQuery.disableAnimationsOf(context) ||
        !(route.popGestureEnabled ||
            (_settleFrom != null &&
                !_committing &&
                route.popDisposition == RoutePopDisposition.pop))) {
      return false;
    }
    _previewStart = _lastRect;
    _gestureStart = widget.animation.value;
    _edge = event.swipeEdge;
    _dragging = true;
    _settleFrom = null;
    _gestureProgress = event.progress;
    route.handleStartBackGesture(
      progress: _gestureStart * (1 - .2 * event.progress),
    );
    return true;
  }

  @override
  void handleUpdateBackGestureProgress(PredictiveBackEvent event) {
    _gestureProgress = event.progress;
    widget.route.handleUpdateBackGestureProgress(
      progress: _gestureStart * (1 - .2 * event.progress),
    );
  }

  void _settle({required bool committing}) {
    _settleFrom = _lastRect;
    _settleRadius = _lastRadius;
    _settleAt = widget.animation.value;
    _committing = committing;
    _dragging = false;
  }

  @override
  void handleCancelBackGesture() {
    _settle(committing: false);
    widget.route.handleCancelBackGesture();
  }

  @override
  void handleCommitBackGesture() async {
    _settle(committing: true);
    final route = widget.route;
    final navigator = route.navigator!;
    // Preserve the release frame. TransitionRoute.handleCommitBackGesture
    // restarts reverse at 1, which disconnects a source-bound transition.
    await navigator.maybePop();
    if (!mounted) return;
    if (route.isCurrent) {
      handleCancelBackGesture();
    } else {
      await route.completed;
      navigator.didStopUserGesture();
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.animation,
    child: widget.child,
    builder: (context, child) {
      if (MediaQuery.disableAnimationsOf(context)) return child!;
      return LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          final full = Offset.zero & size;
          final settings = widget.route.settings;
          final origin = settings is OriginMaterialPage
              ? settings.origin?.rectIn(context)
              : null;
          final closed = origin ?? full.shift(Offset(size.width, 0));
          final t = widget.animation.value.clamp(0.0, 1.0);
          double radius, opacity = 1;
          Rect rect;
          if (_dragging) {
            final p = _gestureProgress;
            final preview = Rect.fromLTWH(
              size.width * .05 + (_edge == SwipeEdge.left ? 1 : -1) * 24,
              size.height * .05,
              size.width * .9,
              size.height * .9,
            );
            rect = Rect.lerp(_previewStart ?? full, preview, p)!;
            radius = 28 * p;
          } else if (_settleFrom != null) {
            final fraction = _settleAt == 1 && !_committing
                ? 1.0
                : _committing
                ? (1 - t / _settleAt).clamp(0.0, 1.0)
                : ((t - _settleAt) / (1 - _settleAt)).clamp(0.0, 1.0);
            final progress = AppMotion.standardCurve.transform(fraction);
            rect = Rect.lerp(
              _settleFrom,
              _committing ? closed : full,
              progress,
            )!;
            radius =
                _settleRadius +
                ((_committing && origin != null ? 16 : 0) - _settleRadius) *
                    progress;
            if (_committing && origin != null) {
              opacity = 1 - const Interval(.55, 1).transform(progress);
            }
          } else {
            final progress = AppMotion.standardCurve.transform(t);
            rect = Rect.lerp(closed, full, progress)!;
            radius = origin == null ? 0 : 16 * (1 - progress);
            if (origin != null) {
              opacity = const Interval(0, .45).transform(progress);
            }
          }
          _lastRect = rect;
          _lastRadius = radius;
          // Transform a stable layout instead of laying out the whole page on
          // every gesture frame. Text, scroll position and focus stay in place.
          return Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fromRect(
                rect: rect,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(radius),
                  child: OverflowBox(
                    alignment: Alignment.topLeft,
                    minWidth: size.width,
                    maxWidth: size.width,
                    minHeight: size.height,
                    maxHeight: size.height,
                    child: Transform.scale(
                      alignment: Alignment.topLeft,
                      scale: rect.width / size.width,
                      child: Opacity(opacity: opacity, child: child),
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
