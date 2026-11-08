import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'navigation_scope.dart';

/// Media overlays share their opening animation with predictive return.
abstract interface class PredictiveOverlayRoute {
  void prepareBackGesture();
}

/// Drives the actual popup/media route, including its barrier and Hero flight.
/// Ordinary pages keep the platform PageTransitionsTheme.
class OverlayBackObserver extends NavigatorObserver
    with WidgetsBindingObserver {
  OverlayBackObserver() {
    WidgetsBinding.instance.addObserver(this);
  }

  Route<dynamic>? _top;
  ModalRoute<dynamic>? _gestureRoute;
  ModalRoute<dynamic>? _returningRoute;
  NavigatorState? _gestureNavigator;
  double _startProgress = 1;

  @override
  void didChangeTop(Route<dynamic> topRoute, Route<dynamic>? previousTopRoute) {
    _top = topRoute;
  }

  @override
  bool handleStartBackGesture(PredictiveBackEvent backEvent) {
    final route = _top;
    final owner = navigator;
    if (backEvent.isButtonEvent ||
        route is! ModalRoute<dynamic> ||
        (route is! PopupRoute && route is! PredictiveOverlayRoute) ||
        owner == null ||
        !route.isCurrent ||
        !(route.popGestureEnabled ||
            (route == _returningRoute &&
                !route.willHandlePopInternally &&
                route.popDisposition == RoutePopDisposition.pop)) ||
        !AppNavigationScope.isActiveOf(owner.context) ||
        !TickerMode.valuesOf(owner.context).enabled ||
        MediaQuery.disableAnimationsOf(owner.context)) {
      return false;
    }
    if (route is PredictiveOverlayRoute) {
      (route as PredictiveOverlayRoute).prepareBackGesture();
    }
    _gestureRoute = route;
    _gestureNavigator = owner;
    _returningRoute = null;
    _startProgress = route.animation!.value;
    route.handleStartBackGesture(
      progress: _startProgress * (1 - backEvent.progress),
    );
    return true;
  }

  @override
  void handleUpdateBackGestureProgress(PredictiveBackEvent backEvent) {
    _gestureRoute?.handleUpdateBackGestureProgress(
      progress: _startProgress * (1 - backEvent.progress),
    );
  }

  @override
  void handleCancelBackGesture() {
    _returningRoute = _gestureRoute;
    _gestureRoute?.handleCancelBackGesture();
    _gestureRoute = null;
    _gestureNavigator = null;
  }

  @override
  void handleCommitBackGesture() async {
    final route = _gestureRoute;
    final owner = _gestureNavigator;
    _gestureRoute = null;
    _gestureNavigator = null;
    if (route == null || owner == null) return;
    if (!route.isCurrent) {
      owner.didStopUserGesture();
      return;
    }
    await owner.maybePop();
    if (route.isCurrent) {
      _returningRoute = route;
      route.handleCancelBackGesture();
    } else {
      // Continue from the finger's position; the framework's default commit
      // restarts reverse at 1, which would jump back to the expanded surface.
      await route.completed;
      owner.didStopUserGesture();
    }
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _gestureNavigator?.didStopUserGesture();
    _gestureNavigator = null;
    _gestureRoute = null;
  }
}
