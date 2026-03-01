import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:flutter/foundation.dart';

import '../features/collection/collection_page.dart';
import '../features/collection/content_detail_page.dart';
import '../features/dashboard/dashboard_page.dart';
import '../features/review/review_page.dart';
import '../features/settings/settings_page.dart';
import '../features/auth/presentation/connect_page.dart';
import '../features/auth/presentation/onboarding_page.dart';
import '../layout/app_shell.dart';
import '../core/providers/local_settings_provider.dart';
import '../core/providers/system_status_provider.dart';

part 'app_router.g.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();

@Riverpod(keepAlive: true)
GoRouter goRouter(Ref ref) {
  final listenable = ValueNotifier<int>(0);

  // 当配置或系统状态发生改变时，通知路由重新验证
  ref.listen(localSettingsProvider, (previous, next) {
    listenable.value++;
  });
  ref.listen(systemStatusProvider, (previous, next) {
    listenable.value++;
  });

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/dashboard',
    refreshListenable: listenable,
    redirect: (context, state) {
      final settings = ref.read(localSettingsProvider);
      final systemStatus = ref.read(systemStatusProvider);

      final isConnecting = state.matchedLocation == '/connect';
      final isOnboarding = state.matchedLocation == '/onboarding';

      final hasConfig =
          settings.baseUrl.isNotEmpty && settings.apiToken.isNotEmpty;

      if (!hasConfig) {
        if (!isConnecting) return '/connect';
        return null;
      }

      // 如果已连接，检查是否需要引导
      return systemStatus.when(
        data: (status) {
          if (status.needsSetup) {
            if (!isOnboarding) return '/onboarding';
            return null;
          } else {
            if (isConnecting) return '/dashboard';

            // Release mode behavior: block onboarding if already setup
            // Debug mode behavior: allow jumping to onboarding for testing
            if (isOnboarding && !kDebugMode) return '/dashboard';

            return null;
          }
        },
        loading: () => null,
        error: (_, _) => null,
      );
    },
    routes: [
      GoRoute(
        path: '/connect',
        builder: (context, state) => const ConnectPage(),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingPage(),
      ),
      StatefulShellRoute.indexedStack(
        // builder用于构建StatefulShellRoute的UI
        // context参数是用于构建Widget的BuildContext对象
        // state参数是GoRouterState对象，包含当前路由的状态信息
        // navigationShell参数是StatefulNavigationShell对象，表示当前的导航壳，可以用于管理子路由的导航状态
        // 返回一个AppShell Widget，传入navigationShell参数
        builder: (context, state, navigationShell) {
          return AppShell(navigationShell: navigationShell);
        },
        branches: [
          // StatefulShellBranch表示一个带有状态的路由分支
          // 定义四个StatefulShellBranch，每个分支对应一个底部导航栏的选项卡
          StatefulShellBranch(
            // routes参数定义该分支下的路由列表
            routes: [
              // 定义一个GoRoute，表示仪表盘页面的路由
              GoRoute(
                path: '/dashboard', // 路由路径为/dashboard
                builder: (context, state) =>
                    const DashboardPage(), // 构建仪表盘页面的UI,生成DashboardPage Widget
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/collection',
                builder: (context, state) => const CollectionPage(),
                routes: [
                  GoRoute(
                    path: ':id',
                    pageBuilder: (context, state) {
                      final id = int.parse(state.pathParameters['id']!);
                      final color = state.uri.queryParameters['color'];
                      return CustomTransitionPage(
                        key: state.pageKey,
                        child: ContentDetailPage(
                          contentId: id,
                          initialColor: color,
                        ),
                        transitionDuration: const Duration(milliseconds: 400),
                        reverseTransitionDuration: const Duration(
                          milliseconds: 400,
                        ),
                        transitionsBuilder:
                            (context, animation, secondaryAnimation, child) {
                              return FadeTransition(
                                opacity: animation,
                                child: child,
                              );
                            },
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/review',
                builder: (context, state) => const ReviewPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                builder: (context, state) => const SettingsPage(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}
