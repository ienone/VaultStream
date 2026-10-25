import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import 'responsive_layout.dart';
import 'workspace_geometry.dart';
import '../motion/shared_layout_transition.dart';
import '../../main.dart';
import '../../theme/design_tokens.dart';
import '../../routing/navigation_scope.dart';

/// 统一列表与详情的分栏、拖动、专注模式和跨断点状态。
class AppListDetailWorkspace extends StatefulWidget {
  const AppListDetailWorkspace({
    super.key,
    required this.list,
    required this.selectedId,
    required this.detailBuilder,
    this.onClose,
  });

  /// Primary list/detail panes need horizontal room; each pane scrolls in short windows.
  static bool supportsSplit(BuildContext context, {Size? availableSize}) {
    final size = availableSize ?? context.size ?? MediaQuery.sizeOf(context);
    final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
    return WindowMetrics.fromSize(Size(size.width / scale, size.height))
        .widthClass
        .supportsSupportingPane;
  }

  final Widget list;
  final Object? selectedId;
  final VoidCallback? onClose;
  final Widget Function(bool deferBody, bool focused, VoidCallback? toggleFocus)
  detailBuilder;

  @override
  State<AppListDetailWorkspace> createState() => _AppListDetailWorkspaceState();
}

class _AppListDetailWorkspaceState extends State<AppListDetailWorkspace>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final _back = AnimationController(
    vsync: this,
    duration: AppMotion.surfaceExit,
  )..addListener(_widthChanged);
  ModalRoute<dynamic>? _ownerRoute;
  ModalRoute<dynamic>? _detailRoute;
  LocalHistoryEntry? _history;
  bool _removingHistory = false;
  bool _previewingBack = false;
  double _backStart = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ownerRoute = ModalRoute.of(context);
    _detailRoute ??= _ownerRoute;
    _syncHistory();
  }

  void _syncHistory() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.selectedId != null && widget.onClose != null) {
        if (_history != null || _ownerRoute == null) return;
        _history = LocalHistoryEntry(
          impliesAppBarDismissal: false,
          onRemove: () {
            _history = null;
            if (!_removingHistory && mounted) widget.onClose?.call();
          },
        );
        _ownerRoute!.addLocalHistoryEntry(_history!);
      } else {
        _removeHistory();
      }
    });
  }

  void _removeHistory() {
    _removingHistory = true;
    _history?.remove();
    _history = null;
    _removingHistory = false;
  }

  void _registerDetailRoute(ModalRoute<dynamic>? route) {
    if (route != null &&
        (route.navigator != _ownerRoute?.navigator || _detailRoute == null)) {
      _detailRoute = route;
    }
  }

  @override
  bool handleStartBackGesture(PredictiveBackEvent backEvent) {
    final route = _detailRoute;
    if (backEvent.isButtonEvent ||
        widget.selectedId == null ||
        widget.onClose == null ||
        route == null ||
        !route.isCurrent ||
        route.popDisposition == RoutePopDisposition.doNotPop ||
        !AppNavigationScope.isActiveOf(context) ||
        !TickerMode.valuesOf(context).enabled ||
        MediaQuery.disableAnimationsOf(context)) {
      return false;
    }
    _back.stop();
    _backStart = _back.value;
    _previewingBack = true;
    _back.value = _backStart + (1 - _backStart) * backEvent.progress;
    return true;
  }

  @override
  void handleUpdateBackGestureProgress(PredictiveBackEvent backEvent) {
    if (_previewingBack) {
      _back.value = _backStart + (1 - _backStart) * backEvent.progress;
    }
  }

  @override
  void handleCancelBackGesture() async {
    await _back.animateBack(0, curve: AppMotion.standardCurve);
    if (mounted && _back.value == 0) {
      setState(() => _previewingBack = false);
    }
  }

  @override
  void handleCommitBackGesture() async {
    final route = _detailRoute;
    if (route?.isCurrent == true) await route!.navigator!.maybePop();
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    if (widget.selectedId != null) {
      handleCancelBackGesture();
    } else {
      setState(() => _previewingBack = false);
      _back.value = 0;
    }
  }

  static const _widthKey = 'collection_list_width';
  final _resizeFocus = FocusNode(debugLabel: 'workspace-pane-resize');
  static final _sharedWidth = ValueNotifier<double>(
    isSharedPrefsInitialized
        ? sharedPrefs.getDouble(_widthKey) ?? AppPane.supportingWidth
        : AppPane.supportingWidth,
  );
  double get _listWidth => _sharedWidth.value;
  set _listWidth(double value) => _sharedWidth.value = value;

  @override
  void initState() {
    super.initState();
    _sharedWidth.addListener(_widthChanged);
    WidgetsBinding.instance.addObserver(this);
  }

  void _widthChanged() => setState(() {});
  bool _focused = false;
  bool _dragging = false;
  bool _resizeHovered = false;
  bool _resizeFocused = false;
  late double _dragOrigin;
  late double _dragStartWidth;
  Size? _paneSize;
  late Object? _readerId = widget.selectedId;
  late var _detailBuilder = widget.detailBuilder;
  (Object?, Object, bool, bool, bool)? _readerConfiguration;
  late bool _readerReady = widget.selectedId != null;
  Widget _reader = const SizedBox.shrink();

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _removeHistory();
    _back.dispose();
    _sharedWidth.removeListener(_widthChanged);
    _resizeFocus.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(AppListDetailWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedId != widget.selectedId) {
      _detailRoute = _ownerRoute;
      _syncHistory();
    }
    if (widget.selectedId == null) {
      _focused = false;
    } else {
      if (oldWidget.selectedId == null && widget.selectedId != _readerId) {
        _readerReady = false;
      }
      _readerId = widget.selectedId;
      _detailBuilder = widget.detailBuilder;
    }
  }

  void _saveWidth() {
    if (isSharedPrefsInitialized) sharedPrefs.setDouble(_widthKey, _listWidth);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final resized = _paneSize != constraints.biggest;
      _paneSize = constraints.biggest;
      final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
      final wide = WindowMetrics.fromSize(
        Size(constraints.maxWidth / scale, constraints.maxHeight),
      ).widthClass.supportsSupportingPane;
      final listVisible = widget.selectedId == null || (wide && !_focused);
      final readerVisible = widget.selectedId != null;
      final maxListWidth = math.max(
        280.0,
        math.min(480.0, constraints.maxWidth - 492),
      );
      final listWidth = wide && readerVisible
          ? _listWidth.clamp(280.0, maxListWidth)
          : constraints.maxWidth;
      final readerWidth = wide && !_focused
          ? constraints.maxWidth - _listWidth.clamp(280.0, maxListWidth)
          : constraints.maxWidth;
      final animate =
          !resized && !_dragging && !MediaQuery.disableAnimationsOf(context);

      void resize(double width) {
        setState(() => _listWidth = width.clamp(280.0, maxListWidth));
      }

      void step(double delta) {
        resize(_listWidth.clamp(280.0, maxListWidth) + delta);
        _saveWidth();
      }

      if (!animate) _readerReady = true;
      final readerReady = _readerReady;
      final readerConfiguration = (
        _readerId,
        _detailBuilder,
        _focused,
        wide,
        readerReady,
      );
      if (_readerConfiguration != readerConfiguration) {
        _readerConfiguration = readerConfiguration;
        _reader = _readerId == null
            ? const SizedBox.shrink()
            : _detailBuilder(
                !readerReady,
                _focused,
                wide ? () => setState(() => _focused = !_focused) : null,
              );
      }

      final paneWidth = listVisible ? listWidth : 0.0;
      return _WorkspaceBackScope(
        register: _registerDetailRoute,
        child: SharedLayoutTransition(
          value: readerVisible && _previewingBack
              ? paneWidth + (constraints.maxWidth - paneWidth) * _back.value
              : paneWidth,
          animate: animate && (!_previewingBack || !readerVisible),
          onEnd: () {
            if (widget.selectedId != null && !_readerReady) {
              setState(() => _readerReady = true);
            }
          },
          builder: (context, paneWidth) => ColoredBox(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            child: Stack(
              children: [
                Row(
                  children: [
                    Container(
                      key: const ValueKey('collection-list-pane'),
                      width: paneWidth,
                      clipBehavior: Clip.hardEdge,
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerLow,
                      ),
                      child: ExcludeFocus(
                        excluding: !listVisible,
                        child: ExcludeSemantics(
                          excluding: !listVisible,
                          child: IgnorePointer(
                            ignoring: !listVisible,
                            child: LayoutBuilder(
                              builder: (context, pane) {
                                final width = math.max(
                                  wide ? 280.0 : listWidth,
                                  pane.maxWidth,
                                );
                                return OverflowBox(
                                  alignment: Alignment.topLeft,
                                  minWidth: width,
                                  maxWidth: width,
                                  child: WorkspaceGeometry(
                                    overviewWidth: constraints.maxWidth,
                                    listWidth: _listWidth.clamp(
                                      280.0,
                                      maxListWidth,
                                    ),
                                    progress: wide
                                        ? ((constraints.maxWidth - width) /
                                                  (constraints.maxWidth -
                                                      _listWidth.clamp(
                                                        280.0,
                                                        maxListWidth,
                                                      )))
                                              .clamp(0.0, 1.0)
                                        : 0,
                                    child: Theme(
                                      data: Theme.of(context).copyWith(
                                        scaffoldBackgroundColor: Theme.of(
                                          context,
                                        ).colorScheme.surfaceContainerLow,
                                        appBarTheme: Theme.of(context)
                                            .appBarTheme
                                            .copyWith(
                                              backgroundColor: Theme.of(context)
                                                  .colorScheme
                                                  .surfaceContainerLow,
                                            ),
                                      ),
                                      child: widget.list,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      key: const ValueKey('collection-reader-pane'),
                      child: ClipRRect(
                        borderRadius: wide && listVisible
                            ? const BorderRadius.horizontal(
                                left: Radius.circular(AppShape.pane),
                              )
                            : BorderRadius.zero,
                        child: OverflowBox(
                          alignment: Alignment.topLeft,
                          minWidth: readerWidth,
                          maxWidth: readerWidth,
                          child: TickerMode(
                            enabled: readerVisible,
                            child: ExcludeFocus(
                              excluding: !readerVisible,
                              child: ExcludeSemantics(
                                excluding: !readerVisible,
                                child: IgnorePointer(
                                  ignoring: !readerVisible,
                                  child: Semantics(
                                    container: true,
                                    child: RepaintBoundary(child: _reader),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (wide && readerVisible && listVisible)
                  Positioned(
                    left: paneWidth - 16,
                    top: 0,
                    bottom: 0,
                    width: 32,
                    child: Semantics(
                      label: '调整列表宽度',
                      value: '${listWidth.round()}',
                      increasedValue:
                          '${(listWidth + 16).clamp(280.0, maxListWidth).round()}',
                      decreasedValue:
                          '${(listWidth - 16).clamp(280.0, maxListWidth).round()}',
                      onIncrease: () => step(16),
                      onDecrease: () => step(-16),
                      child: CallbackShortcuts(
                        bindings: {
                          const SingleActivator(
                            LogicalKeyboardKey.arrowLeft,
                          ): () =>
                              step(-16),
                          const SingleActivator(
                            LogicalKeyboardKey.arrowRight,
                          ): () =>
                              step(16),
                          const SingleActivator(LogicalKeyboardKey.home): () {
                            resize(AppPane.supportingWidth);
                            _saveWidth();
                          },
                        },
                        child: Focus(
                          focusNode: _resizeFocus,
                          onFocusChange: (value) =>
                              setState(() => _resizeFocused = value),
                          child: MouseRegion(
                            onEnter: (_) =>
                                setState(() => _resizeHovered = true),
                            onExit: (_) =>
                                setState(() => _resizeHovered = false),
                            cursor: SystemMouseCursors.resizeColumn,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              dragStartBehavior: DragStartBehavior.down,
                              onTap: _resizeFocus.requestFocus,
                              onHorizontalDragStart: (event) {
                                _dragOrigin = event.globalPosition.dx;
                                _dragStartWidth = listWidth;
                                _resizeFocus.requestFocus();
                                setState(() => _dragging = true);
                              },
                              // 指针位置不依赖正在移动的拖柄，也不丢弃同帧事件。
                              onHorizontalDragUpdate: (event) => resize(
                                _dragStartWidth +
                                    event.globalPosition.dx -
                                    _dragOrigin,
                              ),
                              onHorizontalDragEnd: (_) {
                                setState(() => _dragging = false);
                                _saveWidth();
                              },
                              onHorizontalDragCancel: () =>
                                  setState(() => _dragging = false),
                              onDoubleTap: () {
                                resize(AppPane.supportingWidth);
                                _saveWidth();
                              },
                              child: SizedBox(
                                width: 32,
                                child: Center(
                                  child: Container(
                                    width: 3,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color:
                                          _dragging ||
                                              _resizeFocused ||
                                              _resizeHovered
                                          ? Theme.of(context)
                                                .colorScheme
                                                .primary
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _WorkspaceBackScope extends InheritedWidget {
  const _WorkspaceBackScope({required this.register, required super.child});
  final ValueChanged<ModalRoute<dynamic>?> register;
  @override
  bool updateShouldNotify(_WorkspaceBackScope oldWidget) => false;
}

/// Identifies the leaf route when a pane contains its own Navigator.
class WorkspaceBackTarget extends StatelessWidget {
  const WorkspaceBackTarget({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    context.dependOnInheritedWidgetOfExactType<_WorkspaceBackScope>()?.register(
      ModalRoute.of(context),
    );
    return child;
  }
}
