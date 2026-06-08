import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:flutter/foundation.dart';

import '../features/collection/collection_page.dart';
import '../features/collection/content_detail_page.dart';
import '../features/collection/models/content.dart';
import '../features/dashboard/dashboard_page.dart';
import '../features/dashboard/task_result_page.dart';
import '../features/discovery/discovery_page.dart';
import '../features/review/review_page.dart';
import '../features/settings/settings_page.dart';
import '../features/agent/agent_page.dart';
import '../features/accounts/account_center_page.dart';
import '../features/auth/presentation/connect_page.dart';
import '../features/auth/presentation/onboarding_page.dart';
import '../layout/app_shell.dart';
import '../core/providers/local_settings_provider.dart';
import '../core/providers/system_status_provider.dart';
import '../theme/design_tokens.dart';

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
    initialLocation: '/home',
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
            if (isConnecting) return '/home';

            // Release mode behavior: block onboarding if already setup
            // Debug mode behavior: allow jumping to onboarding for testing
            if (isOnboarding && !kDebugMode) return '/home';

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
      GoRoute(
        path: '/accounts',
        builder: (context, state) => const AccountCenterPage(),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) =>
            SettingsPage(initialTab: state.uri.queryParameters['tab']),
      ),
      GoRoute(path: '/agent', builder: (context, state) => const AgentPage()),
      GoRoute(
        path: '/tasks/:runId',
        builder: (context, state) =>
            TaskResultPage(runId: state.pathParameters['runId']!),
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
          // StatefulShellBranch 表示一个带有状态的主导航分支。
          // 主导航只承载高频任务入口：动态、收藏库、收件箱、自动化。
          StatefulShellBranch(
            // routes参数定义该分支下的路由列表
            routes: [
              GoRoute(
                path: '/home',
                builder: (context, state) => DashboardPage(
                  highlightRunId: state.uri.queryParameters['run'],
                ),
              ),
              GoRoute(
                path: '/dashboard',
                redirect: (context, state) => '/home',
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
                      final preview = state.extra is ShareCard
                          ? state.extra as ShareCard
                          : null;
                      return CustomTransitionPage(
                        key: state.pageKey,
                        child: ContentDetailPage(
                          contentId: id,
                          initialColor: color,
                          preview: preview,
                        ),
                        transitionDuration: AppMotion.routeTransition,
                        reverseTransitionDuration: AppMotion.routeTransition,
                        transitionsBuilder:
                            (context, animation, secondaryAnimation, child) {
                              final curved = CurvedAnimation(
                                parent: animation,
                                curve: AppMotion.standardCurve,
                              );
                              return FadeTransition(
                                opacity: Tween<double>(
                                  begin: 0.96,
                                  end: 1,
                                ).animate(curved),
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
                path: '/inbox',
                builder: (context, state) => const DiscoveryPage(),
              ),
              GoRoute(
                path: '/discovery',
                redirect: (context, state) => '/inbox',
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/automation',
                builder: (context, state) => ReviewPage(
                  initialTab: state.uri.queryParameters['tab'],
                  highlightRunId: state.uri.queryParameters['run'],
                ),
              ),
              GoRoute(
                path: '/review',
                redirect: (context, state) => '/automation',
              ),
            ],
          ),
        ],
      ),
    ],
  );
}
