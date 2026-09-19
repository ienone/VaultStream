import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/layout/responsive_layout.dart';
import '../features/notifications/notification_provider.dart';
import '../main.dart';
import '../theme/design_tokens.dart';

enum SidebarMode {
  automatic('自动'),
  expanded('展开'),
  compact('仅图标'),
  hidden('隐藏');

  const SidebarMode(this.label);
  final String label;

  /// 窗口不足时只改变呈现，不覆盖用户保存的偏好。
  SidebarMode forWidth(double width) {
    if (width < ResponsiveLayout.mediumBreakpoint || this == hidden) {
      return hidden;
    }
    if (this == automatic) {
      return width >= ResponsiveLayout.largeBreakpoint ? expanded : compact;
    }
    if (this == expanded && width < ResponsiveLayout.expandedBreakpoint) {
      return compact;
    }
    return this;
  }
}

final sidebarModeProvider = NotifierProvider<SidebarPreference, SidebarMode>(
  SidebarPreference.new,
);

class SidebarPreference extends Notifier<SidebarMode> {
  static const _key = 'navigation_sidebar_mode';

  @override
  SidebarMode build() {
    final saved = isSharedPrefsInitialized ? sharedPrefs.getString(_key) : null;
    return SidebarMode.values.where((mode) => mode.name == saved).firstOrNull ??
        SidebarMode.automatic;
  }

  void set(SidebarMode mode) {
    state = mode;
    if (isSharedPrefsInitialized) sharedPrefs.setString(_key, mode.name);
  }
}

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
    required this.expanded,
    required this.selectedIndex,
    required this.onDestinationSelected,
    this.closeDrawer,
  });

  static const compactWidth = 72.0;
  static const expandedWidth = 224.0;

  final bool expanded;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final VoidCallback? closeDrawer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final mode = ref.watch(sidebarModeProvider);
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
    }) {
      final child = Badge(isLabelVisible: badge, child: Icon(icon, size: 22));
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        child: Tooltip(
          message: label,
          child: Material(
            color: selected
                ? theme.colorScheme.secondaryContainer
                : Colors.transparent,
            borderRadius: AppShape.cardBorder,
            child: InkWell(
              borderRadius: AppShape.cardBorder,
              onTap: () {
                closeDrawer?.call();
                onTap();
              },
              child: Semantics(
                selected: selected,
                button: true,
                label: expanded ? null : label,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 14,
                  ),
                  child: Row(
                    children: [
                      child,
                      if (expanded) ...[
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(label, style: theme.textTheme.labelLarge),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 12),
          children: [
            SizedBox(
              height: WindowMetrics.of(context).heightClass.isCompact
                  ? 48
                  : kToolbarHeight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    if (expanded)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(left: 12),
                          child: Text(
                            'VaultStream',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall,
                          ),
                        ),
                      ),
                    IconButton(
                      tooltip: closeDrawer != null
                          ? '关闭导航'
                          : expanded
                          ? '收起侧栏'
                          : '展开侧栏',
                      icon: Icon(
                        expanded ? Icons.menu_open_rounded : Icons.menu_rounded,
                      ),
                      onPressed:
                          closeDrawer ??
                          () => ref
                              .read(sidebarModeProvider.notifier)
                              .set(
                                expanded
                                    ? SidebarMode.compact
                                    : SidebarMode.expanded,
                              ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
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
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Divider(height: 1),
            ),
            destination(
              '全局搜索',
              Icons.search_rounded,
              () => context.push('/search'),
            ),
            destination(
              'Agent',
              Icons.auto_awesome_outlined,
              () => context.push('/agent'),
            ),
            destination(
              unread > 0 ? '消息 · $unread 未读' : '消息',
              Icons.notifications_none_rounded,
              () => context.push('/notifications'),
              badge: unread > 0,
            ),
            destination(
              '账号',
              Icons.manage_accounts_outlined,
              () => context.push('/accounts'),
            ),
            destination(
              '设置',
              Icons.settings_outlined,
              () => context.push('/settings'),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: PopupMenuButton<SidebarMode>(
                tooltip: '侧栏布局：${mode.label}',
                onSelected: (value) {
                  closeDrawer?.call();
                  ref.read(sidebarModeProvider.notifier).set(value);
                },
                itemBuilder: (_) => [
                  for (final value in SidebarMode.values)
                    CheckedPopupMenuItem(
                      value: value,
                      checked: value == mode,
                      child: Text(value.label),
                    ),
                ],
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(Icons.view_sidebar_outlined, size: 22),
                      if (expanded) ...[
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '侧栏 · ${mode.label}',
                            style: theme.textTheme.labelMedium,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
