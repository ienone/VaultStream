import '../../../../core/layout/workspace_geometry.dart';

import 'package:flutter/rendering.dart' show ScrollCacheExtent;

import 'collection_grid_layout.dart';

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../theme/design_tokens.dart';
import '../../models/content.dart';
import 'content_card.dart';

/// 浏览时按行组织卡片，阅读时显示单列；共用数据、分页和选择动作。
class CollectionList extends StatefulWidget {
  const CollectionList({
    super.key,
    required this.items,
    required this.scrollController,
    required this.isLoadingMore,
    required this.onRefresh,
    required this.onOpenContent,
    required this.emptyState,
    this.activeId,
    this.onDeleted,
    this.isSelectionMode = false,
    this.selectedIds = const {},
    this.onToggleSelection,
    this.onLongPress,
    this.onLoadMore,
    this.onSelectionChanged,
    this.selectionEnabled = true,
  });

  final List<ShareCard> items;
  final ScrollController scrollController;
  final bool isLoadingMore;
  final RefreshCallback onRefresh;
  final void Function(ShareCard, BuildContext) onOpenContent;
  final int? activeId;
  final ValueChanged<int>? onDeleted;
  final bool isSelectionMode;
  final Set<int> selectedIds;
  final ValueChanged<int>? onToggleSelection;
  final ValueChanged<int>? onLongPress;
  final VoidCallback? onLoadMore;
  final Widget emptyState;
  final ValueChanged<Set<int>>? onSelectionChanged;
  final bool selectionEnabled;

  @override
  State<CollectionList> createState() => _CollectionListState();
}

class _CollectionListState extends State<CollectionList> {
  final _viewport = GlobalKey();
  final _geometry = CollectionGridScrollGeometry();
  final _cards = <int, Widget>{};
  final _keys = <int, GlobalKey>{};
  Offset? _down, _position;
  int? _anchor;
  Set<int> _before = {};
  bool _adding = true, _mouseDown = false, _dragging = false;
  Timer? _edgeTimer;

  int? _hit(Offset point) {
    for (var i = 0; i < widget.items.length; i++) {
      final box = _keys[widget.items[i].id]?.currentContext?.findRenderObject();
      if (box is RenderBox &&
          box.attached &&
          box.hasSize &&
          (box.localToGlobal(Offset.zero) & box.size).contains(point)) {
        return i;
      }
    }
    return null;
  }

  void _start(Offset point) {
    if (!widget.selectionEnabled) return;
    final index = _hit(point);
    if (index == null) return;
    _anchor = index;
    _before = {...widget.selectedIds};
    _adding = !_before.contains(widget.items[index].id);
    _dragging = true;
    _update(point);
    _edgeTimer?.cancel();
    _edgeTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!mounted ||
          !_dragging ||
          _position == null ||
          !widget.scrollController.hasClients) {
        return;
      }
      final box = _viewport.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return;
      final y = box.globalToLocal(_position!).dy;
      final delta = y < 40
          ? -((40 - y) / 4).clamp(0, 14).toDouble()
          : y > box.size.height - 40
          ? ((y - box.size.height + 40) / 4).clamp(0, 14).toDouble()
          : 0.0;
      if (delta == 0) return;
      final scroll = widget.scrollController.position;
      widget.scrollController.jumpTo(
        (scroll.pixels + delta).clamp(
          scroll.minScrollExtent,
          scroll.maxScrollExtent,
        ),
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _dragging) _update(_position!);
      });
    });
  }

  void _update(Offset point) {
    _position = point;
    if (_anchor == null || !widget.selectionEnabled) return;
    final box = _viewport.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final local = box.globalToLocal(point);
    final target = _hit(
      box.localToGlobal(
        Offset(
          local.dx.clamp(1, box.size.width - 1),
          local.dy.clamp(1, box.size.height - 1),
        ),
      ),
    );
    if (target == null) return;
    final next = {..._before};
    final first = target < _anchor! ? target : _anchor!;
    final last = target > _anchor! ? target : _anchor!;
    final range = widget.items.sublist(first, last + 1).map((e) => e.id);
    if (_adding) {
      next.addAll(range);
    } else {
      next.removeAll(range);
    }
    if (next.length != widget.selectedIds.length ||
        !next.containsAll(widget.selectedIds)) {
      widget.onSelectionChanged?.call(next);
    }
  }

  void _end() {
    _edgeTimer?.cancel();
    _anchor = null;
    _down = null;
    if (_mouseDown && mounted) setState(() => _mouseDown = false);
    // Ignore the tap synthesized at the end of a pointer selection.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _dragging = false;
    });
  }

  @override
  void dispose() {
    _edgeTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _cards.clear();
  }

  @override
  void didUpdateWidget(CollectionList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (listEquals(oldWidget.items, widget.items) &&
        oldWidget.selectionEnabled == widget.selectionEnabled &&
        oldWidget.isSelectionMode == widget.isSelectionMode &&
        setEquals(oldWidget.selectedIds, widget.selectedIds) &&
        (!widget.isSelectionMode ||
            (oldWidget.activeId == null) == (widget.activeId == null))) {
      _cards.remove(oldWidget.activeId);
      _cards.remove(widget.activeId);
    } else {
      _cards.clear();
    }
    if (!widget.selectionEnabled ||
        (oldWidget.isSelectionMode && !widget.isSelectionMode) ||
        oldWidget.items.length != widget.items.length ||
        oldWidget.items.indexed.any((e) => e.$2.id != widget.items[e.$1].id)) {
      _edgeTimer?.cancel();
      _anchor = null;
      _dragging = false;
      _mouseDown = false;
    }
    final ids = widget.items.map((e) => e.id).toSet();
    _keys.removeWhere((id, _) => !ids.contains(id));
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      key: _viewport,
      onPointerDown: (event) {
        if (event.kind == PointerDeviceKind.mouse &&
            event.buttons == kPrimaryMouseButton &&
            widget.isSelectionMode &&
            widget.selectionEnabled) {
          _down = event.position;
          setState(() => _mouseDown = true);
        }
      },
      onPointerMove: (event) {
        if (!_mouseDown || _down == null) return;
        if (!_dragging && (event.position - _down!).distance > 5) {
          _start(_down!);
        }
        if (_dragging) _update(event.position);
      },
      onPointerUp: (_) => _end(),
      onPointerCancel: (_) => _end(),
      child: RefreshIndicator(
        onRefresh: widget.onRefresh,
        notificationPredicate: (n) => !widget.isSelectionMode && n.depth == 0,
        child: CustomScrollView(
          key: const PageStorageKey('collection-list'),
          scrollCacheExtent: const ScrollCacheExtent.pixels(0),
          controller: widget.scrollController,
          physics: CollectionGridScrollPhysics(
            geometry: _geometry,
            parent: _mouseDown
                ? const NeverScrollableScrollPhysics()
                : const AlwaysScrollableScrollPhysics(),
          ),
          slivers: [
            if (widget.items.isEmpty && !widget.isLoadingMore)
              SliverFillRemaining(
                hasScrollBody: false,
                child: widget.emptyState,
              )
            else
              _CollectionGridSliver(
                items: widget.items,
                scrollGeometry: _geometry,
                children: SliverChildBuilderDelegate(
                  (context, index) => KeyedSubtree(
                    key: ValueKey(widget.items[index].id),
                    child: _cards.putIfAbsent(
                      widget.items[index].id,
                      () => _card(index),
                    ),
                  ),
                  childCount: widget.items.length,
                  findChildIndexCallback: (key) {
                    final id = (key as ValueKey<int>).value;
                    final index = widget.items.indexWhere(
                      (item) => item.id == id,
                    );
                    return index < 0 ? null : index;
                  },
                ),
              ),
            if (widget.isLoadingMore || widget.onLoadMore != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Center(
                    child: widget.isLoadingMore
                        ? const CircularProgressIndicator()
                        : OutlinedButton.icon(
                            onPressed: widget.onLoadMore,
                            icon: const Icon(Icons.expand_more_rounded),
                            label: const Text('加载更多'),
                          ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _card(int index) {
    final item = widget.items[index];
    final selected =
        widget.isSelectionMode && widget.selectedIds.contains(item.id);
    bool selectedAt(int i) =>
        i >= 0 &&
        i < widget.items.length &&
        widget.selectedIds.contains(widget.items[i].id);
    final previous =
        selected && widget.activeId != null && selectedAt(index - 1);
    final next = selected && widget.activeId != null && selectedAt(index + 1);
    final radius = BorderRadius.vertical(
      top: Radius.circular(previous ? 0 : 16),
      bottom: Radius.circular(next ? 0 : 16),
    );
    return Container(
      key: _keys.putIfAbsent(item.id, () => GlobalKey()),
      margin: EdgeInsets.only(bottom: !next ? 4 : 0),
      padding: EdgeInsets.only(bottom: next ? 4 : 0),
      decoration: BoxDecoration(
        color: selected
            ? Theme.of(context).colorScheme.secondaryContainer
            : null,
        borderRadius: radius,
      ),
      child: ContentCard(
        content: item,
        onDeleted: () => widget.onDeleted?.call(item.id),
        isSelectionMode: widget.isSelectionMode,
        isSelected: selected,
        isActive: widget.activeId == item.id,
        onLongPress: widget.selectionEnabled
            ? () => widget.onLongPress?.call(item.id)
            : null,
        onSelectionStart: widget.selectionEnabled
            ? (d) => _start(d.globalPosition)
            : null,
        onSelectionMove: (d) => _update(d.globalPosition),
        onSelectionEnd: (_) => _end(),
        onTap: () {
          if (_dragging || !widget.selectionEnabled) return;
          if (widget.isSelectionMode) {
            widget.onToggleSelection?.call(item.id);
          } else {
            widget.onOpenContent(item, _keys[item.id]!.currentContext!);
          }
        },
      ),
    );
  }
}

/// Only the grid geometry depends on animation progress. Keep the scroll view
/// and its child delegate stable while the pane changes width.
class _CollectionGridSliver extends StatefulWidget {
  const _CollectionGridSliver({
    required this.items,
    required this.scrollGeometry,
    required this.children,
  });
  final List<ShareCard> items;
  final CollectionGridScrollGeometry scrollGeometry;
  final SliverChildDelegate children;

  @override
  State<_CollectionGridSliver> createState() => _CollectionGridSliverState();
}

class _CollectionGridSliverState extends State<_CollectionGridSliver> {
  CollectionGridMetrics? _metrics;
  (List<ShareCard>, double, double, double, TextTheme)? _metricsKey;

  @override
  Widget build(BuildContext context) {
    final pane = WorkspaceGeometry.of(context);
    final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
    final textTheme = Theme.of(context).textTheme;
    final key = (
      widget.items,
      pane.overviewWidth,
      pane.listWidth,
      scale,
      textTheme,
    );
    if (_metricsKey != key) {
      _metricsKey = key;
      _metrics = CollectionGridMetrics(
        widget.items,
        pane.overviewWidth,
        pane.listWidth,
        scale,
        textTheme,
        Directionality.of(context),
      );
    }
    return SliverPadding(
      padding: EdgeInsets.fromLTRB(12, 12, 12, 24),
      sliver: SliverGrid(
        gridDelegate: CollectionGridDelegate(
          metrics: _metrics!,
          progress: pane.progress,
          scrollGeometry: widget.scrollGeometry,
        ),
        delegate: widget.children,
      ),
    );
  }
}
