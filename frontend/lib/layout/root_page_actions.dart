import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/collection/widgets/dialogs/add_content_dialog.dart';
import '../features/notifications/notification_center_page.dart';

/// 三个主页共用的操作区；主导航只负责切换目的地。
class RootPageActions extends StatelessWidget {
  const RootPageActions({super.key});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton(
        tooltip: '保存内容',
        onPressed: () => AddContentDialog.showAndNotify(context),
        icon: const Icon(Icons.add_rounded),
      ),
      PopupMenuButton<String>(
        tooltip: '工具与设置',
        icon: const NotificationCenterBadge(icon: Icons.apps_rounded),
        onSelected: (route) => context.push(route),
        itemBuilder: (_) => const [
          PopupMenuItem(
            value: '/search',
            child: ListTile(
              leading: Icon(Icons.search_rounded),
              title: Text('全局搜索'),
            ),
          ),
          PopupMenuItem(
            value: '/agent',
            child: ListTile(
              leading: Icon(Icons.auto_awesome_outlined),
              title: Text('Agent 工作台'),
            ),
          ),
          PopupMenuItem(
            value: '/notifications',
            child: ListTile(
              leading: NotificationCenterBadge(),
              title: Text('消息盒子'),
            ),
          ),
          PopupMenuDivider(),
          PopupMenuItem(
            value: '/accounts',
            child: ListTile(
              leading: Icon(Icons.manage_accounts_outlined),
              title: Text('账号中心'),
            ),
          ),
          PopupMenuItem(
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
