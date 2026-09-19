import 'dart:async';
import 'navigation_scope.dart';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:flutter/foundation.dart';

import '../features/collection/collection_page.dart';
import '../features/collection/content_detail_page.dart';
import '../features/collection/content_edit_page.dart';
import '../features/collection/providers/content_editor_key_provider.dart';
import '../features/collection/models/content.dart';
import '../features/dashboard/dashboard_page.dart';
import '../features/dashboard/task_result_page.dart';
import '../features/automation/automation_page.dart';
import '../features/automation/distribution_rule_page.dart';
import '../features/automation/providers/rule_editor_key_provider.dart';
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
import '../features/player/playback_route_observer.dart';
import '../features/auth/presentation/connect_page.dart';
import '../features/auth/presentation/onboarding_page.dart';
import '../layout/app_shell.dart';
import '../core/providers/local_settings_provider.dart';
import '../core/providers/system_status_provider.dart';

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
    if (previous?.apiToken.isNotEmpty == true &&
        next.apiToken.isEmpty &&
        ref.exists(globalPlaybackProvider)) {
      unawaited(ref.read(globalPlaybackProvider.notifier).close());
    }
    listenable.value++;
  });
  ref.listen(systemStatusProvider, (previous, next) {
    listenable.value++;
  });

  Future<bool> confirmRuleExit(
    BuildContext context,
    GoRouterState state,
  ) async {
    // Authentication loss must always remove private pages. Switching to another
    // stateful branch keeps this form mounted and does not discard its draft.
    if (ref.read(localSettingsProvider).apiToken.isEmpty) return true;
    final destination = GoRouter.of(
      context,
    ).routeInformationProvider.value.uri.path;
    if (destination == '/home' || destination == '/collection') return true;
    return await ref
            .read(ruleEditorKeyProvider(state.pageKey))
            .currentState
            ?.confirmExit() ??
        true;
  }

  final router = GoRouter(
    navigatorKey: _rootNavigatorKey,
    observers: [
      if (kIsWeb) ref.read(playbackRouteObserverProvider),
      _PlaybackNavigationObserver((settled) async {
        if (ref.read(localSettingsProvider).apiToken.isEmpty ||
            !ref.exists(globalPlaybackProvider)) {
          return;
        }
        await ref
            .read(globalPlaybackProvider.notifier)
            .preservePlaybackOnViewRemoval(settled);
      }),
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
      GoRoute(path: '/player', builder: (context, state) => const PlayerPage()),
      GoRoute(
        path: '/tasks/:runId',
        builder: (context, state) => GlobalPlaybackChrome(
          child: TaskResultPage(runId: state.pathParameters['runId']!),
        ),
      ),
      GoRoute(
        path: '/events/:id',
        builder: (context, state) => GlobalPlaybackChrome(
          child: EventDetailPage(
            eventId: int.parse(state.pathParameters['id']!),
          ),
        ),
      ),
      ShellRoute(
        builder: (context, state, child) {
          final location = state.uri.path;
          if (location == '/connect' || location == '/onboarding') {
            return AppNavigationScope(child: child);
          }
          final appShellOwnsMiniPlayer =
              location == '/home' ||
              location == '/collection' ||
              location.startsWith('/automation') ||
              location.startsWith('/collection/');
          return AppNavigationScope(
            child: GlobalPlaybackChrome(
              showMiniPlayer: !appShellOwnsMiniPlayer,
              child: child,
            ),
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
          StatefulShellRoute.indexedStack(
            // builder用于构建StatefulShellRoute的UI
            // context参数是用于构建Widget的BuildContext对象
            // state参数是GoRouterState对象，包含当前路由的状态信息
            // navigationShell参数是StatefulNavigationShell对象，表示当前的导航壳，可以用于管理子路由的导航状态
            // 返回一个AppShell Widget，传入navigationShell参数
            builder: (context, state, navigationShell) {
              return AppNavigationScope(
                child: AppShell(navigationShell: navigationShell),
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
                          final extra = state.extra;
                          final preview = extra is ShareCard && extra.id == id
                              ? extra
                              : null;
                          return MaterialPage<void>(
                            key: state.pageKey,
                            child: ContentDetailPage(
                              contentId: id,
                              initialColor: color,
                              preview: preview,
                              initialPlaybackSeconds: playbackSeconds,
                              initialMediaAssetId: mediaAssetId,
                            ),
                          );
                        },
                        routes: [
                          GoRoute(
                            path: 'edit',
                            parentNavigatorKey: _rootNavigatorKey,
                            builder: (context, state) => ContentEditPage(
                              key: ValueKey(state.pathParameters['id']),
                              contentId: int.parse(state.pathParameters['id']!),
                              routeKey: state.pageKey,
                            ),
                            onExit: (context, state) async {
                              if (ref
                                  .read(localSettingsProvider)
                                  .apiToken
                                  .isEmpty) {
                                return true;
                              }
                              return await ref
                                      .read(
                                        contentEditorKeyProvider((
                                          state.pageKey,
                                          int.parse(
                                            state.pathParameters['id']!,
                                          ),
                                        )),
                                      )
                                      .currentState
                                      ?.confirmExit() ??
                                  true;
                            },
                          ),
                        ],
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
                    routes: [
                      GoRoute(
                        path: 'sync',
                        builder: (context, state) => AutomationPage(
                          initialTab: 'sync',
                          highlightRunId: state.uri.queryParameters['run'],
                        ),
                      ),
                      GoRoute(
                        path: 'distribution',
                        builder: (context, state) => AutomationPage(
                          initialTab: 'distribution',
                          reviewItemId: int.tryParse(
                            state.uri.queryParameters['review_item'] ?? '',
                          ),
                        ),
                        routes: [
                          GoRoute(
                            path: 'history',
                            builder: (context, state) =>
                                const AutomationPage(initialTab: 'history'),
                          ),
                          GoRoute(
                            path: 'rules/new',
                            onExit: confirmRuleExit,
                            builder: (context, state) =>
                                DistributionRulePage(routeKey: state.pageKey),
                          ),
                          GoRoute(
                            path: 'rules/:ruleId',
                            onExit: confirmRuleExit,
                            builder: (context, state) => DistributionRulePage(
                              routeKey: state.pageKey,
                              ruleId: int.parse(
                                state.pathParameters['ruleId']!,
                              ),
                            ),
                          ),
                        ],
                      ),
                      GoRoute(
                        path: 'processing',
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
    if (route is PopupRoute) return;
    unawaited(
      onNavigation(
        route is TransitionRoute ? route.completed : Future<void>.value(),
      ),
    );
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute) return;
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
