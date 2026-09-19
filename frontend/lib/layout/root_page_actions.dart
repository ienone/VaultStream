import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/collection/widgets/dialogs/add_content_dialog.dart';
import '../features/notifications/notification_provider.dart';
import 'navigation_sidebar.dart';

/// 导航入口与抽屉同处 leading 侧；常驻侧栏可见时不预留按钮槽位。
Widget? buildRootPageLeading(BuildContext context) {
  final sidebar = SidebarScope.of(context);
  if (sidebar.visible) return null;
  return Consumer(
    builder: (context, ref, _) {
      final unread = ref.watch(
        notificationInboxProvider(
          defaultNotificationQuery,
        ).select((value) => value.value?.unreadCount ?? 0),
      );
      return IconButton(
        tooltip: unread > 0 ? '打开导航，$unread 条未读消息' : '打开导航',
        onPressed: sidebar.openDrawer,
        icon: Badge(
          isLabelVisible: unread > 0,
          child: const Icon(Icons.menu_rounded),
        ),
      );
    },
  );
}

/// 保存属于页头动作区；工具统一归入导航。
class RootPageActions extends StatelessWidget {
  const RootPageActions({super.key});

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: '保存内容',
    onPressed: () => AddContentDialog.showAndNotify(context),
    icon: const Icon(Icons.add_rounded),
  );
}
