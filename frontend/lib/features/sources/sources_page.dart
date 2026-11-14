import '../accounts/account_detail_page.dart';
import '../../core/layout/app_page_body.dart';
import '../../core/layout/app_list_detail_workspace.dart';
import '../../core/network/api_client.dart';
import '../discovery/providers/discovery_sources_provider.dart';
import 'source_editor.dart';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/workspace_tabs.dart';
import '../../theme/design_tokens.dart';
import '../automation/widgets/favorites_sync_automation_panel.dart';
import 'subscriptions_view.dart';
import '../settings/presentation/tabs/push_tab.dart';
import '../settings/presentation/tabs/connection_tab.dart';

enum SourcesSection {
  subscriptions('订阅源', '/sources'),
  monitoring('会话监听', '/sources/chats'),
  accounts('账号', '/accounts'),
  sync('收藏同步', '/sources/sync');

  const SourcesSection(this.label, this.path);
  final String label;
  final String path;
}

class SourcesPage extends ConsumerStatefulWidget {
  const SourcesPage({
    super.key,
    this.tab = SourcesSection.subscriptions,
    this.syncPlatform,
    this.editor,
    this.platform,
    this.accountDetail,
  });
  final String? editor;
  final String? platform;
  final Widget? accountDetail;
  final SourcesSection tab;
  final String? syncPlatform;

  @override
  ConsumerState<SourcesPage> createState() => _SourcesPageState();
}

class _SourcesPageState extends ConsumerState<SourcesPage>
    with SingleTickerProviderStateMixin {
  late final _visitedTabs = <SourcesSection>{widget.tab};
  int _editorRevision = 0;
  int? _lastSourceId;
  String _monitorPlatform = 'telegram';

  late final _tabs = TabController(
    length: SourcesSection.values.length,
    vsync: this,
    initialIndex: widget.tab.index,
  );

  @override
  void didUpdateWidget(SourcesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _lastSourceId = int.tryParse(widget.editor ?? '') ?? _lastSourceId;
    if (oldWidget.tab != widget.tab) {
      _tabs.index = widget.tab.index;
      _visitedTabs.add(widget.tab);
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _closeEditor() {
    setState(() => _editorRevision++);
    if (widget.editor != null) context.go('/sources');
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = AppListDetailWorkspace.supportsSplit(
        context,
        availableSize: constraints.biggest,
      );
      final sources = widget.tab == SourcesSection.subscriptions
          ? ref.watch(discoverySourcesProvider)
          : null;
      final items = sources?.value;
      final defaultSource =
          items?.where((item) => item.id == _lastSourceId).firstOrNull ??
          items?.firstOrNull;
      final editor =
          widget.editor ?? (wide ? defaultSource?.id.toString() : null);
      final platform =
          widget.platform ??
          (wide && widget.tab == SourcesSection.accounts ? 'telegram' : null);
      final syncPlatform = widget.syncPlatform ?? 'zhihu';
      final selectedId =
          editor ??
          platform ??
          (wide
              ? widget.tab == SourcesSection.sync
                    ? 'sync-$syncPlatform'
                    : widget.tab == SourcesSection.monitoring
                    ? 'monitor-$_monitorPlatform'
                    : null
              : null);
      void closeAccount() => context.go(
        GoRouterState.of(context).uri.queryParameters['from'] == 'sync'
            ? '/sources/sync'
            : '/accounts',
      );
      return Scaffold(
        body: AppListDetailWorkspace(
          selectedId: selectedId,
          emptyDetail: WorkspacePlaceholder(
            loading: sources?.isLoading ?? false,
            label: sources?.hasError == true ? '来源加载失败' : '暂无订阅',
          ),
          onClose: widget.editor == null && widget.platform == null
              ? null
              : editor != null
              ? _closeEditor
              : closeAccount,
          list: _buildOverview(
            context,
            wide: wide,
            editor: editor,
            platform: platform,
          ),
          detailBuilder: (_, _, _) => editor != null
              ? _buildEditor(
                  context,
                  editor,
                  showBackButton: widget.editor != null,
                )
              : platform != null
              ? widget.platform != null
                    ? widget.accountDetail!
                    : AccountDetailPage(
                        platform: platform,
                        showBackButton: false,
                      )
              : widget.tab == SourcesSection.sync
              ? FavoritesSyncAutomationPanel(
                  initialPlatform: syncPlatform == 'all' ? null : syncPlatform,
                  showPlatformLinks: false,
                  showBackButton: false,
                )
              : Scaffold(
                  appBar: AppBar(
                    automaticallyImplyLeading: false,
                    title: Text(
                      _monitorPlatform == 'qq' ? 'QQ 会话' : 'Telegram 会话',
                    ),
                  ),
                  body: PushTab(
                    key: ValueKey(_monitorPlatform),
                    monitoringOnly: true,
                    platform: _monitorPlatform,
                  ),
                ),
        ),
      );
    },
  );

  Widget _buildEditor(
    BuildContext context,
    String editor, {
    required bool showBackButton,
  }) {
    void close() => _closeEditor();
    final sourceId = int.tryParse(editor);
    if (editor == 'new') {
      return SourceEditor(
        key: ValueKey(('new-source', _editorRevision)),
        showBackButton: showBackButton,
        onClose: close,
        onSave: (source) async {
          await ref
              .read(discoverySourcesProvider.notifier)
              .createSource(source);
          if (mounted) await ref.read(discoverySourcesProvider.future);
        },
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
                appBar: AppBar(
                  automaticallyImplyLeading: false,
                  leading: showBackButton ? BackButton(onPressed: close) : null,
                ),
                body: const Center(child: Text('来源已不存在')),
              );
            }
            return SourceEditor(
              key: ValueKey((source.id, _editorRevision)),
              showBackButton: showBackButton,
              initialSource: source,
              onClose: close,
              onSave: (updated) async {
                await ref
                    .read(discoverySourcesProvider.notifier)
                    .updateSource(
                      source.id,
                      name: updated.name,
                      enabled: updated.enabled,
                      config: updated.config,
                      syncIntervalMinutes: updated.syncIntervalMinutes,
                    );
                if (mounted) await ref.read(discoverySourcesProvider.future);
              },
              onDelete: () async {
                await ref
                    .read(discoverySourcesProvider.notifier)
                    .deleteSource(source.id);
                if (mounted) await ref.read(discoverySourcesProvider.future);
              },
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Scaffold(
            appBar: AppBar(
              automaticallyImplyLeading: false,
              leading: showBackButton ? BackButton(onPressed: close) : null,
            ),
            body: Center(
              child: Text(
                formatApiErrorMessage(error, fallbackMessage: '暂时无法读取来源'),
              ),
            ),
          ),
        );
  }

  PreferredSizeWidget _workspaceHeader(BuildContext context) => WorkspaceAppBar(
    tabs: WorkspaceTabs(
      controller: _tabs,
      labels: [for (final section in SourcesSection.values) section.label],
      onTap: (index) => context.go(SourcesSection.values[index].path),
    ),
  );

  Widget _buildOverview(
    BuildContext context, {
    required bool wide,
    required String? editor,
    required String? platform,
  }) => Scaffold(
    appBar: _workspaceHeader(context),
    body: IndexedStack(
      index: widget.tab.index,
      children: [
        _visitedTabs.contains(SourcesSection.subscriptions)
            ? TickerMode(
                enabled: widget.tab == SourcesSection.subscriptions,
                child: SubscriptionsView(
                  selectedId: int.tryParse(editor ?? ''),
                  onAdd: () => context.go('/sources?edit=new'),
                  onEdit: (source) => context.go('/sources?edit=${source.id}'),
                ),
              )
            : const SizedBox.shrink(),
        _visitedTabs.contains(SourcesSection.monitoring)
            ? TickerMode(
                enabled: widget.tab == SourcesSection.monitoring,
                child: wide
                    ? ListView(
                        children: [
                          for (final entry in {
                            'telegram': 'Telegram',
                            'qq': 'QQ',
                          }.entries)
                            ListTile(
                              title: Text(entry.value),
                              selected: _monitorPlatform == entry.key,
                              onTap: () =>
                                  setState(() => _monitorPlatform = entry.key),
                            ),
                        ],
                      )
                    : const PushTab(monitoringOnly: true),
              )
            : const SizedBox.shrink(),
        _visitedTabs.contains(SourcesSection.accounts)
            ? TickerMode(
                enabled: widget.tab == SourcesSection.accounts,
                child: AppPageBody(
                  maxWidth: AppPane.readableMaxWidth,
                  child: ConnectionTab(
                    accountsOnly: true,
                    selectedPlatform: platform,
                    onAccountSelected: wide
                        ? (platform) => context.go('/accounts/$platform')
                        : null,
                  ),
                ),
              )
            : const SizedBox.shrink(),
        _visitedTabs.contains(SourcesSection.sync)
            ? TickerMode(
                enabled: widget.tab == SourcesSection.sync,
                child: wide
                    ? FavoritesSyncPlatformList(
                        selectedPlatform: widget.syncPlatform ?? 'zhihu',
                        onSelected: (platform) =>
                            context.go('/sources/sync?platform=$platform'),
                      )
                    : FavoritesSyncAutomationPanel(
                        initialPlatform: widget.syncPlatform == 'all'
                            ? null
                            : widget.syncPlatform,
                      ),
              )
            : const SizedBox.shrink(),
      ],
    ),
  );
}
