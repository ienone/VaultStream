import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_client.dart';
import '../../theme/design_tokens.dart';
import 'notification_models.dart';
import 'notification_provider.dart';

class NotificationCenterPage extends ConsumerStatefulWidget {
  const NotificationCenterPage({super.key});

  @override
  ConsumerState<NotificationCenterPage> createState() =>
      _NotificationCenterPageState();
}

class _NotificationCenterPageState
    extends ConsumerState<NotificationCenterPage> {
  String? _category;
  String _state = 'active';

  NotificationQuery get _query => (category: _category, state: _state);

  @override
  Widget build(BuildContext context) {
    final inbox = ref.watch(notificationInboxProvider(_query));
    return Scaffold(
      appBar: AppBar(
        title: const Text('消息盒子'),
        actions: [
          IconButton(
            tooltip: '全部标为已读',
            onPressed: inbox.value?.unreadCount == 0
                ? null
                : () => _run(() => markAllNotificationsRead(ref)),
            icon: const Icon(Icons.done_all_rounded),
          ),
          IconButton(
            tooltip: '刷新',
            onPressed: () => ref.invalidate(notificationInboxProvider(_query)),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _InboxFilters(
              category: _category,
              state: _state,
              onCategoryChanged: (value) => setState(() => _category = value),
              onStateChanged: (value) => setState(() => _state = value),
            ),
            Expanded(
              child: inbox.when(
                data: (value) => _InboxBody(
                  inbox: value,
                  state: _state,
                  onRefresh: () async {
                    ref.invalidate(notificationInboxProvider(_query));
                    await ref.read(notificationInboxProvider(_query).future);
                  },
                  onOpen: _open,
                  onAction: _applyAction,
                ),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => _InboxError(
                  message: formatApiErrorMessage(
                    error,
                    fallbackMessage: '消息盒子加载失败',
                  ),
                  onRetry: () =>
                      ref.invalidate(notificationInboxProvider(_query)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _open(NotificationInboxItem item) async {
    if (item.isUnread) {
      await _run(() => applyNotificationAction(ref, item.id, 'read'));
    }
    if (!mounted || item.route == null || item.route!.isEmpty) return;
    context.push(item.route!);
  }

  Future<void> _applyAction(NotificationInboxItem item, String action) async {
    DateTime? snoozedUntil;
    if (action == 'snooze-hour') {
      action = 'snooze';
      snoozedUntil = DateTime.now().add(const Duration(hours: 1));
    } else if (action == 'snooze-tomorrow') {
      action = 'snooze';
      final now = DateTime.now();
      snoozedUntil = DateTime(now.year, now.month, now.day + 1, 9);
    }
    await _run(
      () => applyNotificationAction(
        ref,
        item.id,
        action,
        snoozedUntil: snoozedUntil,
      ),
    );
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            formatApiErrorMessage(error, fallbackMessage: '消息状态更新失败'),
          ),
        ),
      );
    }
  }
}

class NotificationCenterBadge extends ConsumerWidget {
  const NotificationCenterBadge({
    super.key,
    this.size = 24,
    this.icon = Icons.notifications_none_rounded,
  });

  final double size;
  final IconData icon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(
      notificationInboxProvider(
        defaultNotificationQuery,
      ).select((value) => value.value?.unreadCount ?? 0),
    );
    return Badge(
      isLabelVisible: count > 0,
      label: Text(count > 99 ? '99+' : '$count'),
      child: Icon(icon, size: size),
    );
  }
}

class _InboxFilters extends StatelessWidget {
  const _InboxFilters({
    required this.category,
    required this.state,
    required this.onCategoryChanged,
    required this.onStateChanged,
  });

  final String? category;
  final String state;
  final ValueChanged<String?> onCategoryChanged;
  final ValueChanged<String> onStateChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: [
          SizedBox(
            width: 172,
            child: DropdownButtonFormField<String?>(
              initialValue: category,
              decoration: const InputDecoration(labelText: '类别', isDense: true),
              items: const [
                DropdownMenuItem(value: null, child: Text('全部类别')),
                DropdownMenuItem(value: 'task', child: Text('任务回执')),
                DropdownMenuItem(value: 'account', child: Text('账号状态')),
                DropdownMenuItem(value: 'agent', child: Text('Agent 消息')),
                DropdownMenuItem(value: 'capture', child: Text('捕获回执')),
                DropdownMenuItem(value: 'digest', child: Text('周期摘要')),
                DropdownMenuItem(value: 'system', child: Text('系统消息')),
              ],
              onChanged: onCategoryChanged,
            ),
          ),
          SizedBox(
            width: 172,
            child: DropdownButtonFormField<String>(
              initialValue: state,
              decoration: const InputDecoration(labelText: '状态', isDense: true),
              items: const [
                DropdownMenuItem(value: 'active', child: Text('当前消息')),
                DropdownMenuItem(value: 'unread', child: Text('未读')),
                DropdownMenuItem(value: 'read', child: Text('已读')),
                DropdownMenuItem(value: 'snoozed', child: Text('稍后提醒')),
                DropdownMenuItem(value: 'muted', child: Text('已静默')),
                DropdownMenuItem(value: 'all', child: Text('全部记录')),
              ],
              onChanged: (value) {
                if (value != null) onStateChanged(value);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _InboxBody extends StatelessWidget {
  const _InboxBody({
    required this.inbox,
    required this.state,
    required this.onRefresh,
    required this.onOpen,
    required this.onAction,
  });

  final NotificationInbox inbox;
  final String state;
  final Future<void> Function() onRefresh;
  final Future<void> Function(NotificationInboxItem) onOpen;
  final Future<void> Function(NotificationInboxItem, String) onAction;

  @override
  Widget build(BuildContext context) {
    if (inbox.items.isEmpty) {
      return _InboxEmpty(state: state, onRefresh: onRefresh);
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final horizontal = constraints.maxWidth >= 840
              ? (constraints.maxWidth - 760) / 2
              : AppSpacing.lg;
          return ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              horizontal,
              0,
              horizontal,
              AppSpacing.xxl,
            ),
            itemCount: inbox.items.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, index) {
              final item = inbox.items[index];
              return _InboxTile(
                item: item,
                onOpen: () => onOpen(item),
                onAction: (action) => onAction(item, action),
              );
            },
          );
        },
      ),
    );
  }
}

class _InboxTile extends StatelessWidget {
  const _InboxTile({
    required this.item,
    required this.onOpen,
    required this.onAction,
  });

  final NotificationInboxItem item;
  final VoidCallback onOpen;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isAttention = item.severity == 'attention';
    final iconColor = isAttention ? scheme.error : scheme.primary;
    return Material(
      color: item.isUnread
          ? scheme.primaryContainer.withValues(alpha: 0.28)
          : scheme.surfaceContainerLow,
      borderRadius: AppShape.cardBorder,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: item.route == null ? null : onOpen,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                isAttention
                    ? Icons.error_outline_rounded
                    : item.category == 'capture'
                    ? Icons.save_alt_rounded
                    : Icons.task_alt_rounded,
                color: iconColor,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.title,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: item.isUnread
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                            ),
                          ),
                        ),
                        if (item.isUnread)
                          Semantics(
                            label: '未读',
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: scheme.primary,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (item.body?.trim().isNotEmpty == true) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        item.body!.trim(),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.xs,
                      children: [
                        Text(
                          _relativeTime(item.lastOccurredAt.toLocal()),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        if (item.occurrenceCount > 1)
                          Text(
                            '合并 ${item.occurrenceCount} 次',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        if (item.isMuted)
                          Text('已静默', style: theme.textTheme.bodySmall),
                        if (item.isSnoozed)
                          Text('稍后提醒', style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ],
                ),
              ),
              _InboxItemMenu(item: item, onSelected: onAction),
            ],
          ),
        ),
      ),
    );
  }
}

class _InboxItemMenu extends StatelessWidget {
  const _InboxItemMenu({required this.item, required this.onSelected});

  final NotificationInboxItem item;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: '消息操作',
      onSelected: onSelected,
      itemBuilder: (_) => [
        PopupMenuItem(
          value: item.isUnread ? 'read' : 'unread',
          child: Text(item.isUnread ? '标为已读' : '标为未读'),
        ),
        if (item.isSnoozed)
          const PopupMenuItem(value: 'unsnooze', child: Text('取消稍后提醒'))
        else ...[
          const PopupMenuItem(value: 'snooze-hour', child: Text('一小时后提醒')),
          const PopupMenuItem(value: 'snooze-tomorrow', child: Text('明天上午提醒')),
        ],
        PopupMenuItem(
          value: item.isMuted ? 'unmute' : 'mute',
          child: Text(item.isMuted ? '取消静默' : '静默此消息'),
        ),
        if (item.dismissedAt != null)
          const PopupMenuItem(value: 'restore', child: Text('恢复消息'))
        else
          const PopupMenuItem(value: 'dismiss', child: Text('移除消息')),
      ],
    );
  }
}

class _InboxEmpty extends StatelessWidget {
  const _InboxEmpty({required this.state, required this.onRefresh});

  final String state;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.58,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xxl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.inbox_outlined, size: 52),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      state == 'unread' ? '没有未读消息' : '没有符合筛选条件的消息',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InboxError extends StatelessWidget {
  const _InboxError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.cloud_off_outlined,
            size: 44,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: AppSpacing.lg),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('重试'),
          ),
        ],
      ),
    ),
  );
}

String _relativeTime(DateTime date) {
  final delta = DateTime.now().difference(date);
  if (delta.isNegative || delta.inMinutes < 1) return '刚刚';
  if (delta.inHours < 1) return '${delta.inMinutes} 分钟前';
  if (delta.inDays < 1) return '${delta.inHours} 小时前';
  if (delta.inDays < 7) return '${delta.inDays} 天前';
  return '${date.month}月${date.day}日';
}
