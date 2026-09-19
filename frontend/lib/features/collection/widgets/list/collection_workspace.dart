import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/layout/responsive_layout.dart';
import '../../../../main.dart';
import '../../../../theme/design_tokens.dart';
import '../../content_detail_page.dart';
import '../../models/content.dart';

/// 先全宽浏览，选中后分栏；阅读模式内收折和拖动保留同一阅读器。
class CollectionWorkspace extends StatefulWidget {
  const CollectionWorkspace({
    super.key,
    required this.list,
    required this.selectedId,
    required this.onClose,
    this.preview,
  });

  final Widget list;
  final int? selectedId;
  final ShareCard? preview;
  final VoidCallback onClose;

  @override
  State<CollectionWorkspace> createState() => _CollectionWorkspaceState();
}

class _CollectionWorkspaceState extends State<CollectionWorkspace> {
  static const _widthKey = 'collection_list_width';
  final _resizeFocus = FocusNode(debugLabel: 'collection-pane-resize');
  late double _listWidth = isSharedPrefsInitialized
      ? sharedPrefs.getDouble(_widthKey) ?? 360
      : 360;
  bool _focused = false;
  bool _dragging = false;
  late double _dragOrigin;
  late double _dragStartWidth;
  Size? _paneSize;

  @override
  void dispose() {
    _resizeFocus.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(CollectionWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedId == null) _focused = false;
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
      ).supportsSupportingPane;
      final listVisible = widget.selectedId == null || (wide && !_focused);
      final readerVisible = widget.selectedId != null;
      final maxListWidth = math.max(
        280.0,
        math.min(480.0, constraints.maxWidth - 492),
      );
      final listWidth = wide && readerVisible
          ? _listWidth.clamp(280.0, maxListWidth)
          : constraints.maxWidth;
      final duration =
          resized || _dragging || MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : AppMotion.standard;

      void resize(double width) {
        setState(() => _listWidth = width.clamp(280.0, maxListWidth));
      }

      void step(double delta) {
        resize(_listWidth.clamp(280.0, maxListWidth) + delta);
        _saveWidth();
      }

      return HeroMode(
        enabled: false,
        child: Row(
          children: [
            AnimatedContainer(
              // 浏览与阅读是不同列表布局；只对阅读模式内的收折插值。
              key: ValueKey(
                readerVisible
                    ? 'collection-list-pane'
                    : 'collection-overview-pane',
              ),
              width: listVisible ? listWidth : 0,
              duration: duration,
              curve: AppMotion.standardCurve,
              clipBehavior: Clip.hardEdge,
              decoration: const BoxDecoration(),
              child: OverflowBox(
                alignment: Alignment.topLeft,
                minWidth: listWidth,
                maxWidth: listWidth,
                child: ExcludeFocus(
                  excluding: !listVisible,
                  child: ExcludeSemantics(
                    excluding: !listVisible,
                    child: IgnorePointer(
                      ignoring: !listVisible,
                      child: widget.list,
                    ),
                  ),
                ),
              ),
            ),
            if (wide && readerVisible && listVisible)
              Semantics(
                label: '调整收藏列表宽度',
                value: '${listWidth.round()}',
                increasedValue:
                    '${(listWidth + 16).clamp(280.0, maxListWidth).round()}',
                decreasedValue:
                    '${(listWidth - 16).clamp(280.0, maxListWidth).round()}',
                onIncrease: () => step(16),
                onDecrease: () => step(-16),
                child: CallbackShortcuts(
                  bindings: {
                    const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
                        step(-16),
                    const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
                        step(16),
                    const SingleActivator(LogicalKeyboardKey.home): () {
                      resize(360);
                      _saveWidth();
                    },
                  },
                  child: Focus(
                    focusNode: _resizeFocus,
                    child: MouseRegion(
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
                          resize(360);
                          _saveWidth();
                        },
                        child: SizedBox(
                          width: 12,
                          child: Center(
                            child: Container(
                              width: 3,
                              height: 40,
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.outlineVariant,
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
            Expanded(
              key: const ValueKey('collection-reader-pane'),
              child: ClipRect(
                child: Offstage(
                  offstage: !readerVisible,
                  child: widget.selectedId == null
                      ? const SizedBox.shrink()
                      : ContentDetailPage(
                          key: ValueKey(widget.selectedId),
                          contentId: widget.selectedId!,
                          preview: widget.preview,
                          onClose: widget.onClose,
                          focused: _focused,
                          onToggleFocus: wide
                              ? () => setState(() => _focused = !_focused)
                              : null,
                        ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}
