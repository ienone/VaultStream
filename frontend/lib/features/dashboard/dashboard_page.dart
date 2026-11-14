import '../../core/layout/app_list_detail_workspace.dart';
import '../events/event_detail_page.dart';
import '../../routing/content_route_extra.dart';
import '../../routing/page_origin.dart';
import '../../core/utils/toast.dart';

import 'package:flutter/rendering.dart' show ScrollCacheExtent;

import '../collection/widgets/list/content_flow_item.dart';
import '../collection/widgets/list/collection_workspace.dart';
import '../collection/models/content.dart';
import '../automation/widgets/push_content_dialog.dart';
import '../../layout/root_page_actions.dart';

import 'package:material_ui/material_ui.dart';

import '../../core/widgets/workspace_tabs.dart';

import '../../core/layout/workspace_geometry.dart';

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
  const DashboardPage({super.key, this.selectedContentId});
  final int? selectedContentId;

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage>
    with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 3, vsync: this);
  ShareCard? _preview;
  int? _lastReadId;
  int? _selectedEventId;
  void _openItem(DiscoveryItem item, BuildContext sourceContext) {
    if (widget.selectedContentId == item.id) return;
    _lastReadId = item.id;
    _preview = ShareCard(
      id: item.id,
      platform: item.sourceType ?? 'universal',
      url: item.url,
      title: item.title,
      mediaAssets: item.mediaAssets,
      layoutType: item.layoutType,
      contentType: item.contentType,
      authorName: item.authorName,
      publishedAt: item.publishedAt,
    );
    if (!CollectionWorkspace.supportsSplit(context)) {
      context.push(
        '/collection/${item.id}',
        extra: ContentRouteExtra(
          preview: _preview!,
          origin: PageOrigin(sourceContext),
        ),
      );
      return;
    }
    if (widget.selectedContentId == null) {
      context.go('/home?item=${item.id}');
    } else {
      context.replace('/home?item=${item.id}');
    }
  }

  void _closeReader() {
    final id = widget.selectedContentId;
    if (id != null) {
      context.replace('/home');
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  bool _isLoadingMore = false;
  final Set<int> _busyItems = <int>{};
  DiscoveryFeedView _view = DiscoveryFeedView.recent;
  bool _showEventUpdates = false;
  int _eventsPage = 1;
  EventPageQuery get _eventsQuery =>
      (page: _eventsPage, title: '', contentId: null);

  Future<void> _refresh() async {
    if (_showEventUpdates) {
      final _ = await ref.refresh(knowledgeEventsProvider(_eventsQuery).future);
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
    _closeReader();
    _tabs.animateTo(view == DiscoveryFeedView.recent ? 0 : 1);
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
    _closeReader();
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

      if (item.id == widget.selectedContentId) _closeReader();
      if (stateValue == 'promoted') {
        Toast.show(
          context,
          '已收藏',
          action: SnackBarAction(
            label: '查看',
            onPressed: () => context.push('/collection/${item.id}'),
          ),
        );
      } else if (stateValue == 'snoozed') {
        Toast.show(
          context,
          '已移到稍后看',
          action: SnackBarAction(
            label: '撤销',
            onPressed: () => _restoreItem(item),
          ),
        );
      } else if (stateValue == 'visible') {
        Toast.show(
          context,
          '已移回新动态',
          action: SnackBarAction(
            label: '撤销',
            onPressed: () => _restoreItem(
              item,
              stateValue: 'snoozed',
              successMessage: '已放回稍后看',
            ),
          ),
        );
      } else {
        Toast.show(
          context,
          '已忽略这条动态',
          action: SnackBarAction(
            label: '撤销',
            onPressed: () => _restoreItem(item),
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
      Toast.show(context, successMessage);
    } catch (error) {
      if (mounted) _showError(error, fallback: '恢复动态失败');
    }
  }

  void _showError(Object error, {required String fallback}) {
    Toast.show(
      context,
      formatApiErrorMessage(error, fallbackMessage: fallback),
      isError: true,
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => _buildWorkspace(context, box.biggest),
  );

  Widget _buildWorkspace(BuildContext context, Size availableSize) {
    final wide = CollectionWorkspace.supportsSplit(
      context,
      availableSize: availableSize,
    );
    final feed = _showEventUpdates ? null : ref.watch(discoveryFeedProvider);
    final items = feed?.value?.items;
    final defaultItem =
        items?.where((item) => item.id == _lastReadId).firstOrNull ??
        items?.firstOrNull;
    final selectedId =
        widget.selectedContentId ??
        (wide && !_showEventUpdates ? defaultItem?.id : null);
    final events = _showEventUpdates
        ? ref.watch(knowledgeEventsProvider(_eventsQuery))
        : null;
    final eventItems = events?.value?.items;
    final activeEvent =
        eventItems?.where((item) => item.id == _selectedEventId).firstOrNull ??
        eventItems?.firstOrNull;
    final content = _showEventUpdates
        ? _EventUpdatesFeed(
            page: _eventsPage,
            onPage: (page) => setState(() => _eventsPage = page),
            onRefresh: _refresh,
            selectedId: wide ? activeEvent?.id : null,
            onSelect: (id) {
              if (wide) {
                setState(() => _selectedEventId = id);
              } else {
                context.push('/events/$id');
              }
            },
          )
        : feed!.when(
            loading: () => const SliverFillRemaining(
              hasScrollBody: false,
              child: WorkspacePlaceholder(loading: true, label: ''),
            ),
            error: (error, _) => SliverFillRemaining(
              hasScrollBody: false,
              child: _FeedError(
                message: formatApiErrorMessage(
                  error,
                  fallbackMessage: '无法读取动态',
                ),
                onRetry: _refresh,
              ),
            ),
            data: (data) {
              if (data.items.isEmpty) {
                return _FeedSliverList(
                  children: [
                    _EmptyFeed(
                      view: _view,
                      onAction: _view == DiscoveryFeedView.recent
                          ? () => context.go('/sources')
                          : () => _showView(DiscoveryFeedView.recent),
                    ),
                  ],
                );
              }
              final children = <Widget>[];
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
                    selected: selectedId == item.id,
                    busy: _busyItems.contains(item.id),
                    onOpen: (sourceContext) => _openItem(item, sourceContext),
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
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.expand_more_rounded),
                      label: Text(_isLoadingMore ? '正在加载' : '加载更多'),
                    ),
                  ),
                );
              }
              children.add(const SizedBox(height: AppSpacing.sm));
              return _FeedSliverList(children: children);
            },
          );
    final list = Builder(
      builder: (context) {
        final split = (WorkspaceGeometry.maybeOf(context)?.progress ?? 0) > 0;
        final horizontalPadding =
            split || MediaQuery.sizeOf(context).width < 600 ? 12.0 : 24.0;
        return Scaffold(
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
          appBar: WorkspaceAppBar(
            toolbarHeight: WindowMetrics.of(context).toolbarHeight,
            tabs: WorkspaceTabs(
              controller: _tabs,
              labels: const ['最新', '稍后看', '事件'],
              onTap: (index) {
                if (index == 2) {
                  _showEvents();
                } else {
                  _showView(
                    index == 0
                        ? DiscoveryFeedView.recent
                        : DiscoveryFeedView.later,
                  );
                }
              },
            ),
            actions: const [RootPageActions()],
          ),
          body: RefreshIndicator(
            onRefresh: _refresh,
            child: CustomScrollView(
              scrollCacheExtent: const ScrollCacheExtent.pixels(0),
              key: const PageStorageKey('dashboard-feed'),
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    AppSpacing.sm,
                    horizontalPadding,
                    AppSpacing.xl,
                  ),
                  sliver: content,
                ),
              ],
            ),
          ),
        );
      },
    );
    if (_showEventUpdates) {
      return AppListDetailWorkspace(
        list: list,
        selectedId: wide ? activeEvent?.id : null,
        emptyDetail: WorkspacePlaceholder(
          loading: events!.isLoading,
          label: events.hasError ? '事件加载失败' : '暂无事件',
        ),
        detailBuilder: (_, _, _) =>
            EventDetailPage(eventId: activeEvent!.id, embedded: true),
      );
    }
    return CollectionWorkspace(
      selectedId: selectedId,
      defaultSelection: widget.selectedContentId == null,
      emptyDetail: WorkspacePlaceholder(
        loading: feed!.isLoading,
        label: feed.hasError ? '动态加载失败' : '暂无动态',
      ),
      preview: _preview?.id == selectedId ? _preview : null,
      onClose: _closeReader,
      list: list,
    );
  }
}

class _FeedSliverList extends StatelessWidget {
  const _FeedSliverList({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SliverList.separated(
    itemCount: children.length,
    separatorBuilder: (_, _) => const SizedBox(height: 4),
    itemBuilder: (context, index) => ContentFlowItem(child: children[index]),
  );
}

class _EventUpdatesFeed extends ConsumerWidget {
  const _EventUpdatesFeed({
    required this.onRefresh,
    required this.page,
    required this.onPage,

    required this.onSelect,
    this.selectedId,
  });
  final int page;
  final ValueChanged<int> onPage;

  final int? selectedId;
  final ValueChanged<int> onSelect;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(
      knowledgeEventsProvider((page: page, title: '', contentId: null)),
    );
    return events.when(
      loading: () => const SliverFillRemaining(
        hasScrollBody: false,
        child: WorkspacePlaceholder(loading: true, label: ''),
      ),
      error: (error, _) => SliverFillRemaining(
        hasScrollBody: false,
        child: _FeedError(
          message: formatApiErrorMessage(error, fallbackMessage: '无法读取事件变化'),
          onRetry: onRefresh,
        ),
      ),
      data: (data) => _FeedSliverList(
        children: [
          if (data.items.isEmpty)
            const _EmptyEvents()
          else ...[
            _EventFeedLead(total: data.total),
            for (final event in data.items)
              _EventUpdateCard(
                event: event,
                selected: event.id == selectedId,
                onTap: () => onSelect(event.id),
              ),
          ],
          if (page > 1 || data.hasMore)
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: '上一页',
                  icon: const Icon(Icons.chevron_left),
                  onPressed: page > 1 ? () => onPage(page - 1) : null,
                ),
                Text('第 $page 页'),
                IconButton(
                  tooltip: '下一页',
                  icon: const Icon(Icons.chevron_right),
                  onPressed: data.hasMore ? () => onPage(page + 1) : null,
                ),
              ],
            ),
          const SizedBox(height: AppSpacing.xxl),
        ],
      ),
    );
  }
}

class _EventFeedLead extends StatelessWidget {
  const _EventFeedLead({required this.total});

  final int total;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
    child: DefaultTextStyle(
      style: Theme.of(context).textTheme.bodySmall!
          .copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      child: Text('$total 个进行中事件'),
    ),
  );
}

class _EventUpdateCard extends StatelessWidget {
  const _EventUpdateCard({
    required this.event,
    required this.onTap,
    this.selected = false,
  });
  final bool selected;
  final VoidCallback onTap;

  final KnowledgeEventSummary event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: selected
          ? scheme.secondaryContainer
          : scheme.surfaceContainerLowest,
      borderRadius: AppShape.cardBorder,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.hub_outlined, size: 18, color: scheme.tertiary),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Wrap(
                      spacing: AppSpacing.md,
                      runSpacing: AppSpacing.xs,
                      children: [
                        Text(
                          _relativeTime(event.updatedAt.toLocal()),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          '${event.memberCount} 条内容',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
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
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
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
        Icon(
          Icons.hub_outlined,
          size: 32,
          color: Theme.of(context).colorScheme.tertiary,
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          '还没有进行中的事件',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '在内容详情中选择“加入事件”。',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ],
    ),
  );
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Text(
        label,
        style: Theme.of(context).textTheme.titleMedium
            ?.copyWith(fontWeight: FontWeight.w700),
      ),
    ),
  );
}

class _FeedCard extends StatelessWidget {
  const _FeedCard({
    required this.selected,
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
  final bool selected;
  final bool busy;
  final ValueChanged<BuildContext> onOpen;
  final VoidCallback onPromote;
  final VoidCallback onSnooze;
  final VoidCallback onRestore;
  final VoidCallback onIgnore;
  final DiscoveryFeedView view;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final asset = item.mediaAssets.previewFor(item.contentType);
    final title = _displayTitle(item);

    final excerpt = _displaySummary(item);
    final heading = title.isNotEmpty
        ? title
        : excerpt ?? Uri.tryParse(item.url)?.host ?? '';
    final short = WindowMetrics.of(context).isShortLandscape;
    return Material(
      color: selected
          ? scheme.secondaryContainer
          : scheme.surfaceContainerLowest,
      borderRadius: AppShape.cardBorder,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: busy ? null : () => onOpen(context),
        child: Padding(
          padding: EdgeInsetsDirectional.fromSTEB(16, short ? 8 : 12, 8, 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: LayoutBuilder(
                  builder: (context, box) {
                    final showCover =
                        asset != null &&
                        box.maxWidth /
                                MediaQuery.textScalerOf(context).scale(1) >=
                            220;
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                heading,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  height: 1.35,
                                ),
                              ),
                              if (title.isNotEmpty && excerpt != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  excerpt,
                                  maxLines: short ? 1 : 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (showCover)
                          _FeedThumbnail(
                            key: ValueKey(asset),
                            asset: asset,
                            short: short,
                          ),
                      ],
                    );
                  },
                ),
              ),
              Row(
                children: [
                  Expanded(child: _SourceLine(item: item)),
                  IconButton(
                    tooltip: '收藏',
                    onPressed: busy ? null : onPromote,
                    icon: busy
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.bookmark_add_outlined, size: 20),
                  ),
                  PopupMenuButton<String>(
                    tooltip: '更多操作',
                    enabled: !busy,
                    icon: const Icon(Icons.more_horiz_rounded, size: 20),
                    onSelected: (action) {
                      switch (action) {
                        case 'push':
                          showPushContentDialog(context, [item.id]);
                        case 'later':
                          onSnooze();
                        case 'restore':
                          onRestore();
                        case 'ignore':
                          onIgnore();
                      }
                    },
                    itemBuilder: (_) => [
                      if (view == DiscoveryFeedView.recent)
                        const PopupMenuItem(value: 'later', child: Text('稍后看')),
                      if (view == DiscoveryFeedView.later)
                        const PopupMenuItem(
                          value: 'restore',
                          child: Text('移回最新动态'),
                        ),
                      const PopupMenuItem(value: 'push', child: Text('推送')),
                      const PopupMenuItem(value: 'ignore', child: Text('忽略')),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A failed optional thumbnail relinquishes its space to the headline.
class _FeedThumbnail extends StatefulWidget {
  const _FeedThumbnail({super.key, required this.asset, required this.short});
  final MediaAsset asset;
  final bool short;

  @override
  State<_FeedThumbnail> createState() => _FeedThumbnailState();
}

class _FeedThumbnailState extends State<_FeedThumbnail> {
  bool _failed = false;
  @override
  Widget build(BuildContext context) {
    if (_failed) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: widget.short ? 72 : 76,
          height: widget.short ? 52 : 58,
          child: CardMediaPreview(
            asset: widget.asset,
            failureBuilder: (_, _) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && !_failed) setState(() => _failed = true);
              });
              return const SizedBox.shrink();
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
    final names = item.sourceNames.where((name) => name.trim().isNotEmpty);
    final source =
        names.firstOrNull ??
        _sourceKindLabel(item.sourceKinds.firstOrNull ?? item.sourceType);
    final when = _itemTime(item);
    final time =
        '${when.hour.toString().padLeft(2, '0')}:${when.minute.toString().padLeft(2, '0')}';
    final fields = [
      if (source.isNotEmpty) source,
      if (item.sourceCount > 1) '等 ${item.sourceCount} 个来源',
      time,
    ];
    return Text(
      fields.join(' · '),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
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
          Icon(
            view == DiscoveryFeedView.recent
                ? Icons.dynamic_feed_outlined
                : Icons.schedule_rounded,
            size: 32,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            view == DiscoveryFeedView.recent ? '暂时没有新动态' : '没有稍后看的动态',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Center(
            child: FilledButton.icon(
              onPressed: onAction,
              icon: Icon(
                view == DiscoveryFeedView.recent
                    ? Icons.add_link_rounded
                    : Icons.arrow_back_rounded,
              ),
              label: Text(view == DiscoveryFeedView.recent ? '管理来源' : '查看新动态'),
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
                size: 32,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                '动态暂时不可用',
                style: theme.textTheme.titleMedium?.copyWith(
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

String _previewText(String text) => text
    .replaceAllMapped(
      RegExp(r'!?\[([^\]]*)\]\(https?://[^\s)]+\)'),
      (match) => match[1]!,
    )
    .replaceAll(RegExp(r'https?://[^\s<>）]+'), '')
    .replaceAll(RegExp(r'\(\s*\)|（\s*）'), '')
    .replaceAll(RegExp(r'[（(]\s*$'), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

String _displayTitle(DiscoveryItem item) {
  final title = _previewText(item.title ?? '');
  return ['-', '无标题', '未命名内容'].contains(title) ? '' : title;
}

String? _displaySummary(DiscoveryItem item) {
  final summary = (item.previewText ?? item.summary)?.trim() ?? '';
  final title = _displayTitle(item).replaceAll(RegExp(r'\s+'), ' ').trim();
  var preview = _previewText(summary);
  final titlePrefix = title.replaceFirst(RegExp(r'(…|\.{3})$'), '').trim();
  if (preview.isEmpty ||
      preview == title ||
      (titlePrefix.isNotEmpty &&
          titlePrefix != title &&
          preview.startsWith(titlePrefix))) {
    return null;
  }
  if (title.isNotEmpty && preview.startsWith(title)) {
    preview = preview.substring(title.length).trimLeft();
  }
  return preview.isEmpty ? null : preview;
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
  null || '' => '',
  _ => '',
};
