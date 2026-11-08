import '../../core/layout/app_page_body.dart';
import '../../core/layout/app_list_detail_workspace.dart';
import '../../core/network/api_client.dart';
import '../discovery/providers/discovery_sources_provider.dart';
import '../accounts/account_detail_page.dart';
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
import '../settings/providers/platform_health_provider.dart';

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
    this.highlightRunId,
    this.editor,
    this.platform,
    this.accountDetail,
  });
  final String? editor;
  final String? platform;
  final Widget? accountDetail;
  final SourcesSection tab;
  final String? highlightRunId;

  @override
  ConsumerState<SourcesPage> createState() => _SourcesPageState();
}

class _SourcesPageState extends ConsumerState<SourcesPage>
    with SingleTickerProviderStateMixin {
  late final _visitedTabs = <SourcesSection>{widget.tab};
  late int? _lastSourceId = int.tryParse(widget.editor ?? '');
  late String? _lastAccount = _isMessageAccount(widget.platform)
      ? widget.platform
      : null;
  int _editorRevision = 0;

  static bool _isMessageAccount(String? platform) =>
      platform == 'telegram' || platform == 'qq';
  late final _tabs = TabController(
    length: SourcesSection.values.length,
    vsync: this,
    initialIndex: widget.tab.index,
  );

  @override
  void didUpdateWidget(SourcesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final sourceId = int.tryParse(widget.editor ?? '');
    if (sourceId != null) _lastSourceId = sourceId;
    if (_isMessageAccount(widget.platform)) _lastAccount = widget.platform;
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
      var editor = widget.editor;
      if (editor == null &&
          widget.tab == SourcesSection.subscriptions &&
          wide) {
        final sources = ref.watch(discoverySourcesProvider).value;
        if (sources != null && sources.isNotEmpty) {
          final remembered = sources
              .where((source) => source.id == _lastSourceId)
              .firstOrNull;
          _lastSourceId = remembered?.id ?? sources.first.id;
          editor = '$_lastSourceId';
        }
      }
      final explicitAccount = _isMessageAccount(widget.platform);
      final platform = explicitAccount
          ? widget.platform
          : widget.tab == SourcesSection.accounts && wide
          ? _lastAccount ?? 'telegram'
          : null;
      final selectedId = editor ?? platform;
      final explicitSelection = widget.editor != null || explicitAccount;
      void closeAccount() => context.go(
        GoRouterState.of(context).uri.queryParameters['from'] == 'sync'
            ? '/sources/sync'
            : '/accounts',
      );
      return Scaffold(
        appBar: wide ? _workspaceHeader(context) : null,
        body: AppListDetailWorkspace(
          selectedId: selectedId,
          onClose: !explicitSelection
              ? null
              : widget.editor != null
              ? _closeEditor
              : closeAccount,
          list: _buildOverview(
            context,
            wide: wide,
            editor: editor,
            platform: widget.platform ?? platform,
          ),
          detailBuilder: (_, _, _) => editor != null
              ? _buildEditor(
                  context,
                  editor,
                  showBackButton: widget.editor != null,
                )
              : explicitAccount
              ? widget.accountDetail!
              : AccountDetailPage(platform: platform!, showBackButton: false),
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
    title: '来源',
    actions: [
      if (widget.tab == SourcesSection.accounts)
        IconButton(
          tooltip: '刷新账号状态',
          onPressed: () => ref.invalidate(platformHealthProvider),
          icon: const Icon(Icons.refresh_rounded),
        ),
    ],
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
    appBar: wide ? null : _workspaceHeader(context),
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
                child: const PushTab(monitoringOnly: true),
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
                  ),
                ),
              )
            : const SizedBox.shrink(),
        _visitedTabs.contains(SourcesSection.sync)
            ? TickerMode(
                enabled: widget.tab == SourcesSection.sync,
                child: FavoritesSyncAutomationPanel(
                  highlightRunId: widget.highlightRunId,
                ),
              )
            : const SizedBox.shrink(),
      ],
    ),
  );
}
