import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
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
    final colorScheme = theme.colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.05),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.auto_awesome_rounded,
                size: 64, color: colorScheme.primary.withValues(alpha: 0.3)),
          ),
          const SizedBox(height: 24),
          Text('暂无待处理内容', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text('队列目前是空的，休息一下吧', style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.outline)),
          const SizedBox(height: 24),
          FilledButton.tonalIcon(
            onPressed: widget.onRefresh,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('刷新队列'),
          ),
        ],
      ),
    ).animate().fadeIn();
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
              padding: EdgeInsets.fromLTRB(16, 16, 16, _isSelectionMode ? 120 : 24),
              itemCount: _localItems.length,
              onReorder: _onReorder,
              buildDefaultDragHandles: false, // Fix Task 3: Disable default handles to prevent overlap
              proxyDecorator: (child, index, animation) {
                return AnimatedBuilder(
                  animation: animation,
                  builder: (context, _) {
                    final animValue = Curves.easeInOut.transform(animation.value);
                    final elevation = lerpDouble(0, 12, animValue)!;
                    return Material(
                      elevation: elevation,
                      borderRadius: BorderRadius.circular(24),
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
    final colorScheme = theme.colorScheme;
    return Positioned(
      left: 20,
      right: 20,
      bottom: 24,
      child: Card(
        color: colorScheme.primaryContainer,
        elevation: 8,
        shadowColor: colorScheme.shadow.withValues(alpha: 0.2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: colorScheme.onPrimaryContainer.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
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
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                onPressed: _batchReschedule,
                icon: const Icon(Icons.event_repeat_rounded, size: 18),
                label: const Text('重排期'),
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
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
    ).animate().slideY(begin: 1, end: 0, curve: Curves.easeOutBack);
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
      helpText: '选择批量排期的起始时间',
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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('批量排期完成')));
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
        String dest = newStatus == QueueStatus.filtered ? '已过滤' : '待推送';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已移动到"$dest"列表'),
            action: SnackBarAction(
              label: '撤销',
              onPressed: () => _moveItem(item, widget.currentStatus),
            ),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _localItems.add(item);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('操作失败: $e')));
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
      child: AnimatedContainer(
        duration: 300.ms,
        decoration: BoxDecoration(
          color: isSelected 
              ? colorScheme.primary.withValues(alpha: 0.05) 
              : colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(24),
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
            borderRadius: BorderRadius.circular(24),
            child: IntrinsicHeight(
              child: Row(
                children: [
                  if (isWillPush)
                    _buildTimeSection(context),
                  
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          if (item.coverUrl != null)
                            _buildCover(colorScheme),
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
                                    letterSpacing: -0.2,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    _PlatformBadge(platform: item.platform),
                                    if (item.isNsfw)
                                      Padding(
                                        padding: const EdgeInsets.only(left: 8),
                                        child: _Badge(label: 'NSFW', color: Colors.red),
                                      ),
                                    const Spacer(),
                                    if (!isWillPush && item.scheduledTime != null)
                                       Text(
                                         DateFormat('MM-dd HH:mm').format(item.scheduledTime!.toLocal()),
                                         style: theme.textTheme.labelSmall?.copyWith(color: colorScheme.outline),
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

                  if (isSelectionMode)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Checkbox(
                        value: isSelected, 
                        onChanged: (_) => onToggleSelect?.call(),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                      ),
                    )
                  else
                    _buildActions(context),
                  
                  if (isWillPush && !isSelectionMode)
                    ReorderableDragStartListener(
                      index: index,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Icon(Icons.drag_indicator_rounded, size: 20, color: colorScheme.outline.withValues(alpha: 0.3)),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    ).animate().fadeIn(delay: (index % 15 * 50).ms).slideX(begin: 0.1, end: 0, curve: Curves.easeOutCubic);
  }

  Widget _buildTimeSection(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final localTime = item.scheduledTime?.toLocal();
    final timeStr = localTime != null ? DateFormat('HH:mm').format(localTime) : '--:--';

    return Theme(
      data: theme.copyWith(
        hoverColor: Colors.transparent,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
      ),
      child: PopupMenuButton<dynamic>(
        tooltip: '调整时间',
        offset: const Offset(72, 0),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        onSelected: (value) async {
          final now = DateTime.now();
          DateTime? newTime;
          if (value is int) {
            final baseTime = localTime ?? now;
            newTime = baseTime.isBefore(now) ? now.add(Duration(minutes: value)) : baseTime.add(Duration(minutes: value));
          } else if (value == 'now') {
            newTime = now.add(const Duration(seconds: 1));
          } else if (value == 'custom') {
            await _pickTime(context);
            return;
          }
          if (newTime != null) {
            if (newTime.isBefore(now)) newTime = now.add(const Duration(seconds: 10));
            onUpdateSchedule?.call(newTime);
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem(
            value: 'now', 
            child: Row(children: [Icon(Icons.bolt_rounded, size: 20, color: colorScheme.primary), const SizedBox(width: 12), const Text('立即推送')]),
          ),
          const PopupMenuDivider(),
          const PopupMenuItem(value: 10, child: Text('+10 分钟')),
          const PopupMenuItem(value: 30, child: Text('+30 分钟')),
          const PopupMenuItem(value: 60, child: Text('+1 小时')),
          const PopupMenuDivider(),
          const PopupMenuItem(value: 'custom', child: Row(children: [Icon(Icons.edit_calendar_rounded, size: 20), SizedBox(width: 12), Text('自定义...')])),
        ],
        child: Material(
          color: colorScheme.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.only(topLeft: Radius.circular(23), bottomLeft: Radius.circular(23)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: null, // Handled by PopupMenuButton
            child: Container(
              width: 72,
              alignment: Alignment.center,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(timeStr, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900, color: colorScheme.primary)),
                  const SizedBox(height: 4),
                  Icon(Icons.timer_outlined, size: 14, color: colorScheme.primary.withValues(alpha: 0.5)),
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
    final initialTime = localTime != null && localTime.isAfter(now) ? TimeOfDay.fromDateTime(localTime) : TimeOfDay.now();
    
    final picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme.copyWith(primary: Theme.of(context).colorScheme.primary),
        ),
        child: child!,
      ),
    );

    if (picked != null) {
      final finalTime = DateTime(now.year, now.month, now.day, picked.hour, picked.minute);
      onUpdateSchedule?.call(finalTime.isBefore(now) ? now.add(const Duration(seconds: 10)) : finalTime);
    }
  }

  Widget _buildCover(ColorScheme colorScheme) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 4, offset: const Offset(0, 2))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: CachedNetworkImage(
          imageUrl: item.coverUrl!,
          width: 52,
          height: 52,
          fit: BoxFit.cover,
          placeholder: (context, url) => Container(color: colorScheme.surfaceContainerHighest),
        ),
      ),
    );
  }

  Widget _buildActions(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    if (currentStatus == QueueStatus.pendingReview) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton.filledTonal(
            onPressed: onApprove, 
            icon: const Icon(Icons.check_rounded, color: Colors.green, size: 20),
            style: IconButton.styleFrom(backgroundColor: Colors.green.withValues(alpha: 0.1)),
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            onPressed: onReject, 
            icon: const Icon(Icons.close_rounded, color: Colors.red, size: 20),
            style: IconButton.styleFrom(backgroundColor: Colors.red.withValues(alpha: 0.1)),
          ),
          const SizedBox(width: 12),
        ],
      );
    }
    if (currentStatus == QueueStatus.willPush) {
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: IconButton.filledTonal(
            onPressed: onMoveToFiltered,
            icon: Icon(Icons.delete_sweep_rounded, color: colorScheme.error, size: 20),
            style: IconButton.styleFrom(backgroundColor: colorScheme.error.withValues(alpha: 0.1)),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: IconButton.filledTonal(onPressed: onRestore, icon: const Icon(Icons.restore_page_rounded, size: 20)),
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
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold)),
    );
  }
}

class _PlatformBadge extends StatelessWidget {
  const _PlatformBadge({required this.platform});
  final String platform;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (platform.toLowerCase()) {
      'bilibili' => (Icons.play_circle_fill_rounded, Color(0xFFFA7298)),
      'weibo' => (Icons.radio_button_checked_rounded, Color(0xFFE6162D)),
      'twitter' => (Icons.tag_rounded, Color(0xFF1DA1F2)),
      'xiaohongshu' => (Icons.explore_rounded, Color(0xFFFF2442)),
      'zhihu' => (Icons.question_answer_rounded, Color(0xFF0066FF)),
      _ => (Icons.public_rounded, Colors.grey),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 6),
          Text(
            platform.toUpperCase(),
            style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold, letterSpacing: 0.5),
          ),
        ],
      ),
    );
  }
}