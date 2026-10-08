import '../../layout/root_page_actions.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/widgets/predictive_back_dialog.dart';
import '../../core/layout/responsive_layout.dart';
import '../../core/network/sse_service.dart';
import '../../core/network/api_client.dart';
import '../../routing/app_navigation.dart';
import '../../theme/design_tokens.dart';
import 'models/distribution_rule.dart';
import 'providers/rule_editor_key_provider.dart';
import 'models/queue_item.dart';
import 'providers/distribution_rules_provider.dart';
import 'providers/bot_chats_provider.dart';
import 'providers/queue_provider.dart';
import '../dashboard/providers/dashboard_provider.dart' as dashboard;
import '../settings/providers/favorites_sync_provider.dart';
import '../settings/providers/settings_provider.dart';
import '../settings/utils/setting_value.dart';
import 'widgets/favorites_sync_automation_panel.dart';
import 'widgets/processing_automation_panel.dart';
import 'widgets/queue_content_list.dart';
import 'widgets/rule_list_tile.dart';
import '../../core/utils/toast.dart';
import '../../core/widgets/app_filter_menu.dart';

class AutomationPage extends ConsumerStatefulWidget {
  const AutomationPage({
    super.key,
    this.initialTab,
    this.highlightRunId,
    this.editorRouteKey,
    this.ruleId,
    this.creatingRule = false,
    this.configuration,
  });

  final String? initialTab;
  final String? highlightRunId;
  final ValueKey<String>? editorRouteKey;
  final int? ruleId;
  final bool creatingRule;
  final Widget? configuration;

  @override
  ConsumerState<AutomationPage> createState() => _AutomationPageState();
}

enum _AutomationSection { overview, sync, distribution, processing }

enum _DistributionDomainView { queue, history, rules }

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
    length: 3,
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
  Widget build(BuildContext context) => TabBar.secondary(
    controller: _controller,
    isScrollable: true,
    tabAlignment: TabAlignment.start,
    dividerColor: Colors.transparent,
    tabs: const [
      Tab(text: '推送'),
      Tab(text: '发送记录'),
      Tab(text: '配置'),
    ],
    onTap: (index) => widget.onChanged(_DistributionDomainView.values[index]),
  );
}

class _AutomationDomainEntry extends StatelessWidget {
  const _AutomationDomainEntry({
    required this.title,
    required this.status,
    required this.onOpen,
  });

  final String title;
  final String status;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
    title: Text(title, style: Theme.of(context).textTheme.titleMedium),
    subtitle: Text(status),
    trailing: const Icon(Icons.chevron_right_rounded),
    onTap: onOpen,
  );
}

class _AutomationPageState extends ConsumerState<AutomationPage> {
  late _AutomationSection _section;
  _DistributionDomainView _distributionView = _DistributionDomainView.queue;
  int? _selectedRuleId;
  StreamSubscription<SseEvent>? _sseSub;

  @override
  void initState() {
    super.initState();
    _section = _sectionFromTab(widget.initialTab);
    _distributionView = _distributionViewFromTab(widget.initialTab);
    _selectedRuleId = widget.ruleId;
    _bindRealtimeEvents();
    _scheduleQueueFilter();
  }

  @override
  void didUpdateWidget(AutomationPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ruleId != widget.ruleId ||
        oldWidget.creatingRule != widget.creatingRule) {
      _selectedRuleId = widget.ruleId;
      _distributionView = _DistributionDomainView.rules;
    }
    _scheduleQueueFilter();
    if (oldWidget.initialTab != widget.initialTab) {
      setState(() {
        _section = _sectionFromTab(widget.initialTab);
        _distributionView = _distributionViewFromTab(widget.initialTab);
      });
    }
  }

  void _scheduleQueueFilter() {
    if (_section != _AutomationSection.distribution) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncQueueFilter();
    });
  }

  QueueStatus get _queueStatus =>
      _distributionView == _DistributionDomainView.history
      ? QueueStatus.pushed
      : QueueStatus.willPush;

  void _syncQueueFilter() {
    if (widget.creatingRule) return;
    ref
        .read(queueFilterProvider.notifier)
        .setFilter(ruleId: _selectedRuleId, status: _queueStatus);
  }

  @override
  void dispose() {
    _sseSub?.cancel();
    super.dispose();
  }

  void _bindRealtimeEvents() {
    ref.read(sseServiceProvider.notifier);
    _sseSub?.cancel();
    _sseSub = SseEventBus().eventStream.listen((event) {
      if (!mounted) return;

      switch (event.type) {
        case 'queue_updated':
          ref.read(contentQueueProvider.notifier).softRefresh();
          ref.invalidate(queueStatsProvider(_selectedRuleId));
          ref.invalidate(dashboard.queueStatsProvider);
          break;
        case 'content_pushed':
        case 'distribution_push_success':
          ref.invalidate(botChatsProvider);
          ref.read(contentQueueProvider.notifier).softRefresh();
          ref.invalidate(queueStatsProvider(_selectedRuleId));
          break;
        case 'distribution_push_failed':
          ref.invalidate(queueStatsProvider(_selectedRuleId));
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: WindowMetrics.of(context).heightClass.isCompact
            ? 48
            : null,
        title: Text(
          _section == _AutomationSection.overview
              ? '自动化'
              : _sectionTitle(_section),
        ),
        actions: _section == _AutomationSection.overview
            ? const [RootPageActions()]
            : _section == _AutomationSection.distribution
            ? [PageAddButton(tooltip: '新建规则', onPressed: _openCreateRule)]
            : null,
        leading: _section == _AutomationSection.overview
            ? buildRootPageLeading(context)
            : const AppBackButton(fallback: '/automation'),
      ),
      body: _buildSectionBody(),
    );
  }

  _AutomationSection _sectionFromTab(String? tab) {
    return switch (tab) {
      'sync' => _AutomationSection.sync,
      'distribution' || 'history' || 'rules' => _AutomationSection.distribution,
      'processing' => _AutomationSection.processing,
      _ => _AutomationSection.overview,
    };
  }

  _DistributionDomainView _distributionViewFromTab(String? tab) {
    return switch (tab) {
      'history' => _DistributionDomainView.history,
      'rules' => _DistributionDomainView.rules,
      _ => _DistributionDomainView.queue,
    };
  }

  String _sectionTitle(_AutomationSection section) {
    return switch (section) {
      _AutomationSection.overview => '自动化',
      _AutomationSection.sync => '收藏同步',
      _AutomationSection.distribution => '分发',
      _AutomationSection.processing => '内容处理',
    };
  }

  Widget _buildSectionBody() {
    return switch (_section) {
      _AutomationSection.overview => _buildOverview(),
      _AutomationSection.sync => FavoritesSyncAutomationPanel(
        highlightRunId: widget.highlightRunId,
      ),
      _AutomationSection.distribution => _buildDistributionDomain(),
      _AutomationSection.processing => const ProcessingAutomationPanel(),
    };
  }

  Widget _buildOverview() {
    final queueStats = ref.watch(queueStatsProvider(null));
    final syncStatus = ref.watch(favoritesSyncStatusProvider);
    final processingStats = ref.watch(dashboard.queueStatsProvider);
    final diagnostics = ref.watch(dashboard.backgroundTaskDiagnosticsProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(queueStatsProvider(null));
        ref.invalidate(favoritesSyncStatusProvider);
        ref.invalidate(dashboard.queueStatsProvider);
        ref.invalidate(dashboard.backgroundTaskDiagnosticsProvider);
      },
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppPane.readableMaxWidth),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(vertical: 12),
            children: [
              _AutomationDomainEntry(
                title: '收藏同步',
                status: syncStatus.when(
                  data: (status) =>
                      '${status.enabledPlatforms.length} 个平台启用 · ${status.running ? '调度已启动' : '调度已停止'}',
                  loading: () => '正在读取同步状态…',
                  error: (_, _) => '同步状态读取失败，进入查看或重试',
                ),
                onOpen: () => context.go('/automation/sync'),
              ),
              _AutomationDomainEntry(
                title: '推送',
                status: queueStats.when(
                  data: (stats) =>
                      '待推送 ${stats['will_push']} · 已推送 ${stats['pushed']}',
                  loading: () => '正在读取队列…',
                  error: (_, _) => '队列读取失败，进入查看或重试',
                ),
                onOpen: () => context.go('/automation/distribution'),
              ),
              _AutomationDomainEntry(
                title: '内容处理',
                status: [
                  processingStats.when(
                    data: (stats) =>
                        '${stats.parse.processing} 处理中 · ${stats.parse.unprocessed} 待处理',
                    loading: () => '正在读取解析队列…',
                    error: (_, _) => '解析队列读取失败',
                  ),
                  diagnostics.when(
                    data: (data) => '解析失败 ${data.failedParseTasks.length}',
                    loading: () => '正在读取失败记录…',
                    error: (_, _) => '失败记录读取失败',
                  ),
                ].join(' · '),
                onOpen: () => context.go('/automation/processing'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDistributionDomain() => LayoutBuilder(
    builder: (context, constraints) {
      final wide = ResponsiveLayout.widthClassFor(
        constraints.maxWidth,
      ).supportsSupportingPane;
      if (!wide) return _buildDistributionContent(wide: false);
      return ColoredBox(
        color: _rulesBackgroundColor,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 280,
              child: Material(
                color: _rulesBackgroundColor,
                child: _buildRules(),
              ),
            ),
            Expanded(
              child: Material(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(24),
                ),
                clipBehavior: Clip.antiAlias,
                child: _buildDistributionContent(wide: true),
              ),
            ),
          ],
        ),
      );
    },
  );

  Color get _rulesBackgroundColor {
    final theme = Theme.of(context);
    return ElevationOverlay.applySurfaceTint(
      theme.colorScheme.surface,
      theme.appBarTheme.surfaceTintColor,
      theme.appBarTheme.scrolledUnderElevation ?? 0,
    );
  }

  Widget _buildRules({bool showAutomaticSending = false}) => ListView(
    padding: const EdgeInsets.all(12),
    children: [
      if (showAutomaticSending) _buildAutomaticSending(),
      DistributionNavigationTile(
        title: '全部内容',
        icon: Icons.inbox_outlined,
        selected: _selectedRuleId == null && !widget.creatingRule,
        onTap: () => _navigateRule('/automation/distribution'),
      ),
      const SizedBox(height: 20),
      ref
          .watch(distributionRulesProvider)
          .when(
            loading: () => const LinearProgressIndicator(),
            error: (error, _) => TextButton(
              onPressed: () => ref.invalidate(distributionRulesProvider),
              child: const Text('规则加载失败，重试'),
            ),
            data: (rules) => Column(
              children: [
                for (final rule in rules)
                  Padding(
                    key: ValueKey(rule.id),
                    padding: const EdgeInsets.only(bottom: 4),
                    child: RuleListTile(
                      backgroundColor: _rulesBackgroundColor,
                      rule: rule,
                      isSelected: rule.id == _selectedRuleId,
                      onTap: () => _openRule(rule),
                      onDelete: () => _confirmDeleteRule(rule),
                      onToggleEnabled: (value) =>
                          _toggleRuleEnabled(rule, value),
                    ),
                  ),
              ],
            ),
          ),
    ],
  );

  Widget _buildDistributionContent({required bool wide}) {
    final header = <Widget>[
      _DistributionDomainTabs(
        view: _distributionView,
        onChanged: (view) {
          setState(() => _distributionView = view);
          _syncQueueFilter();
        },
      ),
      if (!wide && _distributionView != _DistributionDomainView.rules)
        _buildRuleSelector(),
    ];
    final configuration = Stack(
      fit: StackFit.expand,
      children: [
        if (widget.configuration != null)
          Semantics(container: true, child: widget.configuration!),
        if (widget.editorRouteKey == null)
          if (wide)
            ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [_buildAutomaticSending()],
            )
          else
            Material(
              color: _rulesBackgroundColor,
              child: _buildRules(showAutomaticSending: true),
            ),
      ],
    );
    return Column(
      children: [
        header.first,
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              Offstage(
                offstage: _distributionView != _DistributionDomainView.rules,
                child: configuration,
              ),
              if (_distributionView != _DistributionDomainView.rules)
                _buildQueueList(header.skip(1).toList()),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAutomaticSending() => ref
      .watch(systemSettingsProvider)
      .when(
        data: (settings) => SwitchListTile(
          title: const Text('自动分发'),
          value:
              getSettingValue(settings, 'distribution_mode', 'auto') !=
              'paused',
          onChanged: (enabled) async {
            try {
              await ref
                  .read(systemSettingsProvider.notifier)
                  .updateSetting(
                    'distribution_mode',
                    enabled ? 'auto' : 'paused',
                    category: 'automation',
                  );
            } catch (error) {
              if (mounted) {
                Toast.show(
                  context,
                  formatApiErrorMessage(error, fallbackMessage: '保存失败'),
                  isError: true,
                );
              }
            }
          },
        ),
        loading: () => const LinearProgressIndicator(),
        error: (_, _) => TextButton(
          onPressed: () => ref.invalidate(systemSettingsProvider),
          child: const Text('自动分发设置加载失败，重试'),
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

  Widget _buildRuleSelector() {
    return ref
        .watch(distributionRulesProvider)
        .when(
          loading: () => const LinearProgressIndicator(),
          error: (error, _) => Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              formatApiErrorMessage(error, fallbackMessage: '规则加载失败'),
            ),
          ),
          data: (rules) {
            final selected = rules
                .where((rule) => rule.id == _selectedRuleId)
                .firstOrNull;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: AppFilterMenu(
                      label: '规则筛选',
                      value: selected?.id.toString() ?? 'all',
                      options: {
                        'all': '全部内容',
                        for (final rule in rules) rule.id.toString(): rule.name,
                      },
                      onSelected: (value) {
                        final ruleId = value == 'all' ? null : int.parse(value);
                        final rule = rules
                            .where((rule) => rule.id == ruleId)
                            .firstOrNull;
                        if (rule == null) {
                          _navigateRule('/automation/distribution');
                        } else {
                          _openRule(rule);
                        }
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
  }

  Widget _buildQueueList(List<Widget> header) {
    if (widget.creatingRule) return const SizedBox.expand();
    final queueAsync = ref.watch(contentQueueProvider);
    final filter = ref.watch(queueFilterProvider);

    if (filter.ruleId != _selectedRuleId || filter.status != _queueStatus) {
      return _buildDistributionState(
        header,
        const Center(child: CircularProgressIndicator()),
      );
    }
    return queueAsync.when(
      loading: () => _buildDistributionState(
        header,
        const Center(child: CircularProgressIndicator()),
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
                onPressed: () => ref.invalidate(contentQueueProvider),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      ),
      data: (response) {
        return QueueContentList(
          key: ValueKey((filter.ruleId, filter.status)),
          animateEntries: _distributionView == _DistributionDomainView.history,
          header: header,
          items: response.items,
          currentStatus: filter.status,
          onLoadMore: response.hasMore
              ? ref.read(contentQueueProvider.notifier).loadMore
              : null,
          onRefresh: () {
            ref.invalidate(contentQueueProvider);
            ref.invalidate(queueStatsProvider(_selectedRuleId));
          },
        );
      },
    );
  }

  Future<void> _navigateRule(String path) async {
    if (GoRouterState.of(context).uri.path == path) {
      setState(
        () => _distributionView = widget.editorRouteKey == null
            ? _DistributionDomainView.queue
            : _DistributionDomainView.rules,
      );
      _syncQueueFilter();
      return;
    }
    final key = widget.editorRouteKey;
    if (key != null &&
        !(await (ref
                .read(ruleEditorKeyProvider(key))
                .currentState
                ?.confirmExit() ??
            Future.value(true)))) {
      return;
    }
    if (mounted) context.go(path);
  }

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
      builder: (ctx) => PredictiveBackDialog(
        child: AlertDialog(
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
                  if (_selectedRuleId == rule.id) {
                    setState(() => _selectedRuleId = null);
                    ref.read(queueFilterProvider.notifier).setRuleId(null);
                  }
                  if (mounted) {
                    ref.invalidate(contentQueueProvider);
                    ref.invalidate(queueStatsProvider);
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
