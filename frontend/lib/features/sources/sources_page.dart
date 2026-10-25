import '../../core/layout/app_page_body.dart';
import '../../core/layout/app_list_detail_workspace.dart';
import '../../core/network/api_client.dart';
import '../discovery/providers/discovery_sources_provider.dart';
import 'source_editor.dart';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../layout/root_page_actions.dart';
import '../automation/widgets/favorites_sync_automation_panel.dart';
import 'subscriptions_view.dart';
import '../settings/presentation/tabs/connection_tab.dart';
import '../settings/providers/platform_health_provider.dart';

class SourcesPage extends ConsumerStatefulWidget {
  const SourcesPage({
    super.key,
    this.tab = 0,
    this.highlightRunId,
    this.editor,
    this.platform,
    this.accountDetail,
  });
  final String? editor;
  final String? platform;
  final Widget? accountDetail;
  final int tab;
  final String? highlightRunId;

  @override
  ConsumerState<SourcesPage> createState() => _SourcesPageState();
}

class _SourcesPageState extends ConsumerState<SourcesPage>
    with SingleTickerProviderStateMixin {
  late final _visitedTabs = <int>{widget.tab};
  late final _tabs = TabController(
    length: 3,
    vsync: this,
    initialIndex: widget.tab,
  );

  @override
  void didUpdateWidget(SourcesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tab != widget.tab) {
      _tabs.index = widget.tab;
      _visitedTabs.add(widget.tab);
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editor = widget.editor;
    final detail = widget.accountDetail;
    return AppListDetailWorkspace(
      selectedId: editor ?? widget.platform,
      onClose: () => context.go(
        editor != null
            ? '/sources'
            : GoRouterState.of(context).uri.queryParameters['from'] == 'sync'
            ? '/sources/sync'
            : '/accounts',
      ),
      list: _buildOverview(context),
      detailBuilder: (_, _, _) =>
          editor != null ? _buildEditor(context, editor) : detail!,
    );
  }

  Widget _buildEditor(BuildContext context, String editor) {
    void close() => context.go('/sources');
    final sourceId = int.tryParse(editor);
    if (editor == 'new') {
      return SourceEditor(
        key: const ValueKey('new-source'),
        onClose: close,
        onSave: (source) =>
            ref.read(discoverySourcesProvider.notifier).createSource(source),
      );
    }
    return ref
        .watch(discoverySourcesProvider)
        .when(
          data: (sources) {
            final source = sources
                .where((source) => source.id == sourceId)
                .firstOrNull;
            if (source == null) {
              return Scaffold(
                appBar: AppBar(leading: BackButton(onPressed: close)),
                body: const Center(child: Text('来源已不存在')),
              );
            }
            return SourceEditor(
              key: ValueKey(source.id),
              initialSource: source,
              onClose: close,
              onSave: (updated) => ref
                  .read(discoverySourcesProvider.notifier)
                  .updateSource(
                    source.id,
                    name: updated.name,
                    enabled: updated.enabled,
                    config: updated.config,
                    syncIntervalMinutes: updated.syncIntervalMinutes,
                  ),
              onDelete: () => ref
                  .read(discoverySourcesProvider.notifier)
                  .deleteSource(source.id),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Scaffold(
            appBar: AppBar(leading: BackButton(onPressed: close)),
            body: Center(
              child: Text(
                formatApiErrorMessage(error, fallbackMessage: '暂时无法读取来源'),
              ),
            ),
          ),
        );
  }

  Widget _buildOverview(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('来源'),
      leading: buildRootPageLeading(context),
      actions: [
        if (widget.tab == 1)
          IconButton(
            tooltip: '刷新账号状态',
            onPressed: () => ref.invalidate(platformHealthProvider),
            icon: const Icon(Icons.refresh_rounded),
          ),
      ],
      bottom: TabBar.secondary(
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        dividerColor: Colors.transparent,
        controller: _tabs,
        tabs: const [
          Tab(text: '订阅动态'),
          Tab(text: '连接账号'),
          Tab(text: '收藏同步'),
        ],
        onTap: (index) =>
            context.go(const ['/sources', '/accounts', '/sources/sync'][index]),
      ),
    ),
    body: IndexedStack(
      index: widget.tab,
      children: [
        _visitedTabs.contains(0)
            ? TickerMode(
                enabled: widget.tab == 0,
                child: SubscriptionsView(
                  selectedId: int.tryParse(widget.editor ?? ''),
                  onAdd: () => context.go('/sources?edit=new'),
                  onEdit: (source) => context.go('/sources?edit=${source.id}'),
                ),
              )
            : const SizedBox.shrink(),
        _visitedTabs.contains(1)
            ? TickerMode(
                enabled: widget.tab == 1,
                child: AppPageBody(
                  child: ConnectionTab(
                    accountsOnly: true,
                    selectedPlatform: widget.platform,
                    onOpenPlatform: (platform) =>
                        context.go('/accounts/${platform.platform}'),
                  ),
                ),
              )
            : const SizedBox.shrink(),
        _visitedTabs.contains(2)
            ? TickerMode(
                enabled: widget.tab == 2,
                child: FavoritesSyncAutomationPanel(
                  highlightRunId: widget.highlightRunId,
                ),
              )
            : const SizedBox.shrink(),
      ],
    ),
  );
}
