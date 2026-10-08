import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/notifications/notification_provider.dart';
import '../theme/design_tokens.dart';

/// 页头只需要知道导航是否可见以及如何打开，不接管 Shell 的路由状态。
class SidebarScope extends InheritedWidget {
  const SidebarScope({
    super.key,
    required this.visible,
    required this.openDrawer,
    required super.child,
  });

  final bool visible;
  final VoidCallback openDrawer;

  static SidebarScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SidebarScope>()!;

  @override
  bool updateShouldNotify(SidebarScope oldWidget) =>
      visible != oldWidget.visible;
}

class NavigationSidebar extends ConsumerWidget {
  const NavigationSidebar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    this.closeDrawer,
  });

  static const compactWidth = 88.0;

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final VoidCallback? closeDrawer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final unread = ref.watch(
      notificationInboxProvider(
        defaultNotificationQuery,
      ).select((value) => value.value?.unreadCount ?? 0),
    );

    Widget destination(
      String label,
      IconData icon,
      VoidCallback onTap, {
      bool selected = false,
      bool badge = false,
      String? tooltip,
    }) => AppNavigationDestination(
      label: label,
      icon: icon,
      selected: selected,
      badge: badge,
      tooltip: tooltip,
      onTap: () {
        closeDrawer?.call();
        onTap();
      },
    );

    final primary = [
      destination(
        '动态',
        Icons.dynamic_feed_outlined,
        () => onDestinationSelected(0),
        selected: selectedIndex == 0,
      ),
      destination(
        '收藏库',
        Icons.perm_media_outlined,
        () => onDestinationSelected(1),
        selected: selectedIndex == 1,
      ),
      destination(
        '自动化',
        Icons.account_tree_outlined,
        () => onDestinationSelected(2),
        selected: selectedIndex == 2,
      ),
    ];
    final tools = [
      destination(
        'Agent',
        Icons.auto_awesome_outlined,
        () => context.push('/agent'),
      ),
      destination(
        '消息',
        Icons.notifications_none_rounded,
        () => onDestinationSelected(3),
        selected: selectedIndex == 3,
        badge: unread > 0,
        tooltip: unread > 0 ? '消息 · $unread 未读' : '消息',
      ),
      destination(
        '账号',
        Icons.manage_accounts_outlined,
        () => context.push('/accounts'),
      ),
    ];

    return Material(
      color: theme.colorScheme.surfaceContainerLowest,
      child: SafeArea(
        child: Column(
          children: [
            if (closeDrawer != null)
              SizedBox(
                height: kToolbarHeight,
                child: IconButton(
                  tooltip: '关闭导航',
                  onPressed: closeDrawer,
                  icon: const Icon(Icons.close_rounded),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 24),
              child: SizedBox(
                width: 56,
                height: 56,
                child: IconButton.filledTonal(
                  tooltip: '全局搜索',
                  style: IconButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  onPressed: () {
                    closeDrawer?.call();
                    context.push('/search');
                  },
                  icon: const Icon(Icons.search_rounded),
                ),
              ),
            ),
            Expanded(
              child: CustomScrollView(
                slivers: [
                  SliverList.list(children: primary),
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: tools,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: destination(
                '设置',
                Icons.settings_outlined,
                () => context.push('/settings'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Rail and bottom navigation share the same icon indicator and short label.
class AppNavigationDestination extends StatelessWidget {
  const AppNavigationDestination({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.selected = false,
    this.badge = false,
    this.tooltip,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool selected;
  final bool badge;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final foreground = selected
        ? colors.onSecondaryContainer
        : colors.onSurfaceVariant;
    final indicator = AnimatedContainer(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : AppMotion.fast,
      curve: AppMotion.standardCurve,
      width: 56,
      height: 32,
      decoration: BoxDecoration(
        color: selected ? colors.secondaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Center(
        child: Badge(
          isLabelVisible: badge,
          child: Icon(icon, size: 24, color: foreground),
        ),
      ),
    );
    final text = Text(
      label,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: foreground,
        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
      ),
    );
    return Tooltip(
      message: tooltip ?? label,
      child: Semantics(
        selected: selected,
        button: true,
        label: tooltip ?? label,
        excludeSemantics: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [indicator, const SizedBox(height: 4), text],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
