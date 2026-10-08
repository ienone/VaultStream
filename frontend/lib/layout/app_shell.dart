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
import 'navigation_sidebar.dart';

class AppShell extends ConsumerStatefulWidget {
  final StatefulNavigationShell navigationShell;

  const AppShell({required this.navigationShell, super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  bool _isShowingSheet = false;
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
              backgroundColor: Theme.of(
                context,
              ).colorScheme.surfaceContainerLowest,
              drawer: useRail
                  ? null
                  : Drawer(
                      width: NavigationSidebar.compactWidth,
                      child: NavigationSidebar(
                        selectedIndex: widget.navigationShell.currentIndex,
                        onDestinationSelected: _onDestinationSelected,
                        closeDrawer: () =>
                            _scaffoldKey.currentState!.closeDrawer(),
                      ),
                    ),
              body: Row(
                children: [
                  if (useRail)
                    SizedBox(
                      width: NavigationSidebar.compactWidth,
                      child: NavigationSidebar(
                        selectedIndex: widget.navigationShell.currentIndex,
                        onDestinationSelected: _onDestinationSelected,
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
                                child: widget.navigationShell,
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
                  : SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            for (final entry in const [
                              ('动态', Icons.dynamic_feed_outlined),
                              ('收藏库', Icons.perm_media_outlined),
                              ('自动化', Icons.account_tree_outlined),
                            ].indexed)
                              Expanded(
                                child: AppNavigationDestination(
                                  label: entry.$2.$1,
                                  icon: entry.$2.$2,
                                  selected:
                                      widget.navigationShell.currentIndex ==
                                      entry.$1,
                                  onTap: () => _onDestinationSelected(entry.$1),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
            ),
          );
        },
      ),
    );
  }
}
