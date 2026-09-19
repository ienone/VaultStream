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
import '../theme/design_tokens.dart';
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
  Size? _windowSize;

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
          final resized = _windowSize != constraints.biggest;
          _windowSize = constraints.biggest;
          final useRail = metrics.widthClass.atLeast(WindowWidthClass.medium);
          final mode = ref
              .watch(sidebarModeProvider)
              .forWidth(
                constraints.maxWidth /
                    (MediaQuery.textScalerOf(context).scale(16) / 16),
              );
          final sidebarVisible = mode != SidebarMode.hidden;
          final sidebarWidth = mode == SidebarMode.expanded
              ? NavigationSidebar.expandedWidth
              : NavigationSidebar.compactWidth;
          return SidebarScope(
            visible: sidebarVisible,
            openDrawer: () => _scaffoldKey.currentState!.openDrawer(),
            child: Scaffold(
              key: _scaffoldKey,
              drawer: Drawer(
                child: NavigationSidebar(
                  expanded: true,
                  selectedIndex: widget.navigationShell.currentIndex,
                  onDestinationSelected: _onDestinationSelected,
                  closeDrawer: () => _scaffoldKey.currentState!.closeDrawer(),
                ),
              ),
              body: Row(
                children: [
                  AnimatedContainer(
                    width: sidebarVisible ? sidebarWidth : 0,
                    duration: resized || MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : AppMotion.standard,
                    curve: AppMotion.standardCurve,
                    clipBehavior: Clip.hardEdge,
                    decoration: const BoxDecoration(),
                    child: OverflowBox(
                      alignment: Alignment.topLeft,
                      minWidth: sidebarWidth,
                      maxWidth: sidebarWidth,
                      child: ExcludeFocus(
                        excluding: !sidebarVisible,
                        child: ExcludeSemantics(
                          excluding: !sidebarVisible,
                          child: NavigationSidebar(
                            expanded: mode == SidebarMode.expanded,
                            selectedIndex: widget.navigationShell.currentIndex,
                            onDestinationSelected: _onDestinationSelected,
                          ),
                        ),
                      ),
                    ),
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
                            offstage:
                                MediaQuery.viewInsetsOf(context).bottom > 0,
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
            ),
          );
        },
      ),
    );
  }
}
