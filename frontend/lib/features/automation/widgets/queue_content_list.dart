import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../theme/design_tokens.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/network/api_client.dart';
import '../../../core/utils/toast.dart';
import '../../../core/widgets/network_thumbnail.dart';
import '../../../core/media/media_asset.dart';
import '../models/queue_item.dart';
import '../providers/queue_provider.dart';
import '../providers/bot_chats_provider.dart';

class QueueContentList extends ConsumerStatefulWidget {
  const QueueContentList({
    super.key,
    required this.items,
    required this.currentStatus,
    required this.onRefresh,
    this.header = const [],
    this.onLoadMore,
    this.animateEntries = false,
  });
  final bool animateEntries;
  final List<QueueItem> items;
  final QueueStatus currentStatus;
  final VoidCallback onRefresh;
  final List<Widget> header;
  final Future<void> Function()? onLoadMore;
  @override
  ConsumerState<QueueContentList> createState() => _QueueContentListState();
}

class _QueueContentListState extends ConsumerState<QueueContentList> {
  final _scroll = ScrollController();
  final _selected = <int>{};
  bool _selectionMode = false;
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
    if (oldWidget.currentStatus != widget.currentStatus) {
      _selected.clear();
      _selectionMode = false;
    }
    _selected.retainAll(widget.items.where(_editable).map((item) => item.id));
  }

  bool _editable(QueueItem item) =>
      !item.isProcessing &&
      !item.deliveryUnconfirmed &&
      item.status != 'success';

  Future<void> _act(List<QueueItem> items, String action) async {
    if (_busy) return;
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
    for (final item in items) {
      try {
        final actions = ref.read(contentQueueProvider.notifier);
        if (action == 'send') {
          final result = await actions.pushNow(item.id);
          if (result.status != 'success') {
            errorMessage = result.deliveryUnconfirmed
                ? '未收到发送回执'
                : (result.displayReason ?? '尚未发送');
            continue;
          }
        } else if (action == 'schedule') {
          await actions.updateSchedule(item.id, time!);
        } else {
          await actions.moveToStatus(
            item.id,
            QueueStatus.filtered,
            reason: '已取消发送',
          );
        }
        completed++;
        _selected.remove(item.id);
      } catch (error) {
        errorMessage = formatApiErrorMessage(error);
      }
    }
    if (!mounted) return;
    setState(() => _busy = false);
    widget.onRefresh();
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
    final chats = ref.watch(botChatsProvider).value ?? [];
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
            child: Center(child: Text('暂无${widget.currentStatus.label}内容')),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList.separated(
              itemCount: widget.items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final item = widget.items[index];
                final canEdit = _editable(item) && !_busy;
                final asset = item.mediaAssets
                    .where(
                      (a) =>
                          a.mediaType == MediaType.image &&
                          a.role != MediaRole.avatar &&
                          a.sources.isNotEmpty,
                    )
                    .firstOrNull;
                final time = item.scheduledTime;
                final selected = _selected.contains(item.id);
                final row = Material(
                  color: selected
                      ? Theme.of(context).colorScheme.secondaryContainer
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: _selectionMode
                        ? canEdit
                              ? () => setState(() {
                                  selected
                                      ? _selected.remove(item.id)
                                      : _selected.add(item.id);
                                })
                              : null
                        : () => context.push('/collection/${item.contentId}'),
                    onLongPress: canEdit
                        ? () => setState(() {
                            _selectionMode = true;
                            _selected.add(item.id);
                          })
                        : null,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (asset != null)
                                Padding(
                                  padding: const EdgeInsets.only(right: 12),
                                  child: NetworkThumbnail(
                                    imageUrl: asset.sources.first.url,
                                    mediaAsset: asset,
                                    purpose: MediaPurpose.card,
                                    width: 56,
                                    height: 56,
                                    fit: BoxFit.cover,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.title?.trim().isNotEmpty == true
                                          ? item.title!
                                          : '无标题内容',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleSmall,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '发往 ${names[item.botChatId] ?? item.targetId ?? item.platform}',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                              if (_selectionMode)
                                Checkbox(
                                  value: selected,
                                  onChanged: canEdit
                                      ? (value) => setState(() {
                                          value == true
                                              ? _selected.add(item.id)
                                              : _selected.remove(item.id);
                                        })
                                      : null,
                                )
                              else if (_editable(item))
                                PopupMenuButton<String>(
                                  tooltip: '推送操作',
                                  enabled: !_busy,
                                  onSelected: (action) => action == 'select'
                                      ? setState(() {
                                          _selectionMode = true;
                                          _selected.add(item.id);
                                        })
                                      : _act([item], action),
                                  itemBuilder: (_) => [
                                    PopupMenuItem(
                                      value: 'send',
                                      child: Text(
                                        item.reasonCode == 'approval_required'
                                            ? '确认并发送'
                                            : '立即发送',
                                      ),
                                    ),
                                    const PopupMenuItem(
                                      value: 'schedule',
                                      child: Text('设置发送时间…'),
                                    ),
                                    const PopupMenuItem(
                                      value: 'select',
                                      child: Text('选择'),
                                    ),
                                    const PopupMenuItem(
                                      value: 'cancel',
                                      child: Text('取消发送'),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            item.isProcessing
                                ? '正在发送'
                                : item.deliveryUnconfirmed
                                ? '未收到发送回执'
                                : item.status == 'success'
                                ? (item.pushedAt == null
                                      ? '已发送'
                                      : DateFormat(
                                          'M月d日 HH:mm',
                                        ).format(item.pushedAt!.toLocal()))
                                : item.reasonCode == 'approval_required'
                                ? '等待确认发送'
                                : item.status == 'failed'
                                ? (item.displayReason ?? '发送失败')
                                : time == null
                                ? '等待发送'
                                : '计划 ${DateFormat('M月d日 HH:mm').format(time.toLocal())}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
                return widget.animateEntries &&
                        !MediaQuery.disableAnimationsOf(context)
                    ? row.animate().fadeIn(
                        delay: AppMotion.listItemStagger * (index % 15),
                      )
                    : row;
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
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                              _selected.clear();
                              _selectionMode = false;
                            }),
                      child: const Text('取消选择'),
                    ),
                    FilledButton.tonal(
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
                    TextButton(
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
}
