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
      body: Stack(
        children: [
          _AnimatedBranchContainer(
            currentIndex: navigationShell.currentIndex,
            child: navigationShell,
          ),
          const _TopToolOverlay(),
        ],
      ),
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
                icon: Icon(Icons.account_tree_outlined),
                selectedIcon: Icon(Icons.account_tree_rounded),
                label: Text('自动化'),
              ),
            ],
          ),
          VerticalDivider(
            thickness: 1,
            width: 1,
            color: Theme.of(
              context,
            ).colorScheme.outlineVariant.withValues(alpha: 0.2),
          ),
          Expanded(
            child: Stack(
              children: [
                _AnimatedBranchContainer(
                  currentIndex: navigationShell.currentIndex,
                  child: navigationShell,
                ),
                const _TopToolOverlay(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TopToolOverlay extends StatelessWidget {
  const _TopToolOverlay();

  @override
  Widget build(BuildContext context) {
    return PositionedDirectional(
      top: 8,
      end: 12,
      child: SafeArea(
        minimum: EdgeInsets.zero,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Tooltip(
              message: '通知中心',
              child: IconButton.filledTonal(
                onPressed: () => _showNotificationCenterPlaceholder(context),
                icon: Badge(
                  isLabelVisible: false,
                  child: const Icon(Icons.notifications_none_rounded),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: '设置',
              child: IconButton.filledTonal(
                onPressed: () => context.push('/settings'),
                icon: const Icon(Icons.settings_outlined),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void _showNotificationCenterPlaceholder(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.notifications_none_rounded,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Text(
                  '通知中心',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '后续这里会统一承载运行中任务、需要处理的问题和最近完成结果。当前阶段先作为 Root Shell 顶部工具入口预留。',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    ),
  );
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
