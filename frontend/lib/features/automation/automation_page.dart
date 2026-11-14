import '../../routing/navigation_scope.dart';
import '../../routing/content_route_extra.dart';
import '../../routing/page_origin.dart';
import '../../core/layout/app_page_body.dart';
import '../../core/layout/responsive_layout.dart';
import '../../core/widgets/app_setting_group.dart';
import '../../core/widgets/app_choice_segments.dart';
import '../../core/widgets/workspace_tabs.dart';
import '../collection/content_detail_page.dart';
import '../collection/models/content.dart';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/app_list_detail_workspace.dart';
import '../../core/network/api_client.dart';
import '../../theme/design_tokens.dart';
import 'models/distribution_rule.dart';
import 'models/queue_item.dart';
import 'providers/distribution_rules_provider.dart';
import 'providers/queue_provider.dart';
import '../settings/providers/settings_provider.dart';
import '../settings/utils/setting_value.dart';
import 'widgets/queue_content_list.dart';
import 'widgets/rule_list_tile.dart';
import '../settings/presentation/tabs/push_tab.dart';
import '../settings/presentation/widgets/setting_components.dart';
import '../../core/utils/toast.dart';

class DistributionPage extends ConsumerStatefulWidget {
  const DistributionPage({
    super.key,
    this.initialTab,
    this.unsentOnly = false,
    this.editorRouteKey,
    this.ruleId,
    this.filterRuleId,
    this.selectedContentId,
    this.creatingRule = false,
    this.configuration,
  });

  static void showTargets(BuildContext context) {
    var platform = 'telegram';
    showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Dialog(
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * .8,
              child: Column(
                children: [
                  ListTile(
                    title: const Text('推送目标'),
                    trailing: IconButton(
                      tooltip: '关闭',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ),
                  Expanded(
                    child: _PushTargets(
                      platform: platform,
                      onPlatformChanged: (value) =>
                          setState(() => platform = value),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  final String? initialTab;
  final bool unsentOnly;
  final ValueKey<String>? editorRouteKey;
  final int? ruleId;
  final int? filterRuleId;
  final int? selectedContentId;
  final bool creatingRule;
  final Widget? configuration;

  @override
  ConsumerState<DistributionPage> createState() => _DistributionPageState();
}

enum _DistributionDomainView { queue, history, rules, targets }

class _PushTargets extends StatelessWidget {
  const _PushTargets({required this.platform, required this.onPlatformChanged});

  final String platform;
  final ValueChanged<String> onPlatformChanged;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: AppChoiceSegments<String>(
          options: const {'telegram': 'Telegram', 'qq': 'QQ'},
          selected: {platform},
          onChanged: (values) => onPlatformChanged(values.single),
        ),
      ),
      Expanded(
        child: PushTab(
          key: ValueKey(platform),
          targetsOnly: true,
          platform: platform,
        ),
      ),
    ],
  );
}

class _DistributionDomainTabs extends StatefulWidget {
  const _DistributionDomainTabs({required this.view, required this.onChanged});

  final _DistributionDomainView view;
  final ValueChanged<_DistributionDomainView> onChanged;

  @override
  State<_DistributionDomainTabs> createState() =>
      _DistributionDomainTabsState();
}

class _DistributionDomainTabsState extends State<_DistributionDomainTabs>
    with SingleTickerProviderStateMixin {
  late final TabController _controller = TabController(
    length: 4,
    initialIndex: widget.view.index,
    vsync: this,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The parent queue page stays mounted beneath history. Restore its own
    // selection when it becomes current again after browser or system back.
    if (ModalRoute.isCurrentOf(context) ?? true) {
      _controller.index = widget.view.index;
    }
  }

  @override
  void didUpdateWidget(covariant _DistributionDomainTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.view != widget.view) _controller.index = widget.view.index;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => WorkspaceTabs(
    controller: _controller,
    labels: const ['待发送', '发送记录', '规则', '目标'],
    onTap: (index) => widget.onChanged(_DistributionDomainView.values[index]),
  );
}

class _DistributionPageState extends ConsumerState<DistributionPage> {
  _DistributionDomainView get _distributionView =>
      _distributionViewFromTab(widget.initialTab);
  int? get _selectedRuleId => widget.filterRuleId;
  ShareCard? _preview;
  final _lastContentIds = <_DistributionDomainView, int>{};
  String _targetPlatform = 'telegram';
  int? _openingDefaultRule;

  void _showView(_DistributionDomainView view) {
    final path = switch (view) {
      _DistributionDomainView.queue => '/automation/distribution',
      _DistributionDomainView.history => '/automation/distribution/history',
      _DistributionDomainView.rules => '/automation/distribution/rules',
      _DistributionDomainView.targets => '/automation/distribution/targets',
    };
    final isQueue =
        view == _DistributionDomainView.queue ||
        view == _DistributionDomainView.history;
    context.go(
      Uri(
        path: path,
        queryParameters: isQueue && _selectedRuleId != null
            ? {'rule': '$_selectedRuleId'}
            : null,
      ).toString(),
    );
  }

  QueueStatus get _queueStatus =>
      _distributionView == _DistributionDomainView.history
      ? (widget.unsentOnly ? QueueStatus.filtered : QueueStatus.history)
      : QueueStatus.willPush;

  QueueFilter get _filter => (status: _queueStatus, ruleId: _selectedRuleId);

  void _openContent(QueueItem item, BuildContext sourceContext) {
    _lastContentIds[_distributionView] = item.contentId;
    _preview = ShareCard(
      id: item.contentId,
      platform: item.sourcePlatform ?? item.platform,
      url: '',
      title: item.title,
      mediaAssets: item.mediaAssets,
    );
    if (!AppListDetailWorkspace.supportsSplit(context)) {
      context.push(
        '/collection/${item.contentId}',
        extra: ContentRouteExtra(
          preview: _preview!,
          origin: PageOrigin(sourceContext),
        ),
      );
      return;
    }
    final uri = GoRouterState.of(context).uri;
    final location = uri
        .replace(
          queryParameters: {
            ...uri.queryParametersAll,
            'item': ['${item.contentId}'],
          },
        )
        .toString();
    widget.selectedContentId == null
        ? context.go(location)
        : context.replace(location);
  }

  void _closeReader() {
    if (widget.selectedContentId == null) return;
    final uri = GoRouterState.of(context).uri;
    final query = {...uri.queryParametersAll}..remove('item');
    context.replace(uri.replace(queryParameters: query).toString());
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => _buildWorkspace(context, box.biggest),
  );

  Widget _buildWorkspace(BuildContext context, Size availableSize) {
    final wide = AppListDetailWorkspace.supportsSplit(
      context,
      availableSize: availableSize,
    );
    final isQueue =
        _distributionView == _DistributionDomainView.queue ||
        _distributionView == _DistributionDomainView.history;
    final queue = isQueue ? ref.watch(contentQueueProvider(_filter)) : null;
    final items = queue?.value?.items;
    final defaultItem =
        items
            ?.where(
              (item) => item.contentId == _lastContentIds[_distributionView],
            )
            .firstOrNull ??
        items?.firstOrNull;
    final rules = _distributionView == _DistributionDomainView.rules
        ? ref.watch(distributionRulesProvider)
        : null;
    final defaultRule = wide ? rules?.value?.firstOrNull : null;
    final editorKey = widget.editorRouteKey;
    final autoRuleId = widget.editorRouteKey == null ? defaultRule?.id : null;
    if (autoRuleId != null &&
        _openingDefaultRule != autoRuleId &&
        TickerMode.valuesOf(context).enabled &&
        AppNavigationScope.isActiveOf(context)) {
      _openingDefaultRule = autoRuleId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            widget.editorRouteKey != null ||
            _distributionView != _DistributionDomainView.rules ||
            !TickerMode.valuesOf(context).enabled ||
            !AppNavigationScope.isActiveOf(context)) {
          _openingDefaultRule = null;
          return;
        }
        context.replace('/automation/distribution/rules/$autoRuleId');
      });
    }
    if (editorKey != null) _openingDefaultRule = null;
    final configuration = widget.configuration;
    final targets =
        wide && _distributionView == _DistributionDomainView.targets;
    final creating = widget.ruleId == null;
    final contentId =
        widget.selectedContentId ?? (wide ? defaultItem?.contentId : null);
    final preview = _preview?.id == contentId ? _preview : null;
    return AppListDetailWorkspace(
      onClose: editorKey != null
          ? () => context.go('/automation/distribution/rules')
          : widget.selectedContentId == null
          ? null
          : _closeReader,
      selectedId:
          editorKey ??
          (targets
              ? ('target', _targetPlatform)
              : contentId == null
              ? null
              : ('content', contentId)),
      emptyDetail: WorkspacePlaceholder(
        loading:
            autoRuleId != null ||
            (queue?.isLoading ?? false) ||
            (rules?.isLoading ?? false),
        label: (queue?.hasError ?? false) || (rules?.hasError ?? false)
            ? '加载失败'
            : '暂无详情',
      ),
      list: Scaffold(
        appBar: WorkspaceAppBar(
          toolbarHeight: WindowMetrics.of(context).toolbarHeight,
          tabs: _DistributionDomainTabs(
            view: _distributionView,
            onChanged: _showView,
          ),
        ),
        body: targets
            ? ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  AppSettingGroup(
                    children: [
                      for (final platform in {
                        'telegram': 'Telegram',
                        'qq': 'QQ',
                      }.entries)
                        ListTile(
                          leading: Icon(
                            platform.key == 'telegram'
                                ? Icons.send_outlined
                                : Icons.chat_bubble_outline_rounded,
                          ),
                          shape: const RoundedRectangleBorder(
                            borderRadius: AppShape.cardMediaBorder,
                          ),
                          title: Text(platform.value),
                          selected: _targetPlatform == platform.key,
                          onTap: () =>
                              setState(() => _targetPlatform = platform.key),
                        ),
                    ],
                  ),
                ],
              )
            : _buildDistributionContent(
                contentId,
                selectedRuleId: widget.ruleId ?? autoRuleId,
              ),
      ),
      detailBuilder: (deferBody, focused, toggleFocus) => targets
          ? Scaffold(
              appBar: AppBar(
                automaticallyImplyLeading: false,
                title: Text(_targetPlatform == 'qq' ? 'QQ 目标' : 'Telegram 目标'),
              ),
              body: PushTab(
                key: ValueKey(_targetPlatform),
                targetsOnly: true,
                platform: _targetPlatform,
              ),
            )
          : editorKey != null
          ? Scaffold(
              appBar: AppBar(
                automaticallyImplyLeading: false,
                leading: BackButton(
                  onPressed: () => context.go('/automation/distribution/rules'),
                ),
                title: Text(creating ? '新建规则' : '编辑规则'),
              ),
              body: Semantics(container: true, child: configuration),
            )
          : ContentDetailPage(
              contentId: contentId!,
              preview: preview,
              deferBody: deferBody,
              focused: focused,
              onToggleFocus: toggleFocus,
              showBackButton: widget.selectedContentId != null,
              onClose: _closeReader,
            ),
    );
  }

  _DistributionDomainView _distributionViewFromTab(String? tab) =>
      switch (tab) {
        'history' => _DistributionDomainView.history,
        'rules' => _DistributionDomainView.rules,
        'targets' => _DistributionDomainView.targets,
        _ => _DistributionDomainView.queue,
      };

  Widget _buildRules(int? selectedRuleId) => AppPageBody(
    maxWidth: AppPane.readableMaxWidth,
    child: ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _buildAutomaticSending(),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton.tonalIcon(
              onPressed: _openCreateRule,
              icon: const Icon(Icons.add),
              label: const Text('新建规则'),
            ),
          ),
        ),
        ref
            .watch(distributionRulesProvider)
            .when(
              loading: () => const LinearProgressIndicator(),
              error: (_, _) => TextButton(
                onPressed: () => ref.invalidate(distributionRulesProvider),
                child: const Text('规则加载失败，重试'),
              ),
              data: (rules) => Column(
                children: [
                  for (final rule in rules)
                    RuleListTile(
                      key: ValueKey(rule.id),
                      rule: rule,
                      isSelected: rule.id == selectedRuleId,
                      onTap: () => _openRule(rule),
                      onDelete: () => _confirmDeleteRule(rule),
                      onToggleEnabled: (value) =>
                          _toggleRuleEnabled(rule, value),
                    ),
                ],
              ),
            ),
      ],
    ),
  );

  Widget _buildDistributionContent(
    int? activeContentId, {
    int? selectedRuleId,
  }) {
    return switch (_distributionView) {
      _DistributionDomainView.rules => _buildRules(selectedRuleId),
      _DistributionDomainView.targets => _PushTargets(
        platform: _targetPlatform,
        onPlatformChanged: (value) => setState(() => _targetPlatform = value),
      ),
      _ => AppPageBody(
        maxWidth: AppPane.readableMaxWidth,
        child: _buildQueueList(activeContentId),
      ),
    };
  }

  Widget _buildAutomaticSending() => ref
      .watch(systemSettingsProvider)
      .when(
        data: (settings) => SettingSwitch(
          title: const Text('自动发送'),
          value:
              getSettingValue(settings, 'distribution_mode', 'auto') !=
              'paused',
          onChanged: (enabled) => ref
              .read(systemSettingsProvider.notifier)
              .updateSetting(
                'distribution_mode',
                enabled ? 'auto' : 'paused',
                category: 'automation',
              ),
        ),
        loading: () => const LinearProgressIndicator(),
        error: (_, _) => TextButton(
          onPressed: () => ref.invalidate(systemSettingsProvider),
          child: const Text('自动发送设置加载失败，重试'),
        ),
      );

  Widget _buildDistributionState(List<Widget> header, Widget state) =>
      CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          for (final section in header) SliverToBoxAdapter(child: section),
          SliverFillRemaining(hasScrollBody: false, child: state),
        ],
      );

  void _filterQueue(int? ruleId, bool unsentOnly) {
    context.go(
      Uri(
        path: _distributionView == _DistributionDomainView.history
            ? '/automation/distribution/history'
            : '/automation/distribution',
        queryParameters: {
          if (ruleId != null) 'rule': '$ruleId',
          if (unsentOnly) 'status': 'filtered',
        },
      ).toString(),
    );
  }

  Widget _queueFilters() {
    final isHistory = _distributionView == _DistributionDomainView.history;
    final rules = ref.watch(distributionRulesProvider).value ?? [];
    final selected = rules
        .where((rule) => rule.id == _selectedRuleId)
        .firstOrNull;
    if (rules.isEmpty && _selectedRuleId == null && !isHistory) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (rules.isNotEmpty || _selectedRuleId != null)
            MenuAnchor(
              menuChildren: [
                MenuItemButton(
                  onPressed: () => _filterQueue(null, widget.unsentOnly),
                  child: const Text('全部规则'),
                ),
                for (final rule in rules)
                  MenuItemButton(
                    onPressed: () => _filterQueue(rule.id, widget.unsentOnly),
                    child: Text(rule.name),
                  ),
              ],
              builder: (context, controller, _) => ActionChip(
                avatar: const Icon(Icons.filter_list_rounded, size: 18),
                label: Text(
                  selected?.name ?? (_selectedRuleId == null ? '规则' : '已选规则'),
                ),
                tooltip: '按推送规则筛选',
                onPressed: () =>
                    controller.isOpen ? controller.close() : controller.open(),
              ),
            ),
          if (isHistory)
            FilterChip(
              label: const Text('未发送'),
              selected: widget.unsentOnly,
              onSelected: (selected) => _filterQueue(_selectedRuleId, selected),
            ),
        ],
      ),
    );
  }

  Widget _buildQueueList(int? activeContentId) {
    final filter = _filter;
    final provider = contentQueueProvider(filter);
    final queueAsync = ref.watch(provider);
    final hasFilter = _selectedRuleId != null || widget.unsentOnly;
    final header = [
      if (hasFilter || (queueAsync.value?.items.isNotEmpty ?? false))
        _queueFilters(),
    ];
    return queueAsync.when(
      loading: () => _buildDistributionState(
        header,
        const WorkspacePlaceholder(loading: true, label: ''),
      ),
      error: (e, st) => _buildDistributionState(
        header,
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline_rounded,
                size: 48,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(formatApiErrorMessage(e, fallbackMessage: '加载失败，请重试')),
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: () => ref.invalidate(provider),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      ),
      data: (response) {
        return QueueContentList(
          key: ValueKey((filter.ruleId, filter.status)),
          header: header,
          items: response.items,
          activeContentId: activeContentId,
          onOpen: _openContent,
          filter: filter,
          onEmptyAction: hasFilter
              ? () => _filterQueue(null, false)
              : _distributionView == _DistributionDomainView.queue
              ? () => _showView(_DistributionDomainView.history)
              : () => context.go('/collection'),
          emptyActionLabel: hasFilter
              ? '清除筛选'
              : _distributionView == _DistributionDomainView.queue
              ? '查看发送记录'
              : '打开收藏库',
          onLoadMore: response.hasMore
              ? ref.read(provider.notifier).loadMore
              : null,
        );
      },
    );
  }

  void _navigateRule(String path) => context.go(path);

  void _openCreateRule() {
    _navigateRule('/automation/distribution/rules/new');
  }

  void _openRule(DistributionRule rule) {
    _navigateRule('/automation/distribution/rules/${rule.id}');
  }

  void _confirmDeleteRule(DistributionRule rule) {
    showDialog(
      context: context,
      animationStyle: MediaQuery.disableAnimationsOf(context)
          ? AnimationStyle.noAnimation
          : null,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('删除规则“${rule.name}”及其待发送项？已发送记录仍保留。'),
        shape: RoundedRectangleBorder(borderRadius: AppShape.sheetBorder),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await ref
                    .read(distributionRulesProvider.notifier)
                    .deleteRule(rule.id);
                if (widget.ruleId == rule.id && mounted) {
                  context.go('/automation/distribution/rules');
                }
                if (mounted) {
                  ref.invalidate(contentQueueProvider);
                  Toast.show(context, '规则已删除');
                }
              } catch (e) {
                if (mounted) {
                  Toast.show(
                    context,
                    formatApiErrorMessage(e, fallbackMessage: '删除失败，请重试'),
                    isError: true,
                  );
                }
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleRuleEnabled(DistributionRule rule, bool enabled) async {
    try {
      await ref
          .read(distributionRulesProvider.notifier)
          .toggleEnabled(rule.id, enabled);
    } catch (e) {
      if (mounted) {
        Toast.show(
          context,
          formatApiErrorMessage(e, fallbackMessage: '操作失败，请重试'),
          isError: true,
        );
      }
    }
  }
}
