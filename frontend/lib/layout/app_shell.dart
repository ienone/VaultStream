import '../core/widgets/predictive_back_drawer.dart';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_selector/file_selector.dart';
import 'package:go_router/go_router.dart';

import '../core/layout/responsive_layout.dart';
import '../features/share_receiver/share_receiver_service.dart';
import '../features/player/global_player_widgets.dart';
import '../features/collection/models/capture_draft.dart';
import '../features/collection/widgets/dialogs/add_content_dialog.dart';
import '../core/utils/toast.dart';
import '../routing/navigation_scope.dart';
import 'navigation_sidebar.dart';

class AppShell extends ConsumerStatefulWidget {
  final StatefulNavigationShell navigationShell;

  const AppShell({required this.navigationShell, super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  bool _isShowingSheet = false;
  bool _drawerOpen = false;
  final _scaffoldKey = GlobalKey<ScaffoldState>();

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
          final useRail =
              constraints.maxWidth /
                  (MediaQuery.textScalerOf(context).scale(16) / 16) >=
              ResponsiveLayout.mediumBreakpoint;
          return SidebarScope(
            visible: useRail,
            openDrawer: () => _scaffoldKey.currentState!.openDrawer(),
            child: Scaffold(
              key: _scaffoldKey,
              onDrawerChanged: (open) => setState(() => _drawerOpen = open),
              backgroundColor: Theme.of(context)
                  .colorScheme
                  .surfaceContainerLowest,
              drawer: useRail
                  ? null
                  : PredictiveBackDrawer(
                      isOpen: () =>
                          _scaffoldKey.currentState?.isDrawerOpen ?? false,
                      close: () => _scaffoldKey.currentState!.closeDrawer(),
                      child: Drawer(
                        width: 280,
                        child: NavigationSidebar(
                          selectedIndex: widget.navigationShell.currentIndex,
                          onDestinationSelected: _onDestinationSelected,
                          closeDrawer: () =>
                              _scaffoldKey.currentState!.closeDrawer(),
                        ),
                      ),
                    ),
              body: Row(
                children: [
                  if (useRail)
                    SafeArea(
                      top: false,
                      bottom: false,
                      right: false,
                      child: SizedBox(
                        width: NavigationSidebar.compactWidth,
                        child: NavigationSidebar(
                          selectedIndex: widget.navigationShell.currentIndex,
                          onDestinationSelected: _onDestinationSelected,
                        ),
                      ),
                    ),
                  Expanded(
                    key: const ValueKey('root-content'),
                    child: ClipRRect(
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(useRail ? 28 : 0),
                        bottomLeft: Radius.circular(useRail ? 28 : 0),
                      ),
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
                                child: AppNavigationScope(
                                  active: !_drawerOpen,
                                  child: widget.navigationShell,
                                ),
                              ),
                            ),
                            Offstage(
                              offstage:
                                  MediaQuery.viewInsetsOf(context).bottom > 0,
                              child: const GlobalMiniPlayer(),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              bottomNavigationBar:
                  useRail || MediaQuery.viewInsetsOf(context).bottom > 0
                  ? null
                  : NavigationBar(
                      selectedIndex: widget.navigationShell.currentIndex.clamp(
                        0,
                        4,
                      ),
                      labelBehavior:
                          NavigationDestinationLabelBehavior.onlyShowSelected,
                      onDestinationSelected: (index) => index == 4
                          ? _scaffoldKey.currentState!.openDrawer()
                          : _onDestinationSelected(index),
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
                          icon: Icon(Icons.rss_feed_rounded),
                          label: '来源',
                        ),
                        NavigationDestination(
                          icon: Icon(Icons.outbox_outlined),
                          selectedIcon: Icon(Icons.outbox_rounded),
                          label: '推送',
                        ),
                        NavigationDestination(
                          icon: Icon(Icons.menu_rounded),
                          label: '更多',
                        ),
                      ],
                    ),
            ),
          );
        },
      ),
    );
  }
}
