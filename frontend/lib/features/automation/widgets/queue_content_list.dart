import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import '../../../core/utils/toast.dart';
import '../../../core/widgets/network_thumbnail.dart';
import '../../../core/widgets/platform_badge.dart';
import '../../../core/media/media_asset.dart';
import '../../../theme/design_tokens.dart';
import '../models/queue_item.dart';
import '../providers/queue_provider.dart';

class QueueContentList extends ConsumerStatefulWidget {
  const QueueContentList({
    super.key,
    required this.items,
    required this.currentStatus,
    required this.onRefresh,
  });

  final List<QueueItem> items;
  final QueueStatus currentStatus;
  final VoidCallback onRefresh;

  @override
  ConsumerState<QueueContentList> createState() => _QueueContentListState();
}

class _QueueContentListState extends ConsumerState<QueueContentList> {
  List<QueueItem> _localItems = [];
  final Set<int> _selectedIds = {};
  bool _isSelectionMode = false;
  bool _isReordering = false; // 拖动中标记，防止外部数据覆盖
  bool _hasAnimatedOnce = false; // 入场动画只播放一次

  @override
  void initState() {
    super.initState();
    _localItems = List.from(widget.items);
  }

  @override
  void didUpdateWidget(QueueContentList oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 如果正在拖动，跳过外部更新以避免闪烁
    if (_isReordering) return;

    if (!listEquals(oldWidget.items, widget.items)) {
      // 智能合并：仅当列表ID集合变化时才完全替换
      final oldIds = _localItems.map((e) => e.id).toSet();
      final newIds = widget.items.map((e) => e.id).toSet();

      if (oldIds.difference(newIds).isNotEmpty ||
          newIds.difference(oldIds).isNotEmpty) {
        // 条目增删时完全替换
        setState(() {
          _localItems = List.from(widget.items);
        });
      } else {
        // 仅顺序字段变化时，更新字段但保持本地顺序
        final newItemMap = {for (var i in widget.items) i.id: i};
        setState(() {
          _localItems = _localItems.map((item) {
            return newItemMap[item.id] ?? item;
          }).toList();
        });
      }

      final currentIds = _localItems.map((e) => e.id).toSet();
      _selectedIds.retainAll(currentIds);
      if (_selectedIds.isEmpty) _isSelectionMode = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_localItems.isEmpty) {
      return _buildEmptyState();
    }

    return Stack(
      children: [
        _buildMainList(),
        if (_isSelectionMode) _buildBatchActionBar(),
      ],
    );
  }

  Widget _buildEmptyState() {
    final message = switch (widget.currentStatus) {
      QueueStatus.willPush => '暂无待推送内容',
      QueueStatus.filtered => '暂无不推送内容',
      QueueStatus.pushed => '暂无已推送内容',
    };
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            TextButton(onPressed: widget.onRefresh, child: const Text('刷新')),
          ],
        ),
      ),
    );
  }

  Widget _buildMainList() {
    final isWillPush = widget.currentStatus == QueueStatus.willPush;

    if (!isWillPush) {
      return _buildNormalList();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return ClipRect(
          child: SizedBox(
            height: constraints.maxHeight,
            width: constraints.maxWidth,
            child: ReorderableListView.builder(
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                _isSelectionMode ? 120 : 24,
              ),
              itemCount: _localItems.length,
              onReorderItem: _onReorderItem,
              buildDefaultDragHandles: false,
              proxyDecorator: (child, index, animation) {
                return AnimatedBuilder(
                  animation: animation,
                  builder: (context, _) {
                    final animValue = AppMotion.emphasizedCurve.transform(
                      animation.value,
                    );
                    final elevation = lerpDouble(0, 12, animValue)!;
                    return Material(
                      elevation: elevation,
                      shape: const RoundedRectangleBorder(
                        borderRadius: AppShape.sheetBorder,
                      ),
                      color: Colors.transparent,
                      shadowColor: Colors.black.withValues(alpha: 0.2),
                      child: Transform.scale(
                        scale: lerpDouble(1, 1.05, animValue)!,
                        child: child,
                      ),
                    );
                  },
                );
              },
              itemBuilder: (context, index) {
                final item = _localItems[index];
                final shouldAnimate = !_hasAnimatedOnce;
                if (index == _localItems.length - 1 && !_hasAnimatedOnce) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _hasAnimatedOnce = true;
                  });
                }
                return _QueueItemCard(
                  key: ValueKey(item.id),
                  item: item,
                  index: index,
                  currentStatus: widget.currentStatus,
                  isSelected: _selectedIds.contains(item.id),
                  isSelectionMode: _isSelectionMode,
                  animateEntry: shouldAnimate,
                  onToggleSelect: () => _toggleSelect(item.id),
                  onLongPress: () => _startSelection(item.id),
                  onMoveToFiltered: () => _moveItem(item, QueueStatus.filtered),
                  onUpdateSchedule: (newTime) => _updateSchedule(item, newTime),
                  onPushNow: () async {
                    if (!context.mounted) return;
                    final runId = await ref
                        .read(contentQueueProvider.notifier)
                        .pushNow(item.id);
                    if (context.mounted) {
                      final suffix = runId == null
                          ? ''
                          : ' #${runId.length > 8 ? runId.substring(0, 8) : runId}';
                      Toast.show(context, '已加入立即推送$suffix');
                    }
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildNormalList() {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _localItems.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final item = _localItems[index];
        return _QueueItemCard(
          key: ValueKey(item.id),
          item: item,
          index: index,
          currentStatus: widget.currentStatus,
          onMoveToFiltered: () => _moveItem(item, QueueStatus.filtered),
          onRestore: () => _moveItem(item, QueueStatus.willPush),
          onApprove: () => _moveItem(item, QueueStatus.willPush),
          onReject: () => _moveItem(item, QueueStatus.filtered),
        );
      },
    );
  }

  void _onReorderItem(int oldIndex, int newIndex) async {
    if (oldIndex == newIndex) return;

    final movedItem = _localItems[oldIndex];

    // 标记拖动中，防止外部更新覆盖
    _isReordering = true;

    // 1. 本地立即更新列表顺序，同时重新计算预估时间
    setState(() {
      final item = _localItems.removeAt(oldIndex);
      _localItems.insert(newIndex, item);
      _recalculateLocalScheduledTimes();
    });

    try {
      // 2. 后端请求
      await ref
          .read(contentQueueProvider.notifier)
          .reorderToIndex(movedItem.id, newIndex);

      // 延迟解除锁定并软刷新
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          _isReordering = false;
          ref.read(contentQueueProvider.notifier).softRefresh();
        }
      });
    } catch (e) {
      // 失败时回滚本地状态
      _isReordering = false;
      setState(() {
        final item = _localItems.removeAt(newIndex);
        _localItems.insert(oldIndex, item);
        _recalculateLocalScheduledTimes();
      });

      if (mounted) {
        Toast.show(context, '排序失败: $e');
      }
    }
  }

  /// 根据当前列表顺序重新计算本地预估推送时间（用于即时UI反馈）
  void _recalculateLocalScheduledTimes() {
    if (_localItems.isEmpty) return;

    // 基于第一个条目的时间，按列表顺序递增分配时间
    final baseTime = _localItems.first.scheduledTime ?? DateTime.now();
    const interval = Duration(minutes: 10); // 默认间隔

    for (int i = 0; i < _localItems.length; i++) {
      final newTime = baseTime.add(interval * i);
      _localItems[i] = _localItems[i].copyWith(scheduledTime: newTime);
    }
  }

  void _startSelection(int id) {
    setState(() {
      _isSelectionMode = true;
      _selectedIds.add(id);
    });
  }

  void _toggleSelect(int id) {
    if (!_isSelectionMode) return;
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
        if (_selectedIds.isEmpty) _isSelectionMode = false;
      } else {
        _selectedIds.add(id);
      }
    });
  }

  Widget _buildBatchActionBar() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Positioned(
      left: 20,
      right: 20,
      bottom: 24,
      child: Card(
        color: colorScheme.primaryContainer,
        elevation: 8,
        shadowColor: colorScheme.shadow.withValues(alpha: 0.2),
        shape: const RoundedRectangleBorder(borderRadius: AppShape.sheetBorder),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.onPrimaryContainer.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppShape.pill),
                ),
                child: Text(
                  '已选 ${_selectedIds.length}',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: _batchPushNow,
                icon: const Icon(Icons.flash_on_rounded, size: 18),
                label: const Text('立即推送'),
                style: FilledButton.styleFrom(
                  backgroundColor: colorScheme.onPrimaryContainer,
                  foregroundColor: colorScheme.primaryContainer,
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                onPressed: _batchReschedule,
                icon: const Icon(Icons.schedule_send_rounded, size: 18),
                label: const Text('批量排期'),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                onPressed: () => setState(() {
                  _isSelectionMode = false;
                  _selectedIds.clear();
                }),
                icon: const Icon(Icons.close_rounded, size: 20),
              ),
            ],
          ),
        ),
      ),
    ).animate().slideY(
      begin: 1,
      end: 0,
      duration: AppMotion.surfaceEnter,
      curve: AppMotion.emphasizedCurve,
    );
  }

  Future<void> _batchPushNow() async {
    final ids = _selectedIds.toList();
    final idsSet = ids.toSet();

    // 乐观更新：将选中项移到列表最前面并更新时间
    final selectedItems = _localItems
        .where((i) => idsSet.contains(i.id))
        .toList();
    final otherItems = _localItems
        .where((i) => !idsSet.contains(i.id))
        .toList();

    setState(() {
      _isSelectionMode = false;
      _selectedIds.clear();

      // 重新排列：选中项放在最前，时间从现在开始递增
      final now = DateTime.now();
      const interval = Duration(seconds: 10);
      for (int i = 0; i < selectedItems.length; i++) {
        selectedItems[i] = selectedItems[i].copyWith(
          scheduledTime: now.add(interval * i),
        );
      }
      // 其他项时间顺延
      final baseTime = now.add(interval * selectedItems.length);
      const normalInterval = Duration(minutes: 10);
      for (int i = 0; i < otherItems.length; i++) {
        otherItems[i] = otherItems[i].copyWith(
          scheduledTime: baseTime.add(normalInterval * i),
        );
      }

      _localItems = [...selectedItems, ...otherItems];
    });

    try {
      final runId = await ref
          .read(contentQueueProvider.notifier)
          .batchPushNow(selectedItems.map((i) => i.id).toList());
      if (mounted) {
        final suffix = runId == null
            ? ''
            : ' #${runId.length > 8 ? runId.substring(0, 8) : runId}';
        Toast.show(context, '批量推送任务已创建$suffix');
      }
    } catch (e) {
      if (mounted) {
        Toast.show(context, '操作失败: $e');
      }
    }
  }

  Future<void> _batchReschedule() async {
    final ids = _selectedIds.toList();
    final now = DateTime.now();
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      helpText: '选择批量排期的起始时间',
    );

    if (picked == null) return;

    var startTime = DateTime(
      now.year,
      now.month,
      now.day,
      picked.hour,
      picked.minute,
    );
    if (startTime.isBefore(now)) {
      startTime = now.add(const Duration(seconds: 10));
    }

    setState(() {
      _isSelectionMode = false;
      _selectedIds.clear();
    });

    try {
      await ref
          .read(contentQueueProvider.notifier)
          .batchReschedule(
            _localItems
                .where((i) => ids.contains(i.id))
                .map((i) => i.id)
                .toList(),
            startTime,
          );
      if (mounted) {
        Toast.show(context, '批量排期完成');
      }
    } catch (e) {
      if (mounted) {
        Toast.show(context, '操作失败: $e');
      }
    }
  }

  Future<void> _updateSchedule(QueueItem item, DateTime newTime) async {
    try {
      await ref
          .read(contentQueueProvider.notifier)
          .updateSchedule(item.id, newTime);
    } catch (e) {
      if (mounted) {
        Toast.show(context, '更新失败: $e');
      }
    }
  }

  Future<void> _moveItem(QueueItem item, QueueStatus newStatus) async {
    setState(() {
      _localItems.removeWhere((i) => i.id == item.id);
    });

    try {
      await ref
          .read(contentQueueProvider.notifier)
          .moveToStatus(item.id, newStatus);
      if (mounted) {
        final dest = newStatus == QueueStatus.filtered ? '已过滤' : '待推送';
        Toast.show(
          context,
          '已移动到"$dest"列表',
          action: SnackBarAction(
            label: '撤销',
            onPressed: () => _moveItem(item, widget.currentStatus),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _localItems.add(item);
      });
      if (mounted) {
        Toast.show(context, '操作失败: $e');
      }
    }
  }
}

class _QueueItemCard extends StatelessWidget {
  const _QueueItemCard({
    super.key,
    required this.item,
    required this.index,
    required this.currentStatus,
    this.isSelected = false,
    this.isSelectionMode = false,
    this.animateEntry = true,
    this.onToggleSelect,
    this.onLongPress,
    this.onMoveToFiltered,
    this.onRestore,
    this.onApprove,
    this.onReject,
    this.onUpdateSchedule,
    this.onPushNow,
  });

  final QueueItem item;
  final int index;
  final QueueStatus currentStatus;
  final bool isSelected;
  final bool isSelectionMode;
  final bool animateEntry;
  final VoidCallback? onToggleSelect;
  final VoidCallback? onLongPress;
  final VoidCallback? onMoveToFiltered;
  final VoidCallback? onRestore;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;
  final Function(DateTime)? onUpdateSchedule;
  final VoidCallback? onPushNow;

  List<MediaAsset> get _coverAssets => item.mediaAssets
      .where(
        (asset) =>
            asset.mediaType == MediaType.image &&
            asset.role != MediaRole.avatar &&
            asset.sources.isNotEmpty,
      )
      .toList(growable: false);

  MediaAsset? get _coverAsset => _coverAssets.firstOrNull;

  List<String> get _coverCandidates {
    return _coverAssets
        .expand((asset) => asset.sources)
        .map((source) => source.url.trim())
        .where((url) => url.isNotEmpty)
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isWillPush = currentStatus == QueueStatus.willPush;
    final reasonText = (item.displayReason ?? '').trim();
    final coverCandidates = _coverCandidates;

    final card = Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AnimatedContainer(
        duration: AppMotion.stateChange,
        decoration: BoxDecoration(
          color: isSelected
              ? colorScheme.primary.withValues(alpha: 0.05)
              : colorScheme.surfaceContainerLow,
          borderRadius: AppShape.paneBorder,
          border: Border.all(
            color: isSelected
                ? colorScheme.primary
                : colorScheme.outlineVariant.withValues(alpha: 0.3),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: isSelectionMode ? onToggleSelect : null,
            onLongPress: onLongPress,
            borderRadius: AppShape.paneBorder,
            child: IntrinsicHeight(
              child: Row(
                children: [
                  if (isWillPush) _buildTimeSection(context),

                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          if (coverCandidates.isNotEmpty)
                            _buildCover(coverCandidates),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.title ?? '无标题内容',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    PlatformBadge(
                                      platform: item.displayPlatform,
                                    ),
                                    if (item.isNsfw)
                                      Padding(
                                        padding: const EdgeInsets.only(left: 8),
                                        child: _Badge(
                                          label: 'NSFW',
                                          color: colorScheme.error,
                                        ),
                                      ),
                                    const Spacer(),
                                    if (!isWillPush &&
                                        item.scheduledTime != null)
                                      Text(
                                        DateFormat(
                                          'MM-dd HH:mm',
                                        ).format(item.scheduledTime!.toLocal()),
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                              color: colorScheme.outline,
                                            ),
                                      ),
                                  ],
                                ),
                                if (!isWillPush && reasonText.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    reasonText,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: colorScheme.error,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  if (isSelectionMode)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Checkbox(
                        value: isSelected,
                        onChanged: (_) => onToggleSelect?.call(),
                      ),
                    )
                  else
                    _buildActions(context),

                  if (isWillPush && !isSelectionMode)
                    ReorderableDragStartListener(
                      index: index,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Icon(
                          Icons.drag_indicator_rounded,
                          size: 20,
                          color: colorScheme.outline.withValues(alpha: 0.3),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (animateEntry) {
      return card
          .animate()
          .fadeIn(delay: AppMotion.listItemStagger * (index % 15))
          .slideX(begin: 0.1, end: 0, curve: AppMotion.standardCurve);
    }
    return card;
  }

  Widget _buildTimeSection(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final localTime = item.scheduledTime?.toLocal();
    final timeStr = localTime != null
        ? DateFormat('HH:mm').format(localTime)
        : '--:--';

    return Theme(
      data: theme.copyWith(
        hoverColor: Colors.transparent,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
      ),
      child: PopupMenuButton<dynamic>(
        tooltip: '调整时间',
        offset: const Offset(72, 0),
        shape: const RoundedRectangleBorder(borderRadius: AppShape.paneBorder),
        onSelected: (value) async {
          final now = DateTime.now();
          DateTime? newTime;
          if (value is int) {
            final baseTime = localTime ?? now;
            newTime = baseTime.isBefore(now)
                ? now.add(Duration(minutes: value))
                : baseTime.add(Duration(minutes: value));
          } else if (value == 'now') {
            onPushNow?.call();
            return;
          } else if (value == 'custom') {
            await _pickTime(context);
            return;
          }
          if (newTime != null) {
            if (newTime.isBefore(now)) {
              newTime = now.add(const Duration(seconds: 10));
            }
            onUpdateSchedule?.call(newTime);
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem(
            value: 'now',
            child: Row(
              children: [
                Icon(Icons.bolt_rounded, size: 20, color: colorScheme.primary),
                const SizedBox(width: 12),
                const Text('立即推送'),
              ],
            ),
          ),
          const PopupMenuDivider(),
          const PopupMenuItem(value: 10, child: Text('+10 分钟')),
          const PopupMenuItem(value: 30, child: Text('+30 分钟')),
          const PopupMenuItem(value: 60, child: Text('+1 小时')),
          const PopupMenuDivider(),
          const PopupMenuItem(
            value: 'custom',
            child: Row(
              children: [
                Icon(Icons.edit_calendar_rounded, size: 20),
                SizedBox(width: 12),
                Text('自定义..'),
              ],
            ),
          ),
        ],
        child: Material(
          color: colorScheme.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(AppShape.pane),
            bottomLeft: const Radius.circular(AppShape.pane),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: null,
            child: Container(
              width: 72,
              alignment: Alignment.center,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    timeStr,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Icon(
                    Icons.timer_outlined,
                    size: 14,
                    color: colorScheme.primary.withValues(alpha: 0.5),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickTime(BuildContext context) async {
    final now = DateTime.now();
    final localTime = item.scheduledTime?.toLocal();
    final initialTime = localTime != null && localTime.isAfter(now)
        ? TimeOfDay.fromDateTime(localTime)
        : TimeOfDay.now();

    final picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme.copyWith(
            primary: Theme.of(context).colorScheme.primary,
          ),
        ),
        child: child!,
      ),
    );

    if (picked != null) {
      final finalTime = DateTime(
        now.year,
        now.month,
        now.day,
        picked.hour,
        picked.minute,
      );
      onUpdateSchedule?.call(
        finalTime.isBefore(now)
            ? now.add(const Duration(seconds: 10))
            : finalTime,
      );
    }
  }

  Widget _buildCover(List<String> coverCandidates) {
    return ClipRRect(
      borderRadius: AppShape.cardMediaBorder,
      child: NetworkThumbnail(
        imageUrl: coverCandidates.first,
        fallbackUrls: coverCandidates.skip(1).toList(growable: false),
        mediaAsset: _coverAsset,
        mediaAssets: _coverAssets,
        purpose: MediaPurpose.card,
        width: 52,
        height: 52,
        fit: BoxFit.cover,
      ),
    );
  }

  Widget _buildActions(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    if (currentStatus == QueueStatus.willPush) {
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: IconButton.filledTonal(
          onPressed: onMoveToFiltered,
          icon: Icon(
            Icons.delete_sweep_rounded,
            color: colorScheme.error,
            size: 20,
          ),
          style: IconButton.styleFrom(
            backgroundColor: colorScheme.error.withValues(alpha: 0.1),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: IconButton.filledTonal(
        onPressed: onRestore,
        icon: const Icon(Icons.restore_page_rounded, size: 20),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppShape.pill),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
