import 'package:flutter/material.dart';

/// Carries the visibility of a shell route into its child Navigators.
/// A nested route can be locally current while a root dialog covers its shell.
class AppNavigationScope extends StatelessWidget {
  const AppNavigationScope({super.key, required this.child});
  final Widget child;

  static bool _isActive(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_NavigationVisibility>()
          ?.active ??
      true;

  @override
  Widget build(BuildContext context) => _NavigationVisibility(
    active: _isActive(context) && (ModalRoute.isCurrentOf(context) ?? true),
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

/// Keeps the platform transition, but only lets the visible navigation branch
/// participate. PopScope composes with a page's own unsaved-work guard.
class AppPredictiveBackTransitionsBuilder
    extends PredictiveBackPageTransitionsBuilder {
  const AppPredictiveBackTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final active =
        AppNavigationScope._isActive(context) &&
        TickerMode.valuesOf(context).enabled;
    return NotificationListener<NavigationNotification>(
      // A hidden route still guards its own stack, but its notification must
      // not claim system back on behalf of the visible branch.
      onNotification: (_) => !active,
      child: PopScope<T>(
        canPop: active,
        child: super.buildTransitions(
          route,
          context,
          animation,
          secondaryAnimation,
          child,
        ),
      ),
    );
  }
}
