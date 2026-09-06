import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_selector/file_selector.dart';
import 'package:go_router/go_router.dart';

import '../core/layout/responsive_layout.dart';
import '../features/share_receiver/share_receiver_service.dart';
import '../features/player/global_player_widgets.dart';
import '../features/collection/models/capture_draft.dart';
import '../features/collection/widgets/dialogs/add_content_dialog.dart';
import '../core/utils/toast.dart';

class AppShell extends ConsumerStatefulWidget {
  final StatefulNavigationShell navigationShell;
  final String currentLocation;

  const AppShell({
    required this.navigationShell,
    required this.currentLocation,
    super.key,
  });

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  bool _isShowingSheet = false;

  void _onDestinationSelected(int index) {
    final currentIndex = widget.navigationShell.currentIndex;
    widget.navigationShell.goBranch(
      index,
      initialLocation: index == currentIndex,
    );
  }

  Future<void> _showShareSheet(SharedContent content) async {
    if (_isShowingSheet) return;
    setState(() => _isShowingSheet = true);

    try {
      final sharedText = (content.text ?? '').trim();
      final sharedUrl = content.extractedUrl;
      final files = content.mediaFiles
          .map((file) => XFile(file.path, mimeType: file.mimeType))
          .toList(growable: false);
      final result = await AddContentDialog.show(
        context,
        draft: CaptureDraft(
          url: sharedUrl,
          text: sharedText,
          files: files,
          note:
              files.isNotEmpty || (sharedUrl != null && sharedText != sharedUrl)
              ? sharedText
              : null,
          source: 'system_share',
          receivedAt: content.receivedAt,
        ),
      );
      if (result != null && mounted) {
        Toast.show(
          context,
          result.message,
          icon: result.needsAttention
              ? Icons.warning_amber_rounded
              : Icons.check_circle_outline_rounded,
        );
      }
    } finally {
      ref.read(shareReceiverServiceProvider).clearSharedContent();
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

    final isAutomationDetail =
        widget.navigationShell.currentIndex == 2 &&
        widget.currentLocation != '/automation';
    final automationBackLocation =
        widget.currentLocation.startsWith('/automation/distribution/rules/')
        ? '/automation/distribution'
        : '/automation';

    return PopScope(
      canPop: widget.navigationShell.currentIndex == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (isAutomationDetail) {
          context.go(automationBackLocation);
        } else if (widget.navigationShell.currentIndex != 0) {
          widget.navigationShell.goBranch(0);
        }
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final metrics = WindowMetrics.fromSize(constraints.biggest);
          final useRail = metrics.widthClass.atLeast(WindowWidthClass.medium);
          return Scaffold(
            body: Row(
              children: [
                if (useRail)
                  NavigationRail(
                    scrollable: true,
                    minWidth: 80,
                    selectedIndex: widget.navigationShell.currentIndex,
                    onDestinationSelected: _onDestinationSelected,
                    labelType: metrics.heightClass.isCompact
                        ? NavigationRailLabelType.none
                        : NavigationRailLabelType.all,
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
                Expanded(
                  key: const ValueKey('root-content'),
                  child: SafeArea(
                    top: false,
                    bottom: useRail,
                    left: !useRail,
                    child: Column(
                      children: [
                        Expanded(child: widget.navigationShell),
                        const GlobalMiniPlayer(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            bottomNavigationBar:
                useRail || MediaQuery.viewInsetsOf(context).bottom > 0
                ? null
                : NavigationBar(
                    selectedIndex: widget.navigationShell.currentIndex,
                    onDestinationSelected: _onDestinationSelected,
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
        },
      ),
    );
  }
}
