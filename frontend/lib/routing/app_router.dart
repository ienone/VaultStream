import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart'; // 引入go_router库，用于路由管理
import 'package:riverpod_annotation/riverpod_annotation.dart'; // 引入riverpod_annotation库，用于Riverpod状态管理的注解支持

// 引入自行构建的各个页面和布局组件
import '../features/collection/collection_page.dart';
import '../features/collection/content_detail_page.dart';
import '../features/dashboard/dashboard_page.dart';
import '../features/review/review_page.dart';
import '../features/settings/settings_page.dart';
import '../layout/app_shell.dart';

part 'app_router.g.dart'; // 生成的代码文件，源于Riverpod的代码生成
// riverpod_annotation库使用代码生成来简化provider的创建和管理

final _rootNavigatorKey = GlobalKey<NavigatorState>(); // 定义一个全局的导航键，用于管理应用的导航状态

@riverpod // 使用@riverpod注解定义一个Riverpod provider
// goRouterProvider是一个GoRouter类型的provider，负责提供应用的路由配置
// GoRouter是go_router库中的一个类，用于管理应用的路由和导航
// Ref类型的ref参数用于访问和监听其他providers，用于在运行过程中获取依赖的状态或数据
GoRouter goRouter(Ref ref) {
  //返回的GoRouter对象定义了应用的路由结构
  return GoRouter(
    navigatorKey: _rootNavigatorKey, // 设置导航键
    initialLocation: '/dashboard', // 设置初始路由位置为/dashboard(仪表盘页面)
    routes: [
      // 定义应用的路由列表
      // 使用StatefulShellRoute.indexedStack定义一个带有底部导航栏的路由结构
      // IndexedStack是一种布局方式，可以在多个子页面之间切换，同时保持它们的状态
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
                        reverseTransitionDuration: const Duration(milliseconds: 400),
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
