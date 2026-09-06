import '../../layout/root_page_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/responsive_layout.dart';
import '../../core/media/media_asset.dart';
import '../../core/network/api_client.dart';
import '../../core/widgets/network_thumbnail.dart';
import '../../theme/design_tokens.dart';
import '../discovery/models/discovery_models.dart';
import '../discovery/providers/discovery_feed_provider.dart';
import '../events/models/knowledge_event.dart';
import '../events/providers/knowledge_event_provider.dart';

class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  bool _isLoadingMore = false;
  final Set<int> _busyItems = <int>{};
  DiscoveryFeedView _view = DiscoveryFeedView.recent;
  bool _showEventUpdates = false;

  Future<void> _refresh() async {
    if (_showEventUpdates) {
      final _ = await ref.refresh(activeKnowledgeEventsProvider.future);
      return;
    }
    await ref.read(discoveryFeedProvider.notifier).refresh();
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore) return;
    setState(() => _isLoadingMore = true);
    try {
      await ref.read(discoveryFeedProvider.notifier).loadMore();
    } catch (error) {
      if (mounted) _showError(error, fallback: '加载更多动态失败');
    } finally {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  Future<void> _showView(DiscoveryFeedView view) async {
    if (!_showEventUpdates && _view == view) return;
    setState(() {
      _showEventUpdates = false;
      _view = view;
    });
    try {
      await ref.read(discoveryFeedProvider.notifier).showView(view);
    } catch (error) {
      if (mounted) _showError(error, fallback: '切换动态列表失败');
    }
  }

  void _showEvents() {
    if (_showEventUpdates) return;
    setState(() => _showEventUpdates = true);
  }

  Future<void> _actOnItem(
    DiscoveryItem item, {
    required String stateValue,
  }) async {
    if (_busyItems.contains(item.id)) return;
    setState(() => _busyItems.add(item.id));
    try {
      await ref
          .read(discoveryFeedProvider.notifier)
          .actOnItem(item.id, stateValue: stateValue);
      if (!mounted) return;

      if (stateValue == 'promoted') {
        final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(
            content: const Text('已收录到收藏库'),
            action: SnackBarAction(
              label: '查看',
              onPressed: () => context.push('/collection/${item.id}'),
            ),
          ),
        );
      } else if (stateValue == 'snoozed') {
        final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(
            content: const Text('已移到稍后处理'),
            action: SnackBarAction(
              label: '撤销',
              onPressed: () => _restoreItem(item),
            ),
          ),
        );
      } else if (stateValue == 'visible') {
        final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(
            content: const Text('已移回新动态'),
            action: SnackBarAction(
              label: '撤销',
              onPressed: () => _restoreItem(
                item,
                stateValue: 'snoozed',
                successMessage: '已放回稍后处理',
              ),
            ),
          ),
        );
      } else {
        final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(
            content: const Text('已忽略这条动态'),
            action: SnackBarAction(
              label: '撤销',
              onPressed: () => _restoreItem(item),
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) _showError(error, fallback: '更新动态失败');
    } finally {
      if (mounted) setState(() => _busyItems.remove(item.id));
    }
  }

  Future<void> _restoreItem(
    DiscoveryItem item, {
    String stateValue = 'visible',
    String successMessage = '已恢复到动态',
  }) async {
    try {
      await ref
          .read(discoveryFeedProvider.notifier)
          .restoreItem(item, stateValue: stateValue);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(successMessage)));
    } catch (error) {
      if (mounted) _showError(error, fallback: '恢复动态失败');
    }
  }

  void _showError(Object error, {required String fallback}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(formatApiErrorMessage(error, fallbackMessage: fallback)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final feed = ref.watch(discoveryFeedProvider);
    final metrics = WindowMetrics.of(context);
    final horizontalPadding = metrics.widthClass.isCompact
        ? AppSpacing.md
        : AppSpacing.xl;

    return Scaffold(
      appBar: AppBar(
        title: const Text('动态'),
        actions: [
          IconButton(
            tooltip: '刷新动态',
            onPressed: !_showEventUpdates && feed.isLoading ? null : _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const RootPageActions(),
        ],
      ),
      body: _showEventUpdates
          ? _EventUpdatesFeed(
              horizontalPadding: horizontalPadding,
              onRefresh: _refresh,
              onShowDiscovery: _showView,
              onShowEvents: _showEvents,
            )
          : feed.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => _FeedError(
                message: formatApiErrorMessage(
                  error,
                  fallbackMessage: '无法读取动态，请检查服务器连接',
                ),
                onRetry: _refresh,
              ),
              data: (data) {
                if (data.items.isEmpty) {
                  return RefreshIndicator(
                    onRefresh: _refresh,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(
                        horizontalPadding,
                        AppSpacing.sm,
                        horizontalPadding,
                        AppSpacing.xl,
                      ),
                      children: [
                        Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 880),
                            child: _FeedViewSelector(
                              view: _view,
                              showEvents: _showEventUpdates,
                              onChanged: _showView,
                              onShowEvents: _showEvents,
                            ),
                          ),
                        ),
                        _EmptyFeed(
                          view: _view,
                          onAction: _view == DiscoveryFeedView.recent
                              ? () => context.push('/settings?tab=sources')
                              : () => _showView(DiscoveryFeedView.recent),
                        ),
                      ],
                    ),
                  );
                }

                final children = <Widget>[
                  _FeedViewSelector(
                    view: _view,
                    showEvents: _showEventUpdates,
                    onChanged: _showView,
                    onShowEvents: _showEvents,
                  ),
                ];
                String? previousDay;
                for (final item in data.items) {
                  final day = _dayLabel(_itemTime(item));
                  if (day != previousDay) {
                    children.add(_DayHeader(label: day));
                    previousDay = day;
                  }
                  children.add(
                    _FeedCard(
                      item: item,
                      busy: _busyItems.contains(item.id),
                      onOpen: () => context.push('/collection/${item.id}'),
                      onPromote: () => _actOnItem(item, stateValue: 'promoted'),
                      onSnooze: () => _actOnItem(item, stateValue: 'snoozed'),
                      onRestore: () => _actOnItem(item, stateValue: 'visible'),
                      onIgnore: () => _actOnItem(item, stateValue: 'ignored'),
                      view: _view,
                    ),
                  );
                }

                if (data.hasMore) {
                  children.add(
                    Center(
                      child: TextButton.icon(
                        onPressed: _isLoadingMore ? null : _loadMore,
                        icon: _isLoadingMore
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.expand_more_rounded),
                        label: Text(_isLoadingMore ? '正在加载' : '加载更多'),
                      ),
                    ),
                  );
                }
                children.add(const SizedBox(height: AppSpacing.xxl));

                return RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      AppSpacing.sm,
                      horizontalPadding,
                      AppSpacing.xl,
                    ),
                    itemCount: children.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, index) => Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 880),
                        child: children[index],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _FeedViewSelector extends StatelessWidget {
  const _FeedViewSelector({
    required this.view,
    required this.showEvents,
    required this.onChanged,
    required this.onShowEvents,
  });

  final DiscoveryFeedView view;
  final bool showEvents;
  final ValueChanged<DiscoveryFeedView> onChanged;
  final VoidCallback onShowEvents;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: AppSpacing.sm,
    runSpacing: AppSpacing.xs,
    children: [
      ChoiceChip(
        label: const Text('新动态'),
        selected: !showEvents && view == DiscoveryFeedView.recent,
        onSelected: (_) => onChanged(DiscoveryFeedView.recent),
      ),
      ChoiceChip(
        label: const Text('稍后处理'),
        selected: !showEvents && view == DiscoveryFeedView.later,
        onSelected: (_) => onChanged(DiscoveryFeedView.later),
      ),
      ChoiceChip(
        label: const Text('事件变化'),
        selected: showEvents,
        onSelected: (_) => onShowEvents(),
      ),
    ],
  );
}

class _EventUpdatesFeed extends ConsumerWidget {
  const _EventUpdatesFeed({
    required this.horizontalPadding,
    required this.onRefresh,
    required this.onShowDiscovery,
    required this.onShowEvents,
  });

  final double horizontalPadding;
  final Future<void> Function() onRefresh;
  final ValueChanged<DiscoveryFeedView> onShowDiscovery;
  final VoidCallback onShowEvents;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(activeKnowledgeEventsProvider);
    return events.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _FeedError(
        message: formatApiErrorMessage(error, fallbackMessage: '无法读取事件变化'),
        onRetry: onRefresh,
      ),
      data: (data) {
        final children = <Widget>[
          _FeedViewSelector(
            view: DiscoveryFeedView.recent,
            showEvents: true,
            onChanged: onShowDiscovery,
            onShowEvents: onShowEvents,
          ),
          _EventFeedLead(total: data.total),
          if (data.items.isEmpty)
            const _EmptyEvents()
          else
            for (final event in data.items) _EventUpdateCard(event: event),
          const SizedBox(height: AppSpacing.xxl),
        ];
        return RefreshIndicator(
          onRefresh: onRefresh,
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              AppSpacing.sm,
              horizontalPadding,
              AppSpacing.xl,
            ),
            itemCount: children.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, index) => Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 880),
                child: children[index],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _EventFeedLead extends StatelessWidget {
  const _EventFeedLead({required this.total});

  final int total;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
    child: Row(
      children: [
        Expanded(
          child: Text(
            '按最近变化排列的进行中事件',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Text(
          '$total 个事件',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ],
    ),
  );
}

class _EventUpdateCard extends StatelessWidget {
  const _EventUpdateCard({required this.event});

  final KnowledgeEventSummary event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.tertiaryContainer.withValues(alpha: 0.45),
      borderRadius: AppShape.cardBorder,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/events/${event.id}'),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.hub_outlined, color: scheme.tertiary),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      '事件更新 · ${_relativeTime(event.updatedAt.toLocal())}',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Text('${event.memberCount} 条内容'),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                event.title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (event.description?.trim() case final description?
                  when description.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (event.latestMemberTitle?.trim() case final latest?
                  when latest.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  '最新关联：$latest',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyEvents extends StatelessWidget {
  const _EmptyEvents();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(AppSpacing.xl),
    child: Column(
      children: [
        const SizedBox(height: 88),
        Icon(
          Icons.hub_outlined,
          size: 56,
          color: Theme.of(context).colorScheme.tertiary,
        ),
        const SizedBox(height: AppSpacing.lg),
        Text('还没有进行中的事件', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '在内容详情中选择“加入事件”。',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.sm),
    child: Text(
      label,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
    ),
  );
}

class _FeedCard extends StatelessWidget {
  const _FeedCard({
    required this.item,
    required this.busy,
    required this.onOpen,
    required this.onPromote,
    required this.onSnooze,
    required this.onRestore,
    required this.onIgnore,
    required this.view,
  });

  final DiscoveryItem item;
  final bool busy;
  final VoidCallback onOpen;
  final VoidCallback onPromote;
  final VoidCallback onSnooze;
  final VoidCallback onRestore;
  final VoidCallback onIgnore;
  final DiscoveryFeedView view;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final coverAssets = item.mediaAssets
        .where((asset) => asset.mediaType == MediaType.image)
        .toList(growable: false);
    final coverUrl = coverAssets.firstOrNull?.sources.firstOrNull?.url ?? '';

    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: AppShape.cardBorder,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: busy ? null : onOpen,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final showCover = coverUrl.isNotEmpty;
              final coverWidth = constraints.maxWidth < 520 ? 88.0 : 156.0;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SourceLine(item: item),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          _displayTitle(item),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            height: 1.35,
                          ),
                        ),
                        if (_displaySummary(item) case final summary?) ...[
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            summary,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                              height: 1.45,
                            ),
                          ),
                        ],
                        const SizedBox(height: AppSpacing.sm),
                        Wrap(
                          spacing: AppSpacing.xs,
                          runSpacing: AppSpacing.xs,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (view == DiscoveryFeedView.later)
                              TextButton.icon(
                                onPressed: busy ? null : onRestore,
                                icon: const Icon(
                                  Icons.move_to_inbox_outlined,
                                  size: 19,
                                ),
                                label: const Text('移回动态'),
                              ),
                            TextButton.icon(
                              onPressed: busy ? null : onPromote,
                              icon: const Icon(
                                Icons.bookmark_add_outlined,
                                size: 19,
                              ),
                              label: const Text('收录'),
                            ),
                            if (view == DiscoveryFeedView.recent)
                              TextButton.icon(
                                onPressed: busy ? null : onSnooze,
                                icon: const Icon(
                                  Icons.schedule_rounded,
                                  size: 19,
                                ),
                                label: const Text('稍后'),
                              ),
                            TextButton(
                              onPressed: busy ? null : onIgnore,
                              child: const Text('忽略'),
                            ),
                            if (busy) ...[
                              const SizedBox(width: AppSpacing.xs),
                              const SizedBox.square(
                                dimension: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (showCover) ...[
                    const SizedBox(width: AppSpacing.md),
                    NetworkThumbnail(
                      imageUrl: coverUrl,
                      mediaAssets: coverAssets,
                      purpose: MediaPurpose.card,
                      width: coverWidth,
                      height: coverWidth * 0.72,
                      fit: BoxFit.cover,
                      borderRadius: AppShape.cardMediaBorder,
                      maxWidthDiskCache: 480,
                      maxHeightDiskCache: 360,
                      errorIcon: Icons.article_outlined,
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SourceLine extends StatelessWidget {
  const _SourceLine({required this.item});

  final DiscoveryItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final source = item.sourceNames.isNotEmpty
        ? item.sourceNames.take(2).join(' · ')
        : _sourceKindLabel(
            item.sourceKinds.isNotEmpty
                ? item.sourceKinds.first
                : item.sourceType,
          );
    final sourceText = item.sourceCount > 1
        ? '$source · 来自 ${item.sourceCount} 个来源'
        : source;

    return Row(
      children: [
        Icon(_sourceIcon(item), size: 17, color: theme.colorScheme.primary),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            sourceText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Text(
          _relativeTime(_itemTime(item)),
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _EmptyFeed extends StatelessWidget {
  const _EmptyFeed({required this.view, required this.onAction});

  final DiscoveryFeedView view;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        children: [
          const SizedBox(height: 88),
          Icon(
            view == DiscoveryFeedView.recent
                ? Icons.dynamic_feed_outlined
                : Icons.schedule_rounded,
            size: 56,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            view == DiscoveryFeedView.recent ? '暂时没有新动态' : '没有稍后处理的动态',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          if (view == DiscoveryFeedView.recent) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              '可以添加信息来源，或稍后刷新。',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
          Center(
            child: FilledButton.icon(
              onPressed: onAction,
              icon: Icon(
                view == DiscoveryFeedView.recent
                    ? Icons.add_link_rounded
                    : Icons.arrow_back_rounded,
              ),
              label: Text(
                view == DiscoveryFeedView.recent ? '管理信息来源' : '查看新动态',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeedError extends StatelessWidget {
  const _FeedError({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppPane.formMaxWidth),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_off_outlined,
                size: 48,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                '动态暂时不可用',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _displayTitle(DiscoveryItem item) {
  final title = item.title?.trim() ?? '';
  return title.isEmpty || title == '-' ? '未命名内容' : title;
}

String? _displaySummary(DiscoveryItem item) {
  final summary = (item.previewText ?? item.summary)?.trim() ?? '';
  if (summary.isEmpty || summary == _displayTitle(item)) return null;
  return summary.replaceAll(RegExp(r'\s+'), ' ');
}

DateTime _itemTime(DiscoveryItem item) =>
    (item.publishedAt ?? item.discoveredAt ?? item.createdAt).toLocal();

String _dayLabel(DateTime date) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(date.year, date.month, date.day);
  final difference = today.difference(day).inDays;
  if (difference == 0) return '今天';
  if (difference == 1) return '昨天';
  if (date.year == now.year) return '${date.month} 月 ${date.day} 日';
  return '${date.year} 年 ${date.month} 月 ${date.day} 日';
}

String _relativeTime(DateTime date) {
  final difference = DateTime.now().difference(date);
  if (difference.isNegative || difference.inMinutes < 1) return '刚刚';
  if (difference.inHours < 1) return '${difference.inMinutes} 分钟前';
  if (difference.inDays < 1) return '${difference.inHours} 小时前';
  if (difference.inDays < 7) return '${difference.inDays} 天前';
  return '${date.month}/${date.day}';
}

String _sourceKindLabel(String? kind) => switch (kind) {
  'rss' => 'RSS',
  'telegram_channel' => 'Telegram',
  'favorites_sync' => '收藏同步',
  null || '' => '已授权来源',
  _ => kind,
};

IconData _sourceIcon(DiscoveryItem item) {
  final kind = item.sourceKinds.isNotEmpty
      ? item.sourceKinds.first
      : item.sourceType;
  return switch (kind) {
    'rss' => Icons.rss_feed_rounded,
    'telegram_channel' => Icons.send_rounded,
    'favorites_sync' => Icons.sync_rounded,
    _ => Icons.public_rounded,
  };
}
