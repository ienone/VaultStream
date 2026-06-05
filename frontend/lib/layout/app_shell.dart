import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../core/layout/responsive_layout.dart';
import '../features/collection/providers/collection_filter_provider.dart';
import '../features/share_receiver/share_receiver_service.dart';
import '../features/share_receiver/share_submit_sheet.dart';
import '../core/utils/toast.dart';

class AppShell extends ConsumerStatefulWidget {
  final StatefulNavigationShell navigationShell;

  const AppShell({required this.navigationShell, super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  bool _isShowingSheet = false;

  @override
  void initState() {
    super.initState();
    // 分享监听已在 VaultStreamApp 中初始化
  }

  void _onDestinationSelected(int index) {
    final currentIndex = widget.navigationShell.currentIndex;
    if (currentIndex == 1 || index == 1) {
      ref.read(collectionFilterProvider.notifier).clearFilters();
    }

    widget.navigationShell.goBranch(
      index,
      initialLocation: index == currentIndex,
    );
  }

  Future<void> _showShareSheet(SharedContent content) async {
    if (_isShowingSheet) return;
    setState(() => _isShowingSheet = true);

    try {
      await ShareSubmitSheet.show(
        context,
        content,
        onSubmitted: () {
          Toast.show(context, '已保存到收藏库');
        },
      );
    } finally {
      if (mounted) {
        setState(() => _isShowingSheet = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 监听分享内容变化
    ref.listen<SharedContent?>(shareReceiverStateProvider, (previous, next) {
      if (next != null && !next.isEmpty && !_isShowingSheet) {
        _showShareSheet(next);
      }
    });

    return PopScope(
      canPop: widget.navigationShell.currentIndex == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && widget.navigationShell.currentIndex != 0) {
          widget.navigationShell.goBranch(0);
        }
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < ResponsiveLayout.mobileBreakpoint) {
            return _MobileShell(
              navigationShell: widget.navigationShell,
              onDestinationSelected: _onDestinationSelected,
            );
          } else {
            return _DesktopShell(
              navigationShell: widget.navigationShell,
              onDestinationSelected: _onDestinationSelected,
            );
          }
        },
      ),
    );
  }
}

class _MobileShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;
  final ValueChanged<int> onDestinationSelected;

  const _MobileShell({
    required this.navigationShell,
    required this.onDestinationSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _AnimatedBranchContainer(
        currentIndex: navigationShell.currentIndex,
        child: navigationShell,
      ),
      floatingActionButton: navigationShell.currentIndex == 0
          ? FloatingActionButton.small(
              tooltip: '辅助入口',
              onPressed: () => _showUtilityMenu(context),
              child: const Icon(Icons.more_horiz_rounded),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: onDestinationSelected,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dynamic_feed_outlined),
            selectedIcon: Icon(Icons.dynamic_feed_rounded),
            label: '动态',
          ),
          NavigationDestination(
            icon: Icon(Icons.perm_media_outlined),
            selectedIcon: Icon(Icons.perm_media_rounded),
            label: '收藏库',
          ),
          NavigationDestination(
            icon: Icon(Icons.inbox_outlined),
            selectedIcon: Icon(Icons.inbox_rounded),
            label: '收件箱',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_tree_outlined),
            selectedIcon: Icon(Icons.account_tree_rounded),
            label: '自动化',
          ),
        ],
      ),
    );
  }
}

class _DesktopShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;
  final ValueChanged<int> onDestinationSelected;

  const _DesktopShell({
    required this.navigationShell,
    required this.onDestinationSelected,
  });

  @override
  Widget build(BuildContext context) {
    final extended =
        MediaQuery.of(context).size.width >= ResponsiveLayout.desktopBreakpoint;

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: navigationShell.currentIndex,
            onDestinationSelected: onDestinationSelected,
            extended: extended,
            minWidth: 80,
            minExtendedWidth: 200,
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: AnimatedContainer(
                duration: 300.ms,
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.vape_free_rounded, // Replace with your logo icon
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
            ),
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.dynamic_feed_outlined),
                selectedIcon: Icon(Icons.dynamic_feed_rounded),
                label: Text('动态'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.perm_media_outlined),
                selectedIcon: Icon(Icons.perm_media_rounded),
                label: Text('收藏库'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.inbox_outlined),
                selectedIcon: Icon(Icons.inbox_rounded),
                label: Text('收件箱'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.account_tree_outlined),
                selectedIcon: Icon(Icons.account_tree_rounded),
                label: Text('自动化'),
              ),
            ],
            trailing: Padding(
              padding: const EdgeInsets.only(top: 24),
              child: _UtilityRailActions(extended: extended),
            ),
          ),
          VerticalDivider(
            thickness: 1,
            width: 1,
            color: Theme.of(
              context,
            ).colorScheme.outlineVariant.withValues(alpha: 0.2),
          ),
          Expanded(
            child: _AnimatedBranchContainer(
              currentIndex: navigationShell.currentIndex,
              child: navigationShell,
            ),
          ),
        ],
      ),
    );
  }
}

void _showUtilityMenu(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _UtilityMenuTile(
            icon: Icons.smart_toy_outlined,
            label: 'Agent 工作台',
            onTap: () {
              Navigator.of(sheetContext).pop();
              context.push('/agent');
            },
          ),
          _UtilityMenuTile(
            icon: Icons.manage_accounts_outlined,
            label: '账号中心',
            onTap: () {
              Navigator.of(sheetContext).pop();
              context.push('/accounts');
            },
          ),
          _UtilityMenuTile(
            icon: Icons.settings_outlined,
            label: '系统设置',
            onTap: () {
              Navigator.of(sheetContext).pop();
              context.push('/settings');
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

class _UtilityMenuTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _UtilityMenuTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(leading: Icon(icon), title: Text(label), onTap: onTap);
  }
}

class _UtilityRailActions extends StatelessWidget {
  final bool extended;

  const _UtilityRailActions({required this.extended});

  @override
  Widget build(BuildContext context) {
    final actions = [
      _UtilityAction(
        icon: Icons.smart_toy_outlined,
        label: 'Agent',
        route: '/agent',
      ),
      _UtilityAction(
        icon: Icons.manage_accounts_outlined,
        label: '账号',
        route: '/accounts',
      ),
      _UtilityAction(
        icon: Icons.settings_outlined,
        label: '设置',
        route: '/settings',
      ),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final action in actions)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Tooltip(
              message: action.label,
              child: extended
                  ? TextButton.icon(
                      onPressed: () => context.push(action.route),
                      icon: Icon(action.icon, size: 18),
                      label: Text(action.label),
                    )
                  : IconButton(
                      onPressed: () => context.push(action.route),
                      icon: Icon(action.icon),
                    ),
            ),
          ),
      ],
    );
  }
}

class _UtilityAction {
  final IconData icon;
  final String label;
  final String route;

  const _UtilityAction({
    required this.icon,
    required this.label,
    required this.route,
  });
}

/// A wrapper that animates transitions between navigation branches.
class _AnimatedBranchContainer extends StatelessWidget {
  final int currentIndex;
  final Widget child;

  const _AnimatedBranchContainer({
    required this.currentIndex,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: 400.ms,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.02, 0), // Subtle horizontal slide
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      child: KeyedSubtree(key: ValueKey<int>(currentIndex), child: child),
    );
  }
}
