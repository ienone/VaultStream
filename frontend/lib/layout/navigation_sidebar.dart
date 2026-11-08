import 'package:material_ui/material_ui.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/notifications/notification_provider.dart';
import '../core/providers/theme_provider.dart';
import '../core/widgets/app_choice_segments.dart';

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
  static const _destinations = [
    (0, '动态', Icons.dynamic_feed_outlined, Icons.dynamic_feed_rounded),
    (1, '收藏库', Icons.perm_media_outlined, Icons.perm_media_rounded),
    (2, '来源', Icons.rss_feed_rounded, Icons.rss_feed_rounded),
    (3, '推送', Icons.outbox_outlined, Icons.outbox_rounded),
  ];
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final unread = ref.watch(
      notificationInboxProvider(defaultNotificationQuery)
          .select((value) => value.value?.unreadCount ?? 0),
    );
    Widget icon(int index, IconData data) =>
        Badge(isLabelVisible: index == 4 && unread > 0, child: Icon(data));
    void select(int index) {
      closeDrawer?.call();
      onDestinationSelected(index);
    }

    if (closeDrawer != null) {
      final indexes = [
        if (selectedIndex >= 4) ...[0, 1, 2, 3],
        5,
        4,
        6,
      ];
      return NavigationDrawer(
        selectedIndex: indexes.contains(selectedIndex)
            ? indexes.indexOf(selectedIndex)
            : null,
        onDestinationSelected: (index) => select(indexes[index]),
        children: [
          const SizedBox(height: 16),
          if (selectedIndex >= 4) ...[
            for (final item in _destinations)
              NavigationDrawerDestination(
                icon: Icon(item.$3),
                selectedIcon: Icon(item.$4),
                label: Text(item.$2),
              ),
            const Divider(indent: 28, endIndent: 28),
          ],
          NavigationDrawerDestination(
            icon: const Icon(Icons.auto_awesome_outlined),
            selectedIcon: const Icon(Icons.auto_awesome_rounded),
            label: const Text('Agent'),
          ),
          NavigationDrawerDestination(
            icon: icon(4, Icons.notifications_none_rounded),
            selectedIcon: icon(4, Icons.notifications_rounded),
            label: const Text('消息'),
          ),
          const NavigationDrawerDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded),
            label: Text('设置'),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: AppChoiceSegments<ThemeMode>(
              options: const {
                ThemeMode.light: '浅色',
                ThemeMode.system: '自动',
                ThemeMode.dark: '深色',
              },
              selected: {ref.watch(themeModeProvider)},
              onChanged: (values) =>
                  ref.read(themeModeProvider.notifier).set(values.first),
            ),
          ),
        ],
      );
    }
    final active = _destinations.indexWhere((item) => item.$1 == selectedIndex);
    return NavigationRail(
      minWidth: compactWidth,
      backgroundColor: colors.surfaceContainerLowest,
      labelType: NavigationRailLabelType.selected,
      selectedIndex: active < 0 ? null : active,
      scrollable: true,
      groupAlignment: -1,
      trailingAtBottom: true,
      leading: const SizedBox(height: 16),
      destinations: [
        for (final item in _destinations)
          NavigationRailDestination(
            icon: icon(item.$1, item.$3),
            selectedIcon: icon(item.$1, item.$4),
            label: Text(item.$2),
          ),
      ],
      onDestinationSelected: (index) => select(_destinations[index].$1),
      trailing: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final tool in [
              (
                5,
                'Agent',
                Icons.auto_awesome_outlined,
                Icons.auto_awesome_rounded,
              ),
              (
                4,
                '消息',
                Icons.notifications_none_rounded,
                Icons.notifications_rounded,
              ),
            ]) ...[
              M3EIconButton(
                icon: icon(tool.$1, tool.$3),
                selectedIcon: icon(tool.$1, tool.$4),
                tooltip: tool.$2,
                isSelected: selectedIndex == tool.$1,
                variant: selectedIndex == tool.$1
                    ? M3EIconButtonVariant.tonal
                    : M3EIconButtonVariant.standard,
                onPressed: () => select(tool.$1),
              ),
              if (selectedIndex == tool.$1)
                Text(tool.$2, style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 12),
            ],
            M3EIconButton(
              icon: const Icon(Icons.settings_outlined),
              selectedIcon: const Icon(Icons.settings_rounded),
              tooltip: '设置',
              isSelected: selectedIndex == 6,
              variant: selectedIndex == 6
                  ? M3EIconButtonVariant.tonal
                  : M3EIconButtonVariant.standard,
              onPressed: () => select(6),
            ),
            if (selectedIndex == 6)
              Text('设置', style: Theme.of(context).textTheme.labelMedium),
          ],
        ),
      ),
    );
  }
}
