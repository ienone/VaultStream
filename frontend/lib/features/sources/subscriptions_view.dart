import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/layout/app_page_body.dart';
import '../../core/network/api_client.dart';
import '../../theme/design_tokens.dart';
import '../discovery/models/discovery_models.dart';
import '../discovery/providers/discovery_sources_provider.dart';
import '../settings/presentation/widgets/setting_components.dart'
    show LoadingGroup, showToast;

class SubscriptionFilter {
  const SubscriptionFilter({
    this.query = '',
    this.kind = 'all',
    this.status = 'all',
  });

  final String query, kind, status;
  bool get isActive => kind != 'all' || status != 'all';

  SubscriptionFilter copyWith({String? query, String? kind, String? status}) =>
      SubscriptionFilter(
        query: query ?? this.query,
        kind: kind ?? this.kind,
        status: status ?? this.status,
      );

  bool matches(DiscoverySource source) =>
      source.name.toLowerCase().contains(query.trim().toLowerCase()) &&
      (kind == 'all' || source.kind == kind) &&
      (status == 'all' || source.enabled == (status == 'enabled'));
}

class SubscriptionsView extends ConsumerStatefulWidget {
  const SubscriptionsView({
    super.key,
    required this.onAdd,
    required this.onEdit,
    this.selectedId,
    required this.filter,
    required this.onFilterChanged,
  });
  final VoidCallback onAdd;
  final ValueChanged<DiscoverySource> onEdit;
  final int? selectedId;
  final SubscriptionFilter filter;
  final ValueChanged<SubscriptionFilter> onFilterChanged;
  @override
  ConsumerState<SubscriptionsView> createState() => _SubscriptionsViewState();
}

class _SubscriptionsViewState extends ConsumerState<SubscriptionsView> {
  late final _searchController = TextEditingController(
    text: widget.filter.query,
  );

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppPageBody(
    maxWidth: AppPane.readableMaxWidth,
    child: CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          sliver: _buildDiscoverySources(
            context,
            ref,
            ref.watch(discoverySourcesProvider),
          ),
        ),
      ],
    ),
  );

  Widget _buildDiscoverySources(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<DiscoverySource>> sourcesAsync,
  ) {
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: LayoutBuilder(
              builder: (context, box) {
                final filter = widget.filter;
                return Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: '搜索订阅',
                          prefixIcon: const Icon(Icons.search_rounded),
                          isDense: true,
                          suffixIcon: filter.query.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: '清除搜索',
                                  onPressed: () {
                                    _searchController.clear();
                                    widget.onFilterChanged(
                                      filter.copyWith(query: ''),
                                    );
                                  },
                                  icon: const Icon(Icons.close_rounded),
                                ),
                        ),
                        onChanged: (value) => widget.onFilterChanged(
                          filter.copyWith(query: value),
                        ),
                      ),
                    ),
                    PopupMenuButton<String>(
                      tooltip: '筛选订阅',
                      icon: Badge(
                        isLabelVisible: filter.isActive,
                        child: const Icon(Icons.tune_rounded),
                      ),
                      onSelected: (key) => widget.onFilterChanged(
                        key.startsWith('kind:')
                            ? filter.copyWith(kind: key.substring(5))
                            : filter.copyWith(status: key.substring(7)),
                      ),
                      itemBuilder: (_) => [
                        for (final entry in const {
                          'all': '全部类型',
                          'rss': 'RSS',
                          'telegram_channel': 'Telegram',
                        }.entries)
                          CheckedPopupMenuItem(
                            value: 'kind:${entry.key}',
                            checked: filter.kind == entry.key,
                            child: Text(entry.value),
                          ),
                        const PopupMenuDivider(),
                        for (final entry in const {
                          'all': '全部状态',
                          'enabled': '已启用',
                          'disabled': '已停用',
                        }.entries)
                          CheckedPopupMenuItem(
                            value: 'status:${entry.key}',
                            checked: filter.status == entry.key,
                            child: Text(entry.value),
                          ),
                      ],
                    ),
                    if (box.maxWidth >= 440)
                      FilledButton.icon(
                        onPressed: widget.onAdd,
                        icon: const Icon(Icons.add),
                        label: const Text('添加订阅'),
                      )
                    else
                      IconButton.filledTonal(
                        tooltip: '添加订阅',
                        onPressed: widget.onAdd,
                        icon: const Icon(Icons.add),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
        sourcesAsync.when(
          data: (allSources) {
            final sources = allSources.where(widget.filter.matches).toList();
            return sources.isEmpty
                ? SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        allSources.isEmpty ? '尚未添加订阅来源' : '没有匹配的订阅来源',
                      ),
                    ),
                  )
                : SliverList.builder(
                    itemCount: sources.length,
                    itemBuilder: (context, index) => KeyedSubtree(
                      key: ValueKey(sources[index].id),
                      child: _buildSourceTile(context, ref, sources[index]),
                    ),
                  );
          },
          loading: () => const SliverToBoxAdapter(child: LoadingGroup()),
          error: (error, _) => SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  formatApiErrorMessage(error, fallbackMessage: '暂时无法读取来源列表'),
                ),
                TextButton.icon(
                  onPressed: () => ref.invalidate(discoverySourcesProvider),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('重新加载'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSourceTile(
    BuildContext context,
    WidgetRef ref,
    DiscoverySource source,
  ) {
    final muted =
        source.config['transport'] == 'mtproto' &&
        source.config['notifications_enabled'] == false;
    final kind = source.kind == 'rss' ? 'RSS' : 'Telegram';
    final status = muted
        ? '频道已静音'
        : !source.enabled
        ? '自动同步已关闭'
        : '每 ${_sourceIntervalLabel(source.syncIntervalMinutes)}同步';
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: source.id == widget.selectedId
          ? colors.secondaryContainer
          : Colors.transparent,
      borderRadius: AppShape.cardMediaBorder,
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsetsDirectional.only(start: 8, end: 4),
        leading: CircleAvatar(
          backgroundColor: colors.surfaceContainerHigh,
          foregroundColor: colors.onSurfaceVariant,
          child: Icon(
            source.kind == 'rss' ? Icons.rss_feed_rounded : Icons.send_outlined,
            size: 20,
          ),
        ),
        title: Text(source.name, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '$kind · $status',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        onTap: () => widget.onEdit(source),
        trailing: PopupMenuButton<String>(
          tooltip: '${source.name}的操作',
          onSelected: (action) async {
            if (action == 'edit') {
              widget.onEdit(source);
              return;
            }
            try {
              final actions = ref.read(discoverySourcesProvider.notifier);
              if (action == 'sync') {
                await actions.triggerSync(source.id);
                if (context.mounted) showToast(context, '已开始同步');
              } else {
                await actions.updateSource(source.id, enabled: !source.enabled);
              }
            } catch (error) {
              if (context.mounted) {
                showToast(
                  context,
                  formatApiErrorMessage(error, fallbackMessage: '订阅操作失败'),
                );
              }
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'edit', child: Text('编辑订阅')),
            if (!muted && source.enabled)
              const PopupMenuItem(value: 'sync', child: Text('立即同步')),
            if (!muted)
              PopupMenuItem(
                value: 'toggle',
                child: Text(source.enabled ? '关闭自动同步' : '开启自动同步'),
              ),
          ],
        ),
      ),
    );
  }
}

String _sourceIntervalLabel(int minutes) =>
    minutes % 60 == 0 ? '${minutes ~/ 60} 小时' : '$minutes 分钟';
