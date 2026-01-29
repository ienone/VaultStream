import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
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

  @override
  void initState() {
    super.initState();
    _localItems = List.from(widget.items);
  }

  @override
  void didUpdateWidget(QueueContentList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.items, widget.items)) {
      setState(() {
        _localItems = List.from(widget.items);
      });
      // 清理不再存在的选中项
      final currentIds = _localItems.map((e) => e.contentId).toSet();
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
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.schedule_send,
              size: 64, color: theme.colorScheme.outline.withValues(alpha: 0.5)),
          const SizedBox(height: 16),
          Text('暂无内容', style: theme.textTheme.titleMedium),
          TextButton.icon(
            onPressed: widget.onRefresh,
            icon: const Icon(Icons.refresh),
            label: const Text('立即刷新'),
          ),
        ],
      ),
    );
  }

  Widget _buildMainList() {
    final isWillPush = widget.currentStatus == QueueStatus.willPush;

    if (!isWillPush) {
      return _buildNormalList();
    }

    // 核心修复：使用 LayoutBuilder + ClipRect 锁定物理显示区域
    // 确保拖动时的虚影（Overlay）在视觉上不超出此 Widget 边界
    return LayoutBuilder(
      builder: (context, constraints) {
        return ClipRect(
          child: SizedBox(
            height: constraints.maxHeight,
            width: constraints.maxWidth,
            child: ReorderableListView.builder(
              padding: EdgeInsets.fromLTRB(16, 16, 16, _isSelectionMode ? 100 : 24),
              itemCount: _localItems.length,
              onReorder: _onReorder,
              proxyDecorator: (child, index, animation) {
                return AnimatedBuilder(
                  animation: animation,
                  builder: (context, _) {
                    final animValue = Curves.easeInOut.transform(animation.value);
                    final elevation = lerpDouble(0, 8, animValue)!;
                    return Material(
                      elevation: elevation,
                      color: Colors.transparent,
                      shadowColor: Colors.black.withValues(alpha: 0.3),
                      child: Transform.scale(
                        scale: lerpDouble(1, 1.02, animValue)!,
                        child: child,
                      ),
                    );
                  },
                );
              },
              itemBuilder: (context, index) {
                final item = _localItems[index];
                return _QueueItemCard(
                  key: ValueKey(item.contentId),
                  item: item,
                  index: index,
                  currentStatus: widget.currentStatus,
                  isSelected: _selectedIds.contains(item.contentId),
                  isSelectionMode: _isSelectionMode,
                  onToggleSelect: () => _toggleSelect(item.contentId),
                  onLongPress: () => _startSelection(item.contentId),
                  onMoveToFiltered: () => _moveItem(item, QueueStatus.filtered),
                  onUpdateSchedule: (newTime) => _updateSchedule(item, newTime),
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
          key: ValueKey(item.contentId),
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

  void _onReorder(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex -= 1;
    if (oldIndex == newIndex) return;

    final movedItem = _localItems[oldIndex];

    setState(() {
      final item = _localItems.removeAt(oldIndex);
      _localItems.insert(newIndex, item);
    });

    try {
      await ref.read(contentQueueProvider.notifier).reorderToIndex(movedItem.contentId, newIndex);
      // 重排后失效，强制从后端拉取权威时间轴
      ref.invalidate(contentQueueProvider);
    } catch (e) {
      widget.onRefresh();
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
    return Positioned(
      left: 16,
      right: 16,
      bottom: 24,
      child: Card(
        color: theme.colorScheme.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Text('已选 ${_selectedIds.length} 项',
                  style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.onPrimaryContainer)),
              const Spacer(),
              TextButton.icon(
                onPressed: _batchPushNow,
                icon: const Icon(Icons.flash_on),
                label: const Text('立即推送'),
              ),
              TextButton.icon(
                onPressed: _batchReschedule,
                icon: const Icon(Icons.calendar_month),
                label: const Text('批量排期'),
              ),
              IconButton(
                onPressed: () => setState(() {
                  _isSelectionMode = false;
                  _selectedIds.clear();
                }),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _batchPushNow() async {
    final ids = _selectedIds.toList();
    setState(() {
      _isSelectionMode = false;
      _selectedIds.clear();
    });

    try {
      await ref.read(contentQueueProvider.notifier).batchPushNow(ids);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('批量推送任务已创建')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('操作失败: $e')));
      }
    }
  }

  Future<void> _batchReschedule() async {
    final ids = _selectedIds.toList();
    final now = DateTime.now();
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      helpText: '选择批量排期的起始时间 (不能早于现在)',
    );

    if (picked == null) return;

    var startTime = DateTime(now.year, now.month, now.day, picked.hour, picked.minute);
    if (startTime.isBefore(now)) {
      startTime = now.add(const Duration(seconds: 10));
    }

    setState(() {
      _isSelectionMode = false;
      _selectedIds.clear();
    });

    try {
      await ref.read(contentQueueProvider.notifier).batchReschedule(ids, startTime);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('批量排期完成，队列已重排')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('操作失败: $e')));
      }
    }
  }

  Future<void> _updateSchedule(QueueItem item, DateTime newTime) async {
    try {
      await ref.read(contentQueueProvider.notifier).updateSchedule(item.contentId, newTime);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('推送时间已更新')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('更新失败: $e')));
      }
    }
  }

  Future<void> _moveItem(QueueItem item, QueueStatus newStatus) async {
    setState(() {
      _localItems.removeWhere((i) => i.contentId == item.contentId);
    });

    try {
      await ref.read(contentQueueProvider.notifier).moveToStatus(item.contentId, newStatus);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已移动到${newStatus.label}')),
        );
      }
    } catch (e) {
      setState(() {
        _localItems.add(item);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('操作失败: $e')),
        );
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
    this.onToggleSelect,
    this.onLongPress,
    this.onMoveToFiltered,
    this.onRestore,
    this.onApprove,
    this.onReject,
    this.onUpdateSchedule,
  });

  final QueueItem item;
  final int index;
  final QueueStatus currentStatus;
  final bool isSelected;
  final bool isSelectionMode;
  final VoidCallback? onToggleSelect;
  final VoidCallback? onLongPress;
  final VoidCallback? onMoveToFiltered;
  final VoidCallback? onRestore;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;
  final Function(DateTime)? onUpdateSchedule;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isWillPush = currentStatus == QueueStatus.willPush;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: isSelectionMode ? onToggleSelect : null,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            color: isSelected ? colorScheme.primary.withValues(alpha: 0.05) : colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected 
                  ? colorScheme.primary 
                  : colorScheme.outlineVariant.withValues(alpha: 0.4),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: IntrinsicHeight(
            child: Row(
              children: [
                // 左侧时间/状态指示器
                if (isWillPush)
                  _buildTimeSection(context)
                else
                  _buildStatusIndicator(context),
                
                // 主内容
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                    child: Row(
                      children: [
                        if (item.coverUrl != null)
                          _buildCover(colorScheme),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.title ?? '无标题',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  _PlatformBadge(platform: item.platform),
                                  if (item.isNsfw)
                                    Padding(
                                      padding: const EdgeInsets.only(left: 8),
                                      child: _Badge(label: 'NSFW', color: Colors.red),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // 操作区
                if (isSelectionMode)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Checkbox(value: isSelected, onChanged: (_) => onToggleSelect?.call()),
                  )
                else
                  _buildActions(context),
                
                // 拖动手柄
                if (isWillPush && !isSelectionMode)
                  ReorderableDragStartListener(
                    index: index,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Icon(Icons.drag_indicator, color: colorScheme.outline.withValues(alpha: 0.5)),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTimeSection(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    // 统一转换为本地时间显示
    final localTime = item.scheduledTime?.toLocal();
    final timeStr = localTime != null
        ? DateFormat('HH:mm').format(localTime)
        : '--:--';

    return PopupMenuButton<dynamic>(
      tooltip: '快速调整时间',
      onSelected: (value) async {
        final now = DateTime.now();
        DateTime? newTime;
        
        if (value is int) {
          final baseTime = localTime ?? now;
          newTime = baseTime.isBefore(now) ? now.add(Duration(minutes: value)) : baseTime.add(Duration(minutes: value));
        } else if (value == 'now') {
          newTime = now;
        } else if (value == 'custom') {
          await _pickTime(context);
          return;
        }

        if (newTime != null) {
          // 限制最小时间不能早于现在
          if (newTime.isBefore(now)) newTime = now.add(const Duration(seconds: 10));
          onUpdateSchedule?.call(newTime);
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'now', child: ListTile(leading: Icon(Icons.bolt, size: 18), title: Text('立即推送'), dense: true)),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 10, child: Text('+10 分钟')),
        const PopupMenuItem(value: 30, child: Text('+30 分钟')),
        const PopupMenuItem(value: 60, child: Text('+1 小时')),
        const PopupMenuItem(value: 120, child: Text('+2 小时')),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'custom', child: ListTile(leading: Icon(Icons.edit_calendar, size: 18), title: Text('自定义时间...'), dense: true)),
      ],
      child: Container(
        width: 60,
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: const BorderRadius.only(topLeft: Radius.circular(11), bottomLeft: Radius.circular(11)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(timeStr, style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold, color: colorScheme.primary)),
            const SizedBox(height: 2),
            Icon(Icons.expand_more, size: 10, color: colorScheme.outline),
          ],
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
      helpText: '设置推送时间 (不能早于现在)',
    );

    if (picked != null && onUpdateSchedule != null) {
      final newDateTime = DateTime(now.year, now.month, now.day, picked.hour, picked.minute);
      // 如果选的是今天且时间已过，或者日期逻辑有问题，进行修正
      var finalTime = newDateTime;
      if (finalTime.isBefore(now)) {
        // 如果点选的时间在今天已过去，自动假定为明天，或者提示错误。这里逻辑上强制设为“现在”
        finalTime = now.add(const Duration(seconds: 10));
      }
      onUpdateSchedule!(finalTime);
    }
  }

  Widget _buildStatusIndicator(BuildContext context) {
    final color = currentStatus == QueueStatus.pendingReview ? Colors.orange : Colors.grey;
    return Container(
      width: 6,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.5),
        borderRadius: const BorderRadius.only(topLeft: Radius.circular(11), bottomLeft: Radius.circular(11)),
      ),
    );
  }

  Widget _buildCover(ColorScheme colorScheme) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: CachedNetworkImage(
        imageUrl: item.coverUrl!,
        width: 48,
        height: 48,
        fit: BoxFit.cover,
        placeholder: (context, url) => Container(width: 48, height: 48, color: colorScheme.surfaceContainerHighest),
      ),
    );
  }

  Widget _buildActions(BuildContext context) {
    if (currentStatus == QueueStatus.pendingReview) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(onPressed: onApprove, icon: const Icon(Icons.check, color: Colors.green, size: 20)),
          IconButton(onPressed: onReject, icon: const Icon(Icons.close, color: Colors.red, size: 20)),
        ],
      );
    }
    if (currentStatus == QueueStatus.willPush) {
      return IconButton(
          onPressed: onMoveToFiltered,
          icon: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error, size: 20));
    }
    return IconButton(onPressed: onRestore, icon: const Icon(Icons.refresh, size: 20));
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Text(label, style: TextStyle(fontSize: 8, color: color, fontWeight: FontWeight.bold)),
    );
  }
}

class _PlatformBadge extends StatelessWidget {
  const _PlatformBadge({required this.platform});
  final String platform;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (platform.toLowerCase()) {
      'bilibili' => (Icons.play_circle_fill, const Color(0xFFFA7298)),
      'weibo' => (Icons.radio_button_checked, const Color(0xFFE6162D)),
      'twitter' => (Icons.tag, const Color(0xFF1DA1F2)),
      'xiaohongshu' => (Icons.book, const Color(0xFFFF2442)),
      'zhihu' => (Icons.question_answer, const Color(0xFF0066FF)),
      _ => (Icons.public, Colors.grey),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 4),
          Text(
            platform.toUpperCase(),
            style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}