import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
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

  @override
  void initState() {
    super.initState();
    _localItems = List.from(widget.items);
  }

  @override
  void didUpdateWidget(QueueContentList oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Use listEquals to properly compare list contents
    if (!listEquals(
      oldWidget.items.map((e) => e.contentId).toList(),
      widget.items.map((e) => e.contentId).toList(),
    )) {
      _localItems = List.from(widget.items);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: widget.onRefresh,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('刷新'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _localItems.isEmpty
              ? _buildEmptyState()
              : widget.currentStatus == QueueStatus.willPush
                  ? _buildReorderableList()
                  : _buildNormalList(),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    final theme = Theme.of(context);
    final (icon, text) = switch (widget.currentStatus) {
      QueueStatus.willPush => (Icons.schedule_send, '暂无待推送内容'),
      QueueStatus.filtered => (Icons.filter_alt_off, '暂无被过滤的内容'),
      QueueStatus.pendingReview => (Icons.pending_actions, '暂无待审批内容'),
      QueueStatus.pushed => (Icons.check_circle_outline, '暂无已推送内容'),
    };

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: theme.colorScheme.outline),
          const SizedBox(height: 16),
          Text(text, style: theme.textTheme.titleMedium),
        ],
      ),
    );
  }

  Widget _buildReorderableList() {
    return ReorderableListView(
      padding: const EdgeInsets.all(12),
      onReorder: _onReorder,
      buildDefaultDragHandles: false,
      children: [
        for (int index = 0; index < _localItems.length; index++)
          _QueueItemCard(
            key: ValueKey(_localItems[index].contentId),
            item: _localItems[index],
            currentStatus: widget.currentStatus,
            index: index,
            showDragHandle: true,
            onMoveToFiltered: () => _moveItem(_localItems[index], QueueStatus.filtered),
            onRestore: null,
            onApprove: null,
            onReject: null,
          ),
      ],
    );
  }

  Widget _buildNormalList() {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _localItems.length,
      itemBuilder: (context, index) {
        final item = _localItems[index];
        return _QueueItemCard(
          key: ValueKey(item.contentId),
          item: item,
          currentStatus: widget.currentStatus,
          index: index,
          showDragHandle: false,
          onMoveToFiltered: widget.currentStatus == QueueStatus.willPush
              ? () => _moveItem(item, QueueStatus.filtered)
              : null,
          onRestore: widget.currentStatus == QueueStatus.filtered ||
                  widget.currentStatus == QueueStatus.pushed
              ? () => _moveItem(item, QueueStatus.willPush)
              : null,
          onApprove: widget.currentStatus == QueueStatus.pendingReview
              ? () => _moveItem(item, QueueStatus.willPush)
              : null,
          onReject: widget.currentStatus == QueueStatus.pendingReview
              ? () => _moveItem(item, QueueStatus.filtered)
              : null,
        );
      },
    );
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final item = _localItems.removeAt(oldIndex);
      _localItems.insert(newIndex, item);
    });

    final item = _localItems[newIndex];
    ref.read(contentQueueProvider.notifier).reorderItem(item.contentId, newIndex);
  }

  Future<void> _moveItem(QueueItem item, QueueStatus newStatus) async {
    setState(() {
      _localItems.removeWhere((i) => i.contentId == item.contentId);
    });

    try {
      await ref.read(contentQueueProvider.notifier).moveToStatus(item.contentId, newStatus);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已移动到${newStatus.label}'),
            action: SnackBarAction(
              label: '撤销',
              onPressed: () async {
                await ref.read(contentQueueProvider.notifier).moveToStatus(
                      item.contentId,
                      widget.currentStatus,
                    );
              },
            ),
          ),
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
    required this.currentStatus,
    required this.index,
    required this.showDragHandle,
    this.onMoveToFiltered,
    this.onRestore,
    this.onApprove,
    this.onReject,
  });

  final QueueItem item;
  final QueueStatus currentStatus;
  final int index;
  final bool showDragHandle;
  final VoidCallback? onMoveToFiltered;
  final VoidCallback? onRestore;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            if (showDragHandle) ...[
              ReorderableDragStartListener(
                index: index,
                child: Icon(Icons.drag_handle, color: colorScheme.outline),
              ),
              const SizedBox(width: 12),
            ],
            if (currentStatus == QueueStatus.willPush) ...[
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
            ],
            if (item.coverUrl != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CachedNetworkImage(
                  imageUrl: item.coverUrl!,
                  width: 60,
                  height: 60,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(
                    width: 60,
                    height: 60,
                    color: colorScheme.surfaceContainerHighest,
                  ),
                  errorWidget: (_, __, ___) => Container(
                    width: 60,
                    height: 60,
                    color: colorScheme.surfaceContainerHighest,
                    child: const Icon(Icons.broken_image),
                  ),
                ),
              ),
            if (item.coverUrl != null) const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title ?? '无标题',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _PlatformBadge(platform: item.platform),
                      if (item.authorName != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          item.authorName!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.outline,
                          ),
                        ),
                      ],
                      if (item.isNsfw) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.pink.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'NSFW',
                            style: TextStyle(fontSize: 9, color: Colors.pink, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (item.reason != null && currentStatus == QueueStatus.filtered) ...[
                    const SizedBox(height: 4),
                    Text(
                      item.reason!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.orange,
                      ),
                    ),
                  ],
                  if (item.scheduledTime != null && currentStatus == QueueStatus.willPush) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.schedule, size: 12, color: colorScheme.outline),
                        const SizedBox(width: 4),
                        Text(
                          _formatScheduledTime(item.scheduledTime!),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            _buildActions(context),
          ],
        ),
      ),
    );
  }

  Widget _buildActions(BuildContext context) {
    if (currentStatus == QueueStatus.pendingReview) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton.filled(
            onPressed: onApprove,
            icon: const Icon(Icons.check, size: 20),
            style: IconButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            tooltip: '通过',
          ),
          const SizedBox(width: 4),
          IconButton.filled(
            onPressed: onReject,
            icon: const Icon(Icons.close, size: 20),
            style: IconButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            tooltip: '拒绝',
          ),
        ],
      );
    }

    if (currentStatus == QueueStatus.willPush) {
      return IconButton(
        onPressed: onMoveToFiltered,
        icon: const Icon(Icons.remove_circle_outline),
        color: Colors.orange,
        tooltip: '移到不推送',
      );
    }

    if (currentStatus == QueueStatus.filtered || currentStatus == QueueStatus.pushed) {
      return FilledButton.tonalIcon(
        onPressed: onRestore,
        icon: const Icon(Icons.restore, size: 18),
        label: Text(currentStatus == QueueStatus.pushed ? '重推' : '恢复'),
      );
    }

    return const SizedBox.shrink();
  }

  String _formatScheduledTime(DateTime time) {
    final now = DateTime.now();
    final diff = time.difference(now);
    if (diff.isNegative) return '即将推送';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟后';
    if (diff.inHours < 24) return '${diff.inHours}小时后';
    return '${diff.inDays}天后';
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
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            platform,
            style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
