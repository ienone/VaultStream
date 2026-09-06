import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:flutter/foundation.dart';

import '../features/collection/collection_page.dart';
import '../features/collection/content_detail_page.dart';
import '../features/collection/models/content.dart';
import '../features/dashboard/dashboard_page.dart';
import '../features/dashboard/task_result_page.dart';
import '../features/automation/automation_page.dart';
import '../features/automation/distribution_rule_page.dart';
import '../features/settings/settings_page.dart';
import '../features/agent/agent_page.dart';
import '../features/accounts/account_center_page.dart';
import '../features/accounts/account_detail_page.dart';
import '../features/notifications/notification_center_page.dart';
import '../features/events/event_detail_page.dart';
import '../features/search/search_page.dart';
import '../features/player/player_page.dart';
import '../features/player/global_playback_controller.dart';
import '../features/player/global_player_widgets.dart';
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
  // Imperative navigation is used for details and tools throughout the app.
  // Reflect those routes in the browser so every product view remains
  // refreshable and shareable instead of leaving the previous shell URL.
  GoRouter.optionURLReflectsImperativeAPIs = true;

  final listenable = ValueNotifier<int>(0);

  // 当配置或系统状态发生改变时，通知路由重新验证
  ref.listen(localSettingsProvider, (previous, next) {
    listenable.value++;
  });
  ref.listen(systemStatusProvider, (previous, next) {
    listenable.value++;
  });

  final router = GoRouter(
    navigatorKey: _rootNavigatorKey,
    observers: [
      _PlaybackNavigationObserver(
        (settled) => ref
            .read(globalPlaybackProvider.notifier)
            .preservePlaybackOnViewRemoval(settled),
      ),
    ],
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
      ShellRoute(
        builder: (context, state, child) {
          final location = state.matchedLocation;
          final appShellOwnsMiniPlayer =
              location == '/home' ||
              location == '/collection' ||
              location.startsWith('/automation') ||
              location.startsWith('/collection/');
          return GlobalPlaybackChrome(
            showMiniPlayer: location != '/player' && !appShellOwnsMiniPlayer,
            child: child,
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
            path: '/settings',
            builder: (context, state) =>
                SettingsPage(initialTab: state.uri.queryParameters['tab']),
          ),
          GoRoute(
            path: '/agent',
            builder: (context, state) => AgentPage(
              initialSessionId: state.uri.queryParameters['session_id'],
              initialPrompt: state.uri.queryParameters['prompt'],
            ),
          ),
          GoRoute(
            path: '/search',
            builder: (context, state) => SearchPage(
              initialQuery: state.uri.queryParameters['q'] ?? '',
              initialKind: state.uri.queryParameters['kind'] ?? 'all',
              initialContentScope:
                  state.uri.queryParameters['content_scope'] ?? 'library',
            ),
          ),
          GoRoute(
            path: '/player',
            builder: (context, state) => const PlayerPage(),
          ),
          GoRoute(
            path: '/accounts',
            builder: (context, state) => const AccountCenterPage(),
          ),
          GoRoute(
            path: '/accounts/:platform',
            builder: (context, state) =>
                AccountDetailPage(platform: state.pathParameters['platform']!),
          ),
          GoRoute(
            path: '/notifications',
            builder: (context, state) => const NotificationCenterPage(),
          ),
          GoRoute(
            path: '/events/:id',
            builder: (context, state) => EventDetailPage(
              eventId: int.parse(state.pathParameters['id']!),
            ),
          ),
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
              return AppShell(
                navigationShell: navigationShell,
                currentLocation: state.uri.path,
              );
            },
            branches: [
              // StatefulShellBranch 表示一个带有状态的主导航分支。
              // 主导航只承载高频任务入口：动态、收藏库、自动化。
              StatefulShellBranch(
                // routes参数定义该分支下的路由列表
                routes: [
                  GoRoute(
                    path: '/home',
                    builder: (context, state) => const DashboardPage(),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: '/collection',
                    builder: (context, state) => CollectionPage(
                      initialPlatforms: _queryList(state, 'platform'),
                      initialStatuses: _queryList(state, 'status'),
                      initialAuthor: state.uri.queryParameters['author'],
                      initialTags: _queryList(state, 'tag'),
                      initialDateRange: _queryDateRange(state),
                    ),
                    routes: [
                      GoRoute(
                        path: ':id',
                        parentNavigatorKey: _rootNavigatorKey,
                        pageBuilder: (context, state) {
                          final id = int.parse(state.pathParameters['id']!);
                          final color = state.uri.queryParameters['color'];
                          final playbackSeconds = double.tryParse(
                            state.uri.queryParameters['t'] ?? '',
                          );
                          final mediaAssetId = int.tryParse(
                            state.uri.queryParameters['media_asset'] ?? '',
                          );
                          final preview = state.extra is ShareCard
                              ? state.extra as ShareCard
                              : null;
                          return CustomTransitionPage(
                            key: state.pageKey,
                            child: ContentDetailPage(
                              contentId: id,
                              initialColor: color,
                              preview: preview,
                              initialPlaybackSeconds: playbackSeconds,
                              initialMediaAssetId: mediaAssetId,
                            ),
                            transitionDuration: preview == null
                                ? AppMotion.routeTransition
                                : AppMotion.containerTransform,
                            reverseTransitionDuration: preview == null
                                ? AppMotion.routeTransition
                                : AppMotion.containerTransformBack,
                            transitionsBuilder:
                                (
                                  context,
                                  animation,
                                  secondaryAnimation,
                                  child,
                                ) {
                                  // 共享容器先展开，页面内容从动画后半段渐入；
                                  // 返回时页面先淡出，再由容器收拢回源卡片。
                                  final curved = CurvedAnimation(
                                    parent: animation,
                                    curve: preview == null
                                        ? AppMotion.standardCurve
                                        : const Interval(
                                            0.45,
                                            1,
                                            curve: AppMotion.standardCurve,
                                          ),
                                  );
                                  return FadeTransition(
                                    opacity: preview == null
                                        ? Tween<double>(
                                            begin: 0.96,
                                            end: 1,
                                          ).animate(curved)
                                        : curved,
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
                    path: '/automation',
                    builder: (context, state) => AutomationPage(
                      initialTab: state.uri.queryParameters['tab'],
                      highlightRunId: state.uri.queryParameters['run'],
                    ),
                  ),
                  GoRoute(
                    path: '/automation/sync',
                    builder: (context, state) => AutomationPage(
                      initialTab: 'sync',
                      highlightRunId: state.uri.queryParameters['run'],
                    ),
                  ),
                  GoRoute(
                    path: '/automation/distribution',
                    builder: (context, state) =>
                        const AutomationPage(initialTab: 'distribution'),
                  ),
                  GoRoute(
                    path: '/automation/distribution/history',
                    builder: (context, state) =>
                        const AutomationPage(initialTab: 'history'),
                  ),
                  GoRoute(
                    path: '/automation/distribution/rules/new',
                    builder: (context, state) => const DistributionRulePage(),
                  ),
                  GoRoute(
                    path: '/automation/distribution/rules/:ruleId',
                    builder: (context, state) => DistributionRulePage(
                      ruleId: int.parse(state.pathParameters['ruleId']!),
                    ),
                  ),
                  GoRoute(
                    path: '/automation/processing',
                    builder: (context, state) =>
                        const AutomationPage(initialTab: 'processing'),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
  ref.onDispose(() {
    router.dispose();
    listenable.dispose();
  });
  return router;
}

List<String> _queryList(GoRouterState state, String key) {
  final values = state.uri.queryParametersAll[key];
  if (values == null || values.isEmpty) return const [];
  return values
      .expand((value) => value.split(','))
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toList(growable: false);
}

DateTimeRange? _queryDateRange(GoRouterState state) {
  final from = DateTime.tryParse(state.uri.queryParameters['from'] ?? '');
  final to = DateTime.tryParse(state.uri.queryParameters['to'] ?? '');
  if (from == null || to == null || to.isBefore(from)) return null;
  return DateTimeRange(start: from, end: to);
}

class _PlaybackNavigationObserver extends NavigatorObserver {
  _PlaybackNavigationObserver(this.onNavigation);
  final Future<void> Function(Future<Object?>) onNavigation;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    unawaited(
      onNavigation(
        route is TransitionRoute ? route.completed : Future<void>.value(),
      ),
    );
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final animation = route is TransitionRoute ? route.animation : null;
    if (animation == null || animation.isCompleted) return;
    final settled = Completer<void>();
    void listener(AnimationStatus status) {
      if (status == AnimationStatus.completed ||
          status == AnimationStatus.dismissed) {
        animation.removeStatusListener(listener);
        settled.complete();
      }
    }

    animation.addStatusListener(listener);
    unawaited(onNavigation(settled.future));
  }
}
