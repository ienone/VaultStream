import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:frontend/routing/navigation_scope.dart';
import 'package:frontend/routing/app_navigation.dart';
import 'package:frontend/core/widgets/predictive_back_dialog.dart';

Future<void> gesture(
  WidgetTester tester,
  String method, [
  double? progress,
]) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/backgesture',
    const StandardMethodCodec().encodeMethodCall(
      MethodCall(
        method,
        progress == null
            ? null
            : <String, dynamic>{
                'touchOffset': <double>[100, 300],
                'progress': progress,
                'swipeEdge': 0,
              },
      ),
    ),
    (_) {},
  );
  await tester.pump();
}

void main() {
  testWidgets('root modal owns back without removing its nested source page', (
    tester,
  ) async {
    final key = GlobalKey<NavigatorState>();
    final router = GoRouter(
      navigatorKey: key,
      initialLocation: '/home',
      routes: [
        ShellRoute(
          builder: (context, state, child) => AppNavigationScope(child: child),
          routes: [
            GoRoute(
              path: '/home',
              builder: (context, state) => const Scaffold(body: Text('home')),
            ),
            GoRoute(
              path: '/detail',
              builder: (context, state) => Scaffold(
                body: TextField(
                  key: const ValueKey('draft'),
                  decoration: const InputDecoration(labelText: 'draft'),
                ),
              ),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(
        theme: AppTheme.light(null),
        routerConfig: router,
        onNavigationNotification: (n) =>
            handleAppNavigationNotification(router, n),
      ),
    );
    await tester.pumpAndSettle();
    router.push('/detail');
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('draft')), 'preserved');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    showDialog<void>(
      context: key.currentContext!,
      builder: (context) => const PredictiveBackDialog(
        child: AlertDialog(title: Text('root modal')),
      ),
    );
    await tester.pumpAndSettle();
    final initialDialog = tester.getRect(find.byType(AlertDialog));
    await gesture(tester, 'startBackGesture', 0);
    await gesture(tester, 'updateBackGestureProgress', .4);
    final previewDialog = tester.getRect(find.byType(AlertDialog));
    expect(previewDialog.width, lessThan(initialDialog.width));
    expect(previewDialog.center.dx, greaterThan(initialDialog.center.dx));
    await gesture(tester, 'cancelBackGesture');
    await tester.pumpAndSettle();
    expect(
      router.routerDelegate.currentConfiguration.last.matchedLocation,
      '/detail',
    );
    expect(find.text('root modal'), findsOneWidget);
    expect(tester.getRect(find.byType(AlertDialog)), initialDialog);
    expect(key.currentState!.userGestureInProgress, isFalse);
    await gesture(tester, 'startBackGesture', 0);
    await gesture(tester, 'updateBackGestureProgress', .7);
    await gesture(tester, 'commitBackGesture');
    await tester.pumpAndSettle();
    expect(find.text('root modal'), findsNothing);
    expect(
      router.routerDelegate.currentConfiguration.last.matchedLocation,
      '/detail',
    );
    expect(find.text('preserved'), findsOneWidget);
    // Once uncovered, the same page must regain the real predictive route transition.
    final detailRoute = ModalRoute.of(
      tester.element(find.byKey(const ValueKey('draft'))),
    )!;
    await gesture(tester, 'startBackGesture', 0);
    await gesture(tester, 'updateBackGestureProgress', .35);
    expect(detailRoute.navigator!.userGestureInProgress, isTrue);
    expect(detailRoute.animation!.value, closeTo(.65, .001));
    await gesture(tester, 'cancelBackGesture');
    await tester.pumpAndSettle();
    expect(find.text('preserved'), findsOneWidget);
    await gesture(tester, 'startBackGesture', 0);
    await gesture(tester, 'updateBackGestureProgress', .7);
    await gesture(tester, 'commitBackGesture');
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('inactive branch releases system back and retains guarded draft', (
    tester,
  ) async {
    final systemBack = <bool>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'SystemNavigator.setFrameworkHandlesBack') {
          systemBack.add(call.arguments as bool);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final homeCanPop = ValueNotifier(true);
    addTearDown(homeCanPop.dispose);
    late StatefulNavigationShell shell;
    final router = GoRouter(
      initialLocation: '/a',
      routes: [
        ShellRoute(
          builder: (context, state, child) => AppNavigationScope(child: child),
          routes: [
            StatefulShellRoute.indexedStack(
              builder: (context, state, navigationShell) {
                shell = navigationShell;
                return AppNavigationScope(
                  child: PopScope(
                    canPop: navigationShell.currentIndex == 0,
                    child: navigationShell,
                  ),
                );
              },
              branches: [
                StatefulShellBranch(
                  routes: [
                    GoRoute(
                      path: '/a',
                      builder: (context, state) => ValueListenableBuilder(
                        valueListenable: homeCanPop,
                        builder: (context, canPop, _) => PopScope(
                          canPop: canPop,
                          child: const Scaffold(body: Text('branch a')),
                        ),
                      ),
                    ),
                  ],
                ),
                StatefulShellBranch(
                  routes: [
                    GoRoute(
                      path: '/b',
                      builder: (context, state) =>
                          const Scaffold(body: Text('branch b')),
                      routes: [
                        GoRoute(
                          path: 'draft',
                          builder: (context, state) => const PopScope(
                            canPop: false,
                            child: Scaffold(
                              body: TextField(key: ValueKey('branch-draft')),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(
        theme: AppTheme.light(null),
        routerConfig: router,
        onNavigationNotification: (n) =>
            handleAppNavigationNotification(router, n),
      ),
    );
    await tester.pumpAndSettle();
    expect(systemBack.last, isFalse);
    router.go('/b/draft');
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('branch-draft')),
      'branch input',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    expect(systemBack.last, isTrue);
    shell.goBranch(0);
    await tester.pumpAndSettle();
    expect(find.text('branch a'), findsOneWidget);
    expect(router.canPop(), isFalse);
    expect(
      systemBack.last,
      isFalse,
      reason: 'hidden stack must release system back-to-home',
    );
    // A real guard on the visible root must still own system back, even though
    // router.canPop() is false. Releasing it must restore the system preview.
    homeCanPop.value = false;
    await tester.pumpAndSettle();
    expect(systemBack.last, isTrue);
    homeCanPop.value = true;
    await tester.pumpAndSettle();
    expect(systemBack.last, isFalse);
    await gesture(tester, 'startBackGesture', 0);
    await gesture(tester, 'updateBackGestureProgress', .7);
    await gesture(tester, 'commitBackGesture');
    await tester.pumpAndSettle();
    shell.goBranch(1);
    await tester.pumpAndSettle();
    expect(find.text('branch input'), findsOneWidget);
    expect(router.canPop(), isTrue);
    expect(systemBack.last, isTrue);
    await gesture(tester, 'startBackGesture', 0);
    await gesture(tester, 'updateBackGestureProgress', .7);
    await gesture(tester, 'commitBackGesture');
    await tester.pumpAndSettle();
    expect(
      find.text('branch input'),
      findsOneWidget,
      reason: 'visible draft guard still blocks back',
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
