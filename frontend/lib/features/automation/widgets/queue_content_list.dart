import 'package:material_ui/material_ui.dart';

import '../../../theme/design_tokens.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/network/api_client.dart';
import '../../../core/utils/toast.dart';
import '../../../core/widgets/network_thumbnail.dart';
import '../../../core/media/media_asset.dart';
import '../models/queue_item.dart';
import '../models/bot_chat.dart' show BotChat;
import '../providers/queue_provider.dart';
import '../providers/bot_chats_provider.dart';

class QueueContentList extends ConsumerStatefulWidget {
  const QueueContentList({
    super.key,
    required this.items,
    required this.filter,
    required this.onEmptyAction,
    required this.emptyActionLabel,
    this.header = const [],
    this.onLoadMore,
    required this.onOpen,
    this.activeContentId,
  });
  final List<QueueItem> items;
  final void Function(QueueItem, BuildContext) onOpen;
  final int? activeContentId;
  final QueueFilter filter;
  final VoidCallback onEmptyAction;
  final String emptyActionLabel;
  final List<Widget> header;
  final Future<void> Function()? onLoadMore;
  @override
  ConsumerState<QueueContentList> createState() => _QueueContentListState();
}

class _QueueContentListState extends ConsumerState<QueueContentList> {
  final _scroll = ScrollController();
  final _selected = <int>{};
  bool get _selectionMode => _selected.isNotEmpty;
  bool _busy = false;
  bool _loadingMore = false;
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(QueueContentList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filter != widget.filter) {
      _selected.clear();
    }
    _selected.retainAll(widget.items.where(_editable).map((item) => item.id));
  }

  bool _editable(QueueItem item) =>
      !item.isProcessing &&
      !item.deliveryUnconfirmed &&
      item.status != 'success';

  Future<void> _act(List<QueueItem> items, String action) async {
    if (_busy) return;
    if (action == 'details') {
      final item = items.single;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('发送详情'),
          content: SelectableText(item.reason ?? _statusText(item)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
      return;
    }
    DateTime? time;
    if (action == 'schedule') {
      final now = DateTime.now();
      final date = await showDatePicker(
        context: context,
        initialDate: now,
        firstDate: now,
        lastDate: now.add(const Duration(days: 365)),
        helpText: '发送日期',
      );
      if (date == null || !mounted) return;
      final picked = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(
          now.add(const Duration(minutes: 10)),
        ),
        helpText: '发送时间',
      );
      if (picked == null || !mounted) return;
      time = DateTime(
        date.year,
        date.month,
        date.day,
        picked.hour,
        picked.minute,
      );
      if (!time.isAfter(DateTime.now())) {
        Toast.show(context, '请选择未来的时间');
        return;
      }
    }
    setState(() => _busy = true);
    var completed = 0;
    String? errorMessage;
    final ids = [for (final item in items) item.id];
    final actions = ref.read(contentQueueProvider(widget.filter).notifier);
    try {
      if (action == 'send') {
        final results = await sendQueueItems(ref.read(apiClientProvider), ids);
        for (final result in results) {
          if (result.sent) {
            completed++;
            _selected.remove(result.id);
          } else {
            errorMessage ??= result.error ?? '尚未发送';
          }
        }
      } else {
        if (action == 'cancel') {
          await actions.cancelItems(ids);
        } else {
          await actions.schedule(ids, time!);
        }
        completed = ids.length;
        _selected.removeAll(ids);
      }
    } catch (error) {
      errorMessage = formatApiErrorMessage(error);
    }
    if (!mounted) return;
    setState(() => _busy = false);
    final label = action == 'send'
        ? '已发送'
        : action == 'schedule'
        ? '已设置发送时间'
        : '已取消';
    Toast.show(
      context,
      '$label $completed 项${errorMessage == null ? '' : '；$errorMessage'}',
      isError: errorMessage != null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final chats = widget.items.isEmpty
        ? const <BotChat>[]
        : ref.watch(botChatsProvider).value ?? [];
    final names = {for (final chat in chats) chat.id: chat.displayName};
    final list = CustomScrollView(
      controller: _scroll,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        for (final section in widget.header) SliverToBoxAdapter(child: section),
        if (_busy) const SliverToBoxAdapter(child: LinearProgressIndicator()),
        if (widget.items.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      widget.filter.status == QueueStatus.willPush
                          ? Icons.outbox_outlined
                          : Icons.history_rounded,
                      size: 32,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 12),
                    Text(switch (widget.filter.status) {
                      QueueStatus.willPush => '没有待发送的内容',
                      QueueStatus.filtered => '没有未发送的记录',
                      QueueStatus.history => '还没有发送记录',
                    }, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: widget.onEmptyAction,
                      child: Text(widget.emptyActionLabel),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
            sliver: SliverList.separated(
              itemCount: widget.items.length,
              separatorBuilder: (_, _) =>
                  const Divider(height: 1, indent: 12, endIndent: 12),
              itemBuilder: (context, index) {
                final item = widget.items[index];
                return KeyedSubtree(
                  key: ValueKey(item.id),
                  child: Builder(
                    builder: (rowContext) =>
                        _buildRow(rowContext, item, names[item.botChatId]),
                  ),
                );
              },
            ),
          ),
        if (widget.onLoadMore != null)
          SliverToBoxAdapter(
            child: Center(
              child: TextButton(
                onPressed: _loadingMore
                    ? null
                    : () async {
                        setState(() => _loadingMore = true);
                        try {
                          await widget.onLoadMore!();
                        } catch (error) {
                          if (context.mounted) {
                            Toast.show(
                              context,
                              formatApiErrorMessage(error),
                              isError: true,
                            );
                          }
                        } finally {
                          if (mounted) setState(() => _loadingMore = false);
                        }
                      },
                child: Text(_loadingMore ? '正在加载…' : '加载更多'),
              ),
            ),
          ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: list),
        if (_selectionMode)
          Material(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('已选 ${_selected.length} 项'),
                    IconButton(
                      tooltip: '退出多选',
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                              _selected.clear();
                            }),
                      icon: const Icon(Icons.close_rounded),
                    ),
                    FilledButton.tonal(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                      ),
                      onPressed: _busy || _selected.isEmpty
                          ? null
                          : () => _act(
                              widget.items
                                  .where((i) => _selected.contains(i.id))
                                  .toList(),
                              'send',
                            ),
                      child: const Text('发送'),
                    ),
                    FilledButton.tonal(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                      ),
                      onPressed: _busy || _selected.isEmpty
                          ? null
                          : () => _act(
                              widget.items
                                  .where((i) => _selected.contains(i.id))
                                  .toList(),
                              'cancel',
                            ),
                      child: const Text('取消发送'),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildRow(BuildContext context, QueueItem item, String? chatName) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final selected = _selected.contains(item.id);
    final active = selected || widget.activeContentId == item.contentId;
    final editable = _editable(item);
    final image = item.mediaAssets.cardImage;
    final target = chatName ?? item.targetId ?? item.platform;
    final title = item.title?.trim();
    final state = _statusText(item);
    final error = item.isDeliveryFailure;
    void toggleSelection() => setState(() {
      if (!_selected.remove(item.id)) _selected.add(item.id);
    });
    return Material(
      color: active ? colors.secondaryContainer : Colors.transparent,
      borderRadius: AppShape.cardBorder,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _selectionMode
            ? (editable && !_busy ? toggleSelection : null)
            : () => widget.onOpen(item, context),
        onLongPress: editable && !_busy ? toggleSelection : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            children: [
              if (image != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox.square(
                    dimension: 48,
                    child: CardMediaPreview(asset: image),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title == null || title.isEmpty ? target : title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 3),
                    if (title?.isNotEmpty == true)
                      Text(
                        target,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    Text(
                      state,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: error ? colors.error : colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (_selectionMode)
                Checkbox(
                  value: selected,
                  onChanged: editable && !_busy
                      ? (_) => toggleSelection()
                      : null,
                )
              else if (item.deliveryUnconfirmed)
                IconButton(
                  tooltip: '查看发送详情',
                  icon: const Icon(Icons.info_outline),
                  onPressed: () => _act([item], 'details'),
                )
              else if (editable) ...[
                if (widget.filter.status == QueueStatus.willPush || error)
                  IconButton(
                    tooltip: item.reasonCode == 'approval_required'
                        ? '确认并发送'
                        : error
                        ? '重新发送'
                        : '立即发送',
                    onPressed: _busy ? null : () => _act([item], 'send'),
                    icon: Icon(
                      error ? Icons.replay_rounded : Icons.send_outlined,
                      size: 20,
                    ),
                  ),
                PopupMenuButton<String>(
                  tooltip: '更多操作',
                  enabled: !_busy,
                  onSelected: (action) => action == 'select'
                      ? toggleSelection()
                      : _act([item], action),
                  itemBuilder: (_) => [
                    if (item.reason?.isNotEmpty == true)
                      const PopupMenuItem(
                        value: 'details',
                        child: Text('查看原因'),
                      ),
                    if (widget.filter.status != QueueStatus.willPush && !error)
                      const PopupMenuItem(value: 'send', child: Text('重新发送')),
                    const PopupMenuItem(
                      value: 'schedule',
                      child: Text('设置发送时间'),
                    ),
                    const PopupMenuItem(value: 'select', child: Text('多选')),
                    if (item.reasonCode != 'manual_canceled')
                      const PopupMenuItem(value: 'cancel', child: Text('取消发送')),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _statusText(QueueItem item) {
    if (item.isProcessing) return '发送中';
    if (item.deliveryUnconfirmed) return '未收到回执';
    if (item.status == 'success') {
      final at = item.pushedAt;
      return at == null ? '已发送' : '${_formatTime(at)} 已发送';
    }
    if (item.reasonCode == 'approval_required') return '待确认';
    if (item.reasonCode == 'manual_ready') return '待发送';
    if (item.status == 'failed') return item.displayReason ?? '发送失败';
    final at = item.scheduledTime;
    return at == null ? '待发送' : '计划 ${_formatTime(at)}';
  }

  String _formatTime(DateTime at) =>
      DateFormat('M月d日 HH:mm').format(at.toLocal());
}
