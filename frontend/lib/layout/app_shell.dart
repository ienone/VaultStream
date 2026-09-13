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

  const AppShell({required this.navigationShell, super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  bool _isShowingSheet = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // A share can arrive before the connection flow mounts the main shell.
      final pending = ref.read(shareReceiverStateProvider);
      if (pending != null && !pending.isEmpty) {
        _showShareSheet(pending);
      }
    });
  }

  void _onDestinationSelected(int index) {
    final currentIndex = widget.navigationShell.currentIndex;
    if (index != currentIndex) {
      widget.navigationShell.goBranch(index);
      return;
    }
    final navigator =
        widget.navigationShell.route.branches[index].navigatorKey.currentState;
    if (navigator == null) return;
    var blocked = false;
    navigator.popUntil((route) {
      if (route.isFirst) return true;
      blocked = route.popDisposition == RoutePopDisposition.doNotPop;
      return blocked;
    });
    // Stop at an unsaved form or an operation in progress. Its own back
    // handler decides whether to stay or discard and return to its parent.
    if (blocked) navigator.maybePop();
  }

  Future<void> _showShareSheet(SharedContent content) async {
    if (_isShowingSheet) return;
    setState(() => _isShowingSheet = true);
    final shareService = ref.read(shareReceiverServiceProvider);

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
      if (mounted) {
        setState(() => _isShowingSheet = false);
      }
      shareService.completeSharedContent(content);
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
        if (didPop) return;
        if (widget.navigationShell.currentIndex != 0) {
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
                        Expanded(
                          // Route barriers belong to the content pane. Without
                          // this boundary they also hide the preceding rail
                          // from the accessibility tree.
                          child: Semantics(
                            container: true,
                            child: widget.navigationShell,
                          ),
                        ),
                        Offstage(
                          offstage: MediaQuery.viewInsetsOf(context).bottom > 0,
                          child: const GlobalMiniPlayer(),
                        ),
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
