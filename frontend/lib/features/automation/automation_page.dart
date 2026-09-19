import '../../layout/root_page_actions.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../core/widgets/predictive_back_dialog.dart';
import '../../core/layout/responsive_layout.dart';
import '../../core/network/sse_service.dart';
import '../../core/network/api_client.dart';
import '../../theme/design_tokens.dart';
import '../../routing/app_navigation.dart';
import 'models/distribution_rule.dart';
import 'models/pushed_record.dart';
import 'models/queue_item.dart';
import 'providers/distribution_rules_provider.dart';
import 'providers/pushed_records_provider.dart';
import 'providers/bot_chats_provider.dart';
import 'providers/queue_provider.dart';
import '../dashboard/providers/dashboard_provider.dart' as dashboard;
import '../settings/providers/favorites_sync_provider.dart';
import '../settings/providers/settings_provider.dart';
import '../settings/utils/setting_value.dart';
import 'widgets/pushed_record_tile.dart';
import 'widgets/favorites_sync_automation_panel.dart';
import 'widgets/processing_automation_panel.dart';
import 'widgets/queue_content_list.dart';
import 'widgets/delivery_review_dialog.dart';
import 'widgets/rule_list_tile.dart';
import '../../core/utils/toast.dart';
import '../../core/widgets/app_filter_menu.dart';

class AutomationPage extends ConsumerStatefulWidget {
  const AutomationPage({
    super.key,
    this.initialTab,
    this.highlightRunId,
    this.reviewItemId,
  });

  final String? initialTab;
  final String? highlightRunId;
  final int? reviewItemId;

  @override
  ConsumerState<AutomationPage> createState() => _AutomationPageState();
}

enum _AutomationSection { overview, sync, distribution, processing }

enum _DistributionDomainView { queue, history }

class _DistributionDomainTabs extends StatefulWidget {
  const _DistributionDomainTabs({required this.view});

  final _DistributionDomainView view;

  @override
  State<_DistributionDomainTabs> createState() =>
      _DistributionDomainTabsState();
}

class _DistributionDomainTabsState extends State<_DistributionDomainTabs>
    with SingleTickerProviderStateMixin {
  late final TabController _controller = TabController(
    length: 2,
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
      Tab(text: '队列与规则'),
      Tab(text: '推送历史'),
    ],
    onTap: (index) => context.go(
      index == _DistributionDomainView.history.index
          ? '/automation/distribution/history'
          : '/automation/distribution',
    ),
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
  final _queueListKey = GlobalKey();
  StreamSubscription<SseEvent>? _sseSub;
  DateTime? _lastToastAt;

  @override
  void initState() {
    super.initState();
    _section = _sectionFromTab(widget.initialTab);
    _distributionView = _distributionViewFromTab(widget.initialTab);
    _bindRealtimeEvents();
    _openDeliveryReview();
  }

  void _openDeliveryReview() {
    final itemId = widget.reviewItemId;
    if (itemId == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(queueFilterProvider.notifier).setStatus(QueueStatus.filtered);
      showDeliveryReview(context, ref, itemId);
    });
  }

  @override
  void didUpdateWidget(AutomationPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reviewItemId != widget.reviewItemId) _openDeliveryReview();
    if (oldWidget.initialTab != widget.initialTab) {
      setState(() {
        _section = _sectionFromTab(widget.initialTab);
        _distributionView = _distributionViewFromTab(widget.initialTab);
      });
    }
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
          ref.invalidate(pushedRecordsProvider);
          ref.invalidate(queueStatsProvider(_selectedRuleId));
          _maybeToast('推送成功，列表已实时更新');
          break;
        case 'distribution_push_failed':
          ref.invalidate(queueStatsProvider(_selectedRuleId));
          _maybeToast('有推送失败，请在推送历史查看详情');
          break;
      }
    });
  }

  void _maybeToast(String message) {
    final now = DateTime.now();
    if (_lastToastAt != null &&
        now.difference(_lastToastAt!) < const Duration(seconds: 2)) {
      return;
    }
    _lastToastAt = now;
    Toast.show(context, message);
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
            : null,
        leading: _section == _AutomationSection.overview
            ? null
            : const AppBackButton(fallback: '/automation'),
      ),
      body: _buildSectionBody(),
    );
  }

  _AutomationSection _sectionFromTab(String? tab) {
    return switch (tab) {
      'sync' => _AutomationSection.sync,
      'distribution' || 'history' => _AutomationSection.distribution,
      'processing' => _AutomationSection.processing,
      _ => _AutomationSection.overview,
    };
  }

  _DistributionDomainView _distributionViewFromTab(String? tab) {
    return switch (tab) {
      'history' => _DistributionDomainView.history,
      _ => _DistributionDomainView.queue,
    };
  }

  String _sectionTitle(_AutomationSection section) {
    return switch (section) {
      _AutomationSection.overview => '自动化',
      _AutomationSection.sync => '收藏同步',
      _AutomationSection.distribution => '分发',
      _AutomationSection.processing => '解析 / 后处理',
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
                title: '分发',
                status: queueStats.when(
                  data: (stats) =>
                      '待推送 ${stats['will_push']} · 已推送 ${stats['pushed']}',
                  loading: () => '正在读取队列…',
                  error: (_, _) => '队列读取失败，进入查看或重试',
                ),
                onOpen: () => context.go('/automation/distribution'),
              ),
              _AutomationDomainEntry(
                title: '解析 / 后处理',
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

  Widget _buildDistributionDomain() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final short = WindowMetrics.fromSize(
          constraints.biggest,
        ).isShortLandscape;
        final wide = ResponsiveLayout.widthClassFor(
          constraints.maxWidth,
        ).supportsSupportingPane;
        final header = <Widget>[
          _buildDistributionHeader(short),
          if (_distributionView == _DistributionDomainView.queue) ...[
            if (!wide) _buildRuleSelector(),
            _buildStatusTabs(),
          ],
        ];
        final content = _distributionView == _DistributionDomainView.queue
            ? _buildQueueList(header)
            : _buildHistoryTab(header);
        if (!wide || _distributionView == _DistributionDomainView.history) {
          return content;
        }
        return Row(
          children: [
            SizedBox(
              width: AppPane.supportingWidth,
              child: _buildRuleSidebar(),
            ),
            Expanded(child: content),
          ],
        );
      },
    );
  }

  Widget _buildDistributionHeader(bool short) {
    final policy = ref
        .watch(systemSettingsProvider)
        .when(
          data: (settings) {
            final enabled =
                getSettingValue(settings, 'distribution_mode', 'auto') !=
                'paused';
            void change(bool value) => ref
                .read(systemSettingsProvider.notifier)
                .updateSetting(
                  'distribution_mode',
                  value ? 'auto' : 'paused',
                  category: 'automation',
                );
            if (short) {
              return MergeSemantics(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('自动分发'),
                    const SizedBox(width: 8),
                    Switch.adaptive(value: enabled, onChanged: change),
                  ],
                ),
              );
            }
            return SwitchListTile.adaptive(
              title: const Text('自动分发'),
              subtitle: const Text('暂停后停止新的自动发送，仍可审核队列'),
              contentPadding: EdgeInsets.zero,
              value: enabled,
              onChanged: change,
            );
          },
          loading: () => const LinearProgressIndicator(),
          error: (_, _) => const Text('分发策略暂时无法读取'),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final tabs = _DistributionDomainTabs(view: _distributionView);
          if (short &&
              constraints.maxWidth >=
                  MediaQuery.textScalerOf(context).scale(320)) {
            return Row(
              children: [
                policy,
                const SizedBox(width: 24),
                Expanded(child: tabs),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [policy, tabs],
          );
        },
      ),
    );
  }

  Widget _buildDistributionState(List<Widget> header, Widget state) =>
      CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          for (final section in header) SliverToBoxAdapter(child: section),
          SliverFillRemaining(hasScrollBody: false, child: state),
        ],
      );

  Widget _buildRuleSidebar() {
    final rulesAsync = ref.watch(distributionRulesProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: colorScheme.surfaceContainerLow,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 12, 12),
            child: Row(
              children: [
                Icon(Icons.rule_rounded, size: 20, color: colorScheme.primary),
                const SizedBox(width: 12),
                Text(
                  '分发规则',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton.filledTonal(
                  icon: const Icon(Icons.add_rounded, size: 20),
                  onPressed: _openCreateRule,
                  tooltip: '新建规则',
                ),
              ],
            ),
          ),
          Expanded(
            child: rulesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, st) => Center(
                child: Text(
                  formatApiErrorMessage(e, fallbackMessage: '加载失败，请重试'),
                ),
              ),
              data: (rules) => _buildRuleList(rules),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRuleList(List<DistributionRule> rules) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        _buildAllContentTile(),
        const SizedBox(height: 16),
        Row(
          children: [
            const Expanded(child: Divider()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                '自定义规则',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.outline,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const Expanded(child: Divider()),
          ],
        ),
        const SizedBox(height: 16),
        if (rules.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text('暂无自定义规则'),
          )
        else
          ...rules.asMap().entries.map(
            (entry) => RuleListTile(
              rule: entry.value,
              isSelected: _selectedRuleId == entry.value.id,
              onTap: () {
                setState(() => _selectedRuleId = entry.value.id);
                ref
                    .read(queueFilterProvider.notifier)
                    .setRuleId(entry.value.id);
              },
              onEdit: () => _openRule(entry.value),
              onDelete: () => _confirmDeleteRule(entry.value),
              onToggleEnabled: (enabled) =>
                  _toggleRuleEnabled(entry.value, enabled),
            ),
          ),
      ],
    );
  }

  Widget _buildAllContentTile() {
    return ListTile(
      title: const Text('全部内容'),
      selected: _selectedRuleId == null,
      shape: const RoundedRectangleBorder(borderRadius: AppShape.cardBorder),
      selectedTileColor: Theme.of(context).colorScheme.secondaryContainer,
      onTap: () {
        setState(() => _selectedRuleId = null);
        ref.read(queueFilterProvider.notifier).setRuleId(null);
      },
    );
  }

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
                      label: '分发规则',
                      value: selected?.id.toString() ?? 'all',
                      options: {
                        'all': '全部内容',
                        for (final rule in rules) rule.id.toString(): rule.name,
                      },
                      onSelected: (value) {
                        final ruleId = value == 'all' ? null : int.parse(value);
                        setState(() => _selectedRuleId = ruleId);
                        ref
                            .read(queueFilterProvider.notifier)
                            .setRuleId(ruleId);
                      },
                    ),
                  ),
                  if (selected != null)
                    IconButton(
                      tooltip: '查看与编辑规则',
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => _openRule(selected),
                    ),
                  IconButton(
                    tooltip: '新建规则',
                    icon: const Icon(Icons.add_rounded),
                    onPressed: _openCreateRule,
                  ),
                ],
              ),
            );
          },
        );
  }

  Widget _buildStatusTabs() {
    final filter = ref.watch(queueFilterProvider);
    final rulesAsync = ref.watch(distributionRulesProvider);
    final statsAsync = ref.watch(queueStatsProvider(_selectedRuleId));
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: statsAsync.when(
        loading: () => rulesAsync.isLoading
            ? const SizedBox.shrink()
            : const LinearProgressIndicator(),
        error: (e, st) => const SizedBox.shrink(),
        data: (stats) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 8,
              children: [
                for (final status in QueueStatus.values)
                  ChoiceChip(
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      spacing: 4,
                      children: [
                        Text(status.label, softWrap: false),
                        Text('${stats[status.value] ?? 0}'),
                      ],
                    ),
                    selected: filter.status == status,
                    showCheckmark: false,
                    onSelected: (_) => ref
                        .read(queueFilterProvider.notifier)
                        .setStatus(status),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildQueueList(List<Widget> header) {
    final queueAsync = ref.watch(contentQueueProvider);
    final filter = ref.watch(queueFilterProvider);

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
          key: _queueListKey,
          header: header,
          items: response.items,
          currentStatus: filter.status,
          onRefresh: () {
            ref.invalidate(contentQueueProvider);
            ref.invalidate(queueStatsProvider(_selectedRuleId));
          },
        );
      },
    );
  }

  Widget _buildHistoryTab(List<Widget> header) {
    final recordsAsync = ref.watch(pushedRecordsProvider);

    return recordsAsync.when(
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
                onPressed: () => ref.invalidate(pushedRecordsProvider),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      ),
      data: (records) {
        if (records.isEmpty) {
          return _buildDistributionState(
            header,
            const Center(child: Text('暂无推送记录')),
          );
        }

        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(pushedRecordsProvider),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              for (final section in header) SliverToBoxAdapter(child: section),
              SliverPadding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                sliver: SliverList.separated(
                  itemCount: records.length,
                  separatorBuilder: (context, index) =>
                      const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final record = records[index];
                    return PushedRecordTile(
                      record: record,
                      onRetry: record.isFailed
                          ? () => _retryPush(record)
                          : null,
                    ).animate().fadeIn(
                      delay: AppMotion.listItemStagger * (index % 15),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _openCreateRule() {
    context.go('/automation/distribution/rules/new');
  }

  void _openRule(DistributionRule rule) {
    context.go('/automation/distribution/rules/${rule.id}');
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
          content: Text('确定要删除规则"${rule.name}" 吗？'),
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

  Future<void> _retryPush(PushedRecord record) async {
    try {
      await ref
          .read(pushedRecordsProvider.notifier)
          .repushNow(contentId: record.contentId, targetId: record.targetId);
      if (mounted) {
        Toast.show(context, '已加入立即重推队列');
      }
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
