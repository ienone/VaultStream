import '../../layout/root_page_actions.dart';
import '../../core/utils/toast.dart';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/layout/app_list_detail_workspace.dart';
import '../dashboard/task_result_page.dart';
import '../collection/content_detail_page.dart';
import '../../core/widgets/app_filter_menu.dart';
import '../../routing/app_navigation.dart';
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
  final _scrollController = ScrollController();
  String? _category;
  String _state = 'active';
  int _offset = 0;
  NotificationInboxItem? _selected;

  NotificationQuery get _query =>
      (category: _category, state: _state, offset: _offset);

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _changeFilter(VoidCallback change) {
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
    setState(() {
      change();
      _offset = 0;
      _selected = null;
    });
  }

  Future<void> _refresh() async {
    ref.invalidate(notificationInboxProvider(_query));
    await ref.read(notificationInboxProvider(_query).future);
  }

  @override
  Widget build(BuildContext context) {
    final inbox = ref.watch(notificationInboxProvider(_query));
    final selected = _selected;
    return LayoutBuilder(
      builder: (context, constraints) {
        return AppListDetailWorkspace(
          onClose: () => setState(() => _selected = null),
          selectedId: _selected?.id,
          list: Scaffold(
            backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
            appBar: AppBar(
              automaticallyImplyLeading: false,
              leading: buildRootPageLeading(context),
              title: const Text('消息'),
              actions: [
                IconButton(
                  tooltip: '全部标为已读',
                  onPressed:
                      inbox.value == null || inbox.value!.unreadCount == 0
                      ? null
                      : () => _run(() => markAllNotificationsRead(ref)),
                  icon: const Icon(Icons.done_all_rounded),
                ),
                IconButton(
                  tooltip: '刷新',
                  onPressed: () =>
                      ref.invalidate(notificationInboxProvider(_query)),
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            body: _buildList(inbox),
          ),
          detailBuilder: (_, focused, toggleFocus) => _buildDetail(
            selected!,
            focused: focused,
            toggleFocus: toggleFocus,
          ),
        );
      },
    );
  }

  Widget _buildList(AsyncValue<NotificationInbox> inbox) => SafeArea(
    top: false,
    child: RefreshIndicator(
      onRefresh: _refresh,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final horizontal =
              constraints.maxWidth > AppPane.readableMaxWidth + 32
              ? (constraints.maxWidth - AppPane.readableMaxWidth) / 2
              : 12.0;
          return CustomScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(horizontal, 12, horizontal, 16),
                sliver: SliverToBoxAdapter(
                  child: _InboxFilters(
                    category: _category,
                    state: _state,
                    onCategoryChanged: (value) =>
                        _changeFilter(() => _category = value),
                    onStateChanged: (value) =>
                        _changeFilter(() => _state = value),
                  ),
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(horizontal, 0, horizontal, 24),
                sliver: inbox.when(
                  data: (value) => _InboxBody(
                    inbox: value,
                    state: _state,
                    onOpen: _open,
                    selectedId: _selected?.id,
                    onAction: _applyAction,
                  ),
                  loading: () => const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (error, _) => SliverFillRemaining(
                    hasScrollBody: false,
                    child: _InboxError(
                      message: formatApiErrorMessage(
                        error,
                        fallbackMessage: '消息加载失败',
                      ),
                      onRetry: () =>
                          ref.invalidate(notificationInboxProvider(_query)),
                    ),
                  ),
                ),
              ),
              if (inbox.value case final data?)
                if (_offset > 0 || _offset + data.items.length < data.total)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          TextButton(
                            onPressed: _offset == 0
                                ? null
                                : () => _changePage(_offset - 100),
                            child: const Text('上一页'),
                          ),
                          Text(
                            '${_offset ~/ 100 + 1} / ${(data.total / 100).ceil()}',
                          ),
                          TextButton(
                            onPressed: _offset + data.items.length >= data.total
                                ? null
                                : () => _changePage(_offset + 100),
                            child: const Text('下一页'),
                          ),
                        ],
                      ),
                    ),
                  ),
            ],
          );
        },
      ),
    ),
  );

  void _changePage(int offset) {
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
    setState(() {
      _offset = offset;
      _selected = null;
    });
  }

  Widget _buildDetail(
    NotificationInboxItem item, {
    bool focused = false,
    VoidCallback? toggleFocus,
  }) {
    final uri = Uri.tryParse(item.route ?? '');
    final segments = uri?.pathSegments ?? const <String>[];
    if (segments.length == 2 && segments.first == 'tasks') {
      return _detailScaffold(
        item,
        TaskResultPane(key: ValueKey(item.id), runId: segments[1]),
        focused,
        toggleFocus,
      );
    }
    if (segments.length == 2 && segments.first == 'collection') {
      final id = int.tryParse(segments[1]);
      if (id != null) {
        return ContentDetailPage(
          key: ValueKey(item.id),
          contentId: id,
          focused: focused,
          onToggleFocus: toggleFocus,
          onClose: () => setState(() => _selected = null),
        );
      }
    }
    return _detailScaffold(
      item,
      SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.title, style: Theme.of(context).textTheme.headlineSmall),
            if (item.body?.isNotEmpty == true) ...[
              const SizedBox(height: 16),
              SelectableText(item.body!),
            ],
            if (item.route?.isNotEmpty == true) ...[
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => openAppLocation(context, item.route!),
                child: Text(switch (item.category) {
                  'agent' => '打开对话',
                  'account' => '打开账号',
                  'digest' => '查看动态',
                  _ => '打开详情',
                }),
              ),
            ],
          ],
        ),
      ),
      focused,
      toggleFocus,
    );
  }

  Widget _detailScaffold(
    NotificationInboxItem item,
    Widget body,
    bool focused,
    VoidCallback? toggleFocus,
  ) => Scaffold(
    appBar: AppBar(
      leading: BackButton(onPressed: () => setState(() => _selected = null)),
      title: const Text('消息详情'),
      actions: [
        if (toggleFocus != null)
          IconButton(
            tooltip: focused ? '退出专注' : '专注阅读',
            onPressed: toggleFocus,
            icon: Icon(
              focused
                  ? Icons.fullscreen_exit_rounded
                  : Icons.fullscreen_rounded,
            ),
          ),
      ],
    ),
    body: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: AppPane.readableMaxWidth + 48,
        ),
        child: body,
      ),
    ),
  );

  Future<void> _open(NotificationInboxItem item) async {
    if (item.isUnread) {
      await _run(() => applyNotificationAction(ref, item.id, 'read'));
    }
    if (mounted) setState(() => _selected = item);
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
      Toast.show(
        context,
        formatApiErrorMessage(error, fallbackMessage: '消息状态更新失败'),
        isError: true,
      );
    }
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
    return AppFilterMenuRow(
      menus: [
        AppFilterMenu(
          label: '类别',
          value: category ?? 'all',
          options: const {
            'all': '全部类别',
            'task': '任务',
            'account': '账号状态',
            'agent': 'Agent 消息',
            'capture': '保存记录',
            'digest': '周期摘要',
            'system': '系统消息',
          },
          onSelected: (value) =>
              onCategoryChanged(value == 'all' ? null : value),
        ),
        AppFilterMenu(
          label: '状态',
          value: state,
          options: const {
            'active': '当前消息',
            'unread': '未读',
            'read': '已读',
            'snoozed': '稍后提醒',
            'muted': '已静默',
            'all': '全部记录',
          },
          onSelected: onStateChanged,
        ),
      ],
    );
  }
}

class _InboxBody extends StatelessWidget {
  const _InboxBody({
    required this.inbox,
    this.selectedId,
    required this.state,
    required this.onOpen,
    required this.onAction,
  });

  final NotificationInbox inbox;
  final int? selectedId;
  final String state;
  final Future<void> Function(NotificationInboxItem) onOpen;
  final Future<void> Function(NotificationInboxItem, String) onAction;

  @override
  Widget build(BuildContext context) {
    if (inbox.items.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _InboxEmpty(state: state),
      );
    }
    return SliverList.separated(
      itemCount: inbox.items.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.xs),
      itemBuilder: (context, index) {
        final item = inbox.items[index];
        return _InboxTile(
          key: ValueKey(item.id),
          item: item,
          selected: item.id == selectedId,
          onOpen: () => onOpen(item),
          onAction: (action) => onAction(item, action),
        );
      },
    );
  }
}

class _InboxTile extends StatelessWidget {
  const _InboxTile({
    super.key,
    required this.item,
    this.selected = false,
    required this.onOpen,
    required this.onAction,
  });

  final NotificationInboxItem item;
  final bool selected;
  final VoidCallback onOpen;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: selected
          ? scheme.secondaryContainer
          : item.isUnread
          ? scheme.primaryContainer.withValues(alpha: 0.28)
          : Colors.transparent,
      borderRadius: AppShape.cardBorder,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (item.severity == 'attention') ...[
                    Icon(
                      Icons.error_outline_rounded,
                      color: scheme.error,
                      size: 20,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                  ],
                  Expanded(
                    child: Text(
                      item.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: item.isUnread
                            ? FontWeight.w700
                            : FontWeight.w500,
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
                  _InboxItemMenu(item: item, onSelected: onAction),
                ],
              ),
              if (item.body?.trim().isNotEmpty == true) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  item.body!.trim(),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
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
                      style: theme.textTheme.bodySmall,
                    ),
                  if (item.isMuted)
                    Text('已静默', style: theme.textTheme.bodySmall),
                  if (item.isSnoozed)
                    Text('稍后提醒', style: theme.textTheme.bodySmall),
                  if (item.dismissedAt != null)
                    Text('已移除', style: theme.textTheme.bodySmall),
                ],
              ),
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
      useRootNavigator: true,
      popUpAnimationStyle: MediaQuery.disableAnimationsOf(context)
          ? AnimationStyle.noAnimation
          : null,
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
  const _InboxEmpty({required this.state});
  final String state;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.inbox_outlined,
            size: 44,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            state == 'unread' ? '没有未读消息' : '没有符合筛选条件的消息',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    ),
  );
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
