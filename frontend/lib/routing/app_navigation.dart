import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

/// A root dialog can close while an active shell still handles back.
/// Its root Navigator notification alone does not describe that nested stack.
bool handleAppNavigationNotification(
  GoRouter router,
  NavigationNotification notification,
) {
  var canHandlePop = notification.canHandlePop || router.canPop();
  final matches = router.routerDelegate.currentConfiguration.matches;
  if (!canHandlePop && matches.isNotEmpty) {
    RouteMatchBase match = matches.last;
    while (match is ShellRouteMatch) {
      final navigatorContext = match.navigatorKey.currentContext;
      final route = navigatorContext == null
          ? null
          : ModalRoute.of(navigatorContext);
      if (route == null || !route.isCurrent) break;
      if (route.popDisposition == RoutePopDisposition.doNotPop) {
        canHandlePop = true;
        break;
      }
      match = match.matches.last;
    }
  }
  if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.detached) {
    unawaited(SystemNavigator.setFrameworkHandlesBack(canHandlePop));
  }
  return true;
}

/// Open a product link without pushing a second instance of the stateful shell.
void openAppLocation(BuildContext context, String location) {
  final path = Uri.parse(location).path;
  if (path == '/home' ||
      path == '/collection' ||
      path == '/automation' ||
      path.startsWith('/automation/')) {
    context.go(location);
  } else {
    context.push(location);
  }
}

class AppBackButton extends StatelessWidget {
  const AppBackButton({super.key, this.fallback = '/home'});

  final String fallback;

  @override
  Widget build(BuildContext context) => BackButton(
    onPressed: () {
      if (context.canPop()) {
        context.pop();
      } else {
        context.go(fallback);
      }
    },
  );
}
