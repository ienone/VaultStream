import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/layout/app_page_body.dart';
import '../../core/network/api_client.dart';
import '../../core/widgets/app_filter_menu.dart';
import '../../theme/design_tokens.dart';
import '../discovery/models/discovery_models.dart';
import '../discovery/providers/discovery_sources_provider.dart';
import '../settings/presentation/widgets/setting_components.dart';
import '../settings/presentation/tabs/push_tab.dart';

class SubscriptionsView extends ConsumerStatefulWidget {
  const SubscriptionsView({
    super.key,
    required this.onAdd,
    required this.onEdit,
    this.selectedId,
  });
  final VoidCallback onAdd;
  final ValueChanged<DiscoverySource> onEdit;
  final int? selectedId;
  @override
  ConsumerState<SubscriptionsView> createState() => _SubscriptionsViewState();
}

class _SubscriptionsViewState extends ConsumerState<SubscriptionsView> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _kind = 'all';
  String _status = 'all';

  @override
  Widget build(BuildContext context) => AppPageBody(
    child: CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          sliver: SliverMainAxisGroup(
            slivers: [
              _buildDiscoverySources(
                context,
                ref,
                ref.watch(discoverySourcesProvider),
              ),
              const SliverToBoxAdapter(
                child: ExpandableSettingTile(
                  title: '机器人消息',
                  expandedContent: PushTab(
                    monitoringOnly: true,
                    embedded: true,
                  ),
                ),
              ),
            ],
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
                final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
                final search = TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    hintText: '搜索订阅来源',
                    prefixIcon: Icon(Icons.search_rounded),
                    isDense: true,
                  ),
                  onChanged: (value) =>
                      setState(() => _query = value.trim().toLowerCase()),
                );
                final add = TextButton.icon(
                  onPressed: widget.onAdd,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('添加'),
                );
                final filters = AppFilterMenuRow(
                  menus: [
                    AppFilterMenu(
                      label: '来源类型',
                      value: _kind,
                      options: const {
                        'all': '全部类型',
                        'rss': 'RSS',
                        'telegram_channel': 'Telegram',
                      },
                      onSelected: (value) => setState(() => _kind = value),
                    ),
                    AppFilterMenu(
                      label: '同步状态',
                      value: _status,
                      options: const {
                        'all': '全部状态',
                        'enabled': '已启用',
                        'disabled': '已停用',
                      },
                      onSelected: (value) => setState(() => _status = value),
                    ),
                  ],
                );
                if (box.maxWidth >= 760 * scale) {
                  return Row(
                    children: [
                      Expanded(child: search),
                      const SizedBox(width: 12),
                      SizedBox(width: 360 * scale, child: filters),
                      const SizedBox(width: 8),
                      add,
                    ],
                  );
                }
                return Column(
                  children: [
                    Row(
                      children: [
                        Expanded(child: search),
                        add,
                      ],
                    ),
                    const SizedBox(height: 8),
                    filters,
                  ],
                );
              },
            ),
          ),
        ),
        sourcesAsync.when(
          data: (allSources) {
            final sources = allSources
                .where(
                  (s) =>
                      s.name.toLowerCase().contains(_query) &&
                      (_kind == 'all' || s.kind == _kind) &&
                      (_status == 'all' || s.enabled == (_status == 'enabled')),
                )
                .toList();
            return sources.isEmpty
                ? const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('没有匹配的订阅来源'),
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            selected: source.id == widget.selectedId,
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            shape: const RoundedRectangleBorder(
              borderRadius: AppShape.cardMediaBorder,
            ),
            title: Text(
              source.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                Text(source.kind == 'rss' ? 'RSS' : 'Telegram 频道'),
                Text(
                  muted
                      ? 'Telegram 已关闭通知，暂停接收'
                      : '每 ${_sourceIntervalLabel(source.syncIntervalMinutes)}同步',
                ),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.sync_rounded),
                  tooltip: '立即同步',
                  onPressed: !source.enabled || muted
                      ? null
                      : () async {
                          try {
                            final runId = await ref
                                .read(discoverySourcesProvider.notifier)
                                .triggerSync(source.id);
                            if (context.mounted) {
                              final suffix = runId == null
                                  ? ''
                                  : ' #${runId.length > 8 ? runId.substring(0, 8) : runId}';
                              showToast(context, '已手动触发同步$suffix');
                            }
                          } catch (e) {
                            if (context.mounted) {
                              showToast(
                                context,
                                formatApiErrorMessage(
                                  e,
                                  fallbackMessage: '手动同步失败',
                                ),
                              );
                            }
                          }
                        },
                ),
                Semantics(
                  label: '启用${source.name}',
                  child: Switch(
                    value: source.enabled && !muted,
                    onChanged: muted
                        ? null
                        : (value) => ref
                              .read(discoverySourcesProvider.notifier)
                              .updateSource(source.id, enabled: value),
                  ),
                ),
              ],
            ),
            onTap: () => widget.onEdit(source),
          ),
        ],
      ),
    );
  }
}

String _sourceIntervalLabel(int minutes) =>
    minutes % 60 == 0 ? '${minutes ~/ 60} 小时' : '$minutes 分钟';
