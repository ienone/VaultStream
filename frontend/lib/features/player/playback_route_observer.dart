import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final playbackRouteObserverProvider = Provider<PlaybackRouteObserver>((ref) {
  final observer = PlaybackRouteObserver();
  ref.onDispose(observer.topPage.dispose);
  return observer;
});

/// Popup menus and dialogs do not take ownership of the page's web video.
/// Full-screen media uses a PageRoute and participates in the handoff.
class PlaybackRouteObserver extends NavigatorObserver {
  final topPage = ValueNotifier<Route<dynamic>?>(null);
  final _routes = <Route<dynamic>>[];

  bool ownsPage(Route<dynamic>? route) =>
      route == null ||
      (_routes.contains(route) ? route == topPage.value : route.isCurrent);

  void _update() {
    topPage.value = _routes.whereType<PageRoute<dynamic>>().lastOrNull;
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.add(route);
    _update();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _update();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _update();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute == null) return;
    final index = _routes.indexOf(oldRoute);
    if (index >= 0) {
      if (newRoute == null) {
        _routes.removeAt(index);
      } else {
        _routes[index] = newRoute;
      }
    }
    _update();
  }
}
