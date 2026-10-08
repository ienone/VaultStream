import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
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
    this.columns = 1,
    this.activeId,
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
  final ValueChanged<ShareCard> onOpenContent;
  final int columns;
  final int? activeId;
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
  void didUpdateWidget(CollectionList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.selectionEnabled ||
        (oldWidget.isSelectionMode && !widget.isSelectionMode) ||
        oldWidget.columns != widget.columns ||
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
  Widget build(BuildContext context) => Listener(
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
      if (!_dragging && (event.position - _down!).distance > 5) _start(_down!);
      if (_dragging) _update(event.position);
    },
    onPointerUp: (_) => _end(),
    onPointerCancel: (_) => _end(),
    child: RefreshIndicator(
      onRefresh: widget.onRefresh,
      notificationPredicate: (n) => !widget.isSelectionMode && n.depth == 0,
      child: CustomScrollView(
        key: PageStorageKey(
          widget.activeId == null ? 'collection-overview' : 'collection-list',
        ),
        controller: widget.scrollController,
        physics: _mouseDown
            ? const NeverScrollableScrollPhysics()
            : const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (widget.items.isEmpty && !widget.isLoadingMore)
            SliverFillRemaining(hasScrollBody: false, child: widget.emptyState)
          else
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                widget.columns == 1 ? 8 : 16,
                4,
                widget.columns == 1 ? 8 : 16,
                16,
              ),
              sliver: SliverList.builder(
                itemCount: (widget.items.length / widget.columns).ceil(),
                itemBuilder: (context, row) => widget.columns == 1
                    ? _card(row)
                    : Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (var col = 0; col < widget.columns; col++) ...[
                              if (col > 0) const SizedBox(width: 8),
                              Expanded(
                                child:
                                    row * widget.columns + col <
                                        widget.items.length
                                    ? _card(row * widget.columns + col)
                                    : const SizedBox(),
                              ),
                            ],
                          ],
                        ),
                      ),
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

  Widget _card(int index) {
    final item = widget.items[index];
    final selected =
        widget.isSelectionMode && widget.selectedIds.contains(item.id);
    bool selectedAt(int i) =>
        i >= 0 &&
        i < widget.items.length &&
        widget.selectedIds.contains(widget.items[i].id);
    final previous = selected && widget.columns == 1 && selectedAt(index - 1);
    final next = selected && widget.columns == 1 && selectedAt(index + 1);
    final radius = BorderRadius.vertical(
      top: Radius.circular(previous ? 0 : 16),
      bottom: Radius.circular(next ? 0 : 16),
    );
    return Container(
      key: _keys.putIfAbsent(item.id, () => GlobalKey()),
      margin: EdgeInsets.only(bottom: widget.columns == 1 && !next ? 4 : 0),
      padding: EdgeInsets.only(bottom: widget.columns == 1 && next ? 4 : 0),
      decoration: BoxDecoration(
        color: selected
            ? Theme.of(context).colorScheme.secondaryContainer
            : null,
        borderRadius: radius,
      ),
      child: ContentCard(
        content: item,
        isList: widget.columns == 1,
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
            widget.onOpenContent(item);
          }
        },
      ),
    );
  }
}
