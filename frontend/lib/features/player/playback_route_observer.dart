import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final playbackRouteObserverProvider = Provider<PlaybackRouteObserver>((ref) {
  final observer = PlaybackRouteObserver();
  ref.onDispose(observer.revision.dispose);
  return observer;
});

/// Popup menus and dialogs do not take ownership of the page's web video.
/// Full-screen media uses a PageRoute and participates in the handoff.
class PlaybackRouteObserver extends NavigatorObserver {
  final revision = ValueNotifier<int>(0);
  final _routes = <Route<dynamic>>[];

  bool ownsPage(Route<dynamic>? route) {
    if (route == null) return true;
    if (!_routes.contains(route)) return route.isCurrent;
    // GoRouter forwards nested Navigator events to its root observers.
    // A shell and its child page can both be current in their own stacks.
    return route ==
        _routes
            .whereType<PageRoute<dynamic>>()
            .where((candidate) => candidate.navigator == route.navigator)
            .lastOrNull;
  }

  void _update() {
    revision.value++;
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
