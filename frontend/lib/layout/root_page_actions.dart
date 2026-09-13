import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/layout/responsive_layout.dart';

import '../features/collection/widgets/dialogs/add_content_dialog.dart';
import '../features/notifications/notification_provider.dart';

/// 三个主页共用的操作区；主导航只负责切换目的地。
class RootPageActions extends ConsumerWidget {
  const RootPageActions({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unreadCount = ref.watch(
      notificationInboxProvider(
        defaultNotificationQuery,
      ).select((value) => value.value?.unreadCount ?? 0),
    );
    final unreadLabel = unreadCount > 0 ? '，$unreadCount 条未读消息' : '';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: '保存内容',
          onPressed: () => AddContentDialog.showAndNotify(context),
          icon: const Icon(Icons.add_rounded),
        ),
        if (!WindowMetrics.of(context).isCompact) ...[
          IconButton(
            tooltip: '全局搜索',
            onPressed: () => context.push('/search'),
            icon: const Icon(Icons.search_rounded),
          ),
          IconButton(
            tooltip: 'Agent 工作台',
            onPressed: () => context.push('/agent'),
            icon: const Icon(Icons.auto_awesome_outlined),
          ),
          IconButton(
            tooltip: '消息盒子$unreadLabel',
            onPressed: () => context.push('/notifications'),
            icon: Badge(
              isLabelVisible: unreadCount > 0,
              child: const Icon(Icons.notifications_none_rounded),
            ),
          ),
          IconButton(
            tooltip: '账号中心',
            onPressed: () => context.push('/accounts'),
            icon: const Icon(Icons.manage_accounts_outlined),
          ),
          IconButton(
            tooltip: '设置',
            onPressed: () => context.push('/settings'),
            icon: const Icon(Icons.settings_outlined),
          ),
        ] else
          PopupMenuButton<String>(
            tooltip: '工具与设置$unreadLabel',
            icon: Badge(
              isLabelVisible: unreadCount > 0,
              child: const Icon(Icons.apps_rounded),
            ),
            onSelected: (route) => context.push(route),
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: '/search',
                child: ListTile(
                  leading: Icon(Icons.search_rounded),
                  title: Text('全局搜索'),
                ),
              ),
              const PopupMenuItem(
                value: '/agent',
                child: ListTile(
                  leading: Icon(Icons.auto_awesome_outlined),
                  title: Text('Agent 工作台'),
                ),
              ),
              PopupMenuItem(
                value: '/notifications',
                child: Consumer(
                  builder: (context, ref, _) {
                    final count = ref.watch(
                      notificationInboxProvider(
                        defaultNotificationQuery,
                      ).select((value) => value.value?.unreadCount ?? 0),
                    );
                    return ListTile(
                      leading: const Icon(Icons.notifications_none_rounded),
                      title: const Text('消息盒子'),
                      titleAlignment: ListTileTitleAlignment.titleHeight,
                      subtitle: count > 0 ? Text('$count 条未读') : null,
                    );
                  },
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: '/accounts',
                child: ListTile(
                  leading: Icon(Icons.manage_accounts_outlined),
                  title: Text('账号中心'),
                ),
              ),
              const PopupMenuItem(
                value: '/settings',
                child: ListTile(
                  leading: Icon(Icons.settings_outlined),
                  title: Text('设置'),
                ),
              ),
            ],
          ),
      ],
    );
  }
}
