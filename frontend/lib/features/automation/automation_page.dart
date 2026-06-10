import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/network/api_client.dart';
import '../../core/network/sse_service.dart';
import '../../core/widgets/frosted_app_bar.dart';
import 'models/distribution_rule.dart';
import 'models/distribution_target.dart';
import 'models/bot_chat.dart';
import 'models/pushed_record.dart';
import 'models/queue_item.dart';
import 'providers/distribution_targets_provider.dart';
import 'providers/distribution_rules_provider.dart';
import 'providers/pushed_records_provider.dart';
import 'providers/bot_chats_provider.dart';
import 'providers/queue_provider.dart';
import '../settings/providers/favorites_sync_provider.dart';
import '../settings/providers/platform_health_provider.dart';
import 'widgets/pushed_record_tile.dart';
import 'widgets/distribution_rule_dialog.dart';
import 'widgets/automation_health_matrix_panel.dart';
import 'widgets/favorites_sync_automation_panel.dart';
import 'widgets/rule_config_panel.dart';
import 'widgets/queue_content_list.dart';
import 'widgets/rule_list_tile.dart';
import '../../core/utils/toast.dart';

class AutomationPage extends ConsumerStatefulWidget {
  const AutomationPage({super.key, this.initialTab, this.highlightRunId});

  final String? initialTab;
  final String? highlightRunId;

  @override
  ConsumerState<AutomationPage> createState() => _AutomationPageState();
}

enum _AutomationSection { overview, sync, distribution, processing }

enum _DistributionDomainView { queue, history }

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.icon,
    this.urgent = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final bool urgent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final color = urgent ? colorScheme.error : colorScheme.primary;

    return Container(
      width: 148,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 10),
          Text(
            value,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _AutomationDomainCard extends StatelessWidget {
  const _AutomationDomainCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.primaryMetric,
    required this.secondaryMetric,
    required this.onOpen,
    this.urgent = false,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final String primaryMetric;
  final String secondaryMetric;
  final VoidCallback onOpen;
  final bool urgent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final accent = urgent ? colorScheme.error : colorScheme.primary;

    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: BorderSide(
          color: urgent
              ? colorScheme.error.withValues(alpha: 0.26)
              : colorScheme.outlineVariant.withValues(alpha: 0.42),
        ),
      ),
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(icon, color: accent),
                  ),
                  const Spacer(),
                  Icon(Icons.arrow_forward_rounded, color: accent),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                title,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(
                    label: Text(primaryMetric),
                    avatar: Icon(Icons.insights_rounded, size: 18, color: accent),
                    side: BorderSide.none,
                    backgroundColor: accent.withValues(alpha: 0.10),
                  ),
                  Chip(
                    label: Text(secondaryMetric),
                    side: BorderSide.none,
                    backgroundColor: colorScheme.surfaceContainerHighest,
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

class _AttentionPanel extends StatelessWidget {
  const _AttentionPanel({
    required this.failedPushes,
    required this.syncFailures,
    required this.platformIssues,
    required this.onOpenDistribution,
    required this.onOpenSync,
    required this.onOpenProcessing,
  });

  final int failedPushes;
  final int syncFailures;
  final int platformIssues;
  final VoidCallback onOpenDistribution;
  final VoidCallback onOpenSync;
  final VoidCallback onOpenProcessing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final items = <Widget>[
      if (failedPushes > 0)
        _AttentionItem(
          icon: Icons.outbox_rounded,
          title: '推送失败',
          description: '$failedPushes 条记录需要检查目标、网络或权限后再处理',
          onTap: onOpenDistribution,
        ),
      if (syncFailures > 0)
        _AttentionItem(
          icon: Icons.bookmark_added_rounded,
          title: '收藏同步失败',
          description: '$syncFailures 个最近 run 失败，进入收藏同步域查看平台结果',
          onTap: onOpenSync,
        ),
      if (platformIssues > 0)
        _AttentionItem(
          icon: Icons.health_and_safety_rounded,
          title: '平台或后处理异常',
          description: '$platformIssues 个平台或处理链路需要诊断',
          onTap: onOpenProcessing,
        ),
    ];

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withValues(alpha: 0.30),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: colorScheme.error.withValues(alpha: 0.22)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.priority_high_rounded, color: colorScheme.error),
                const SizedBox(width: 10),
                Text(
                  '需要处理',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...items.expand((item) => [item, const SizedBox(height: 8)]),
          ],
        ),
      ),
    );
  }
}

class _AttentionItem extends StatelessWidget {
  const _AttentionItem({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: colorScheme.surface.withValues(alpha: 0.70),
      borderRadius: BorderRadius.circular(18),
      child: ListTile(
        leading: Icon(icon, color: colorScheme.error),
        title: Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Text(description),
        trailing: const Icon(Icons.chevron_right_rounded),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        onTap: onTap,
      ),
    );
  }
}

String? _automationRunString(Map<String, dynamic> run, String key) {
  final value = run[key];
  return value == null ? null : value.toString();
}

class _AutomationPageState extends ConsumerState<AutomationPage> {
  late _AutomationSection _section;
  _DistributionDomainView _distributionView = _DistributionDomainView.queue;
  int? _selectedRuleId;
  bool _portraitRuleConfigExpanded = false;
  StreamSubscription<SseEvent>? _sseSub;
  DateTime? _lastToastAt;

  @override
  void initState() {
    super.initState();
    _section = _sectionFromTab(widget.initialTab);
    _distributionView = _distributionViewFromTab(widget.initialTab);
    _bindRealtimeEvents();
  }

  @override
  void didUpdateWidget(AutomationPage oldWidget) {
    super.didUpdateWidget(oldWidget);
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
      appBar: FrostedAppBar(
        title: Text(_section == _AutomationSection.overview ? '自动化' : _sectionTitle(_section)),
        leading: _section == _AutomationSection.overview
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                tooltip: '返回自动化总览',
                onPressed: () => setState(() => _section = _AutomationSection.overview),
              ),
      ),
      body: _buildSectionBody().animate().fadeIn(duration: 240.ms),
    );
  }

  _AutomationSection _sectionFromTab(String? tab) {
    return switch (tab) {
      'favorites' || 'favorites-sync' || 'sync' => _AutomationSection.sync,
      'queue' || 'distribution' || 'history' || 'logs' || 'pushed' =>
        _AutomationSection.distribution,
      'health' || 'matrix' || 'processing' || 'diagnostics' =>
        _AutomationSection.processing,
      _ => _AutomationSection.overview,
    };
  }

  _DistributionDomainView _distributionViewFromTab(String? tab) {
    return switch (tab) {
      'history' || 'logs' || 'pushed' => _DistributionDomainView.history,
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
      _AutomationSection.processing => const AutomationHealthMatrixPanel(),
    };
  }

  Widget _buildOverview() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final queueStats = ref.watch(queueStatsProvider(null));
    final syncStatus = ref.watch(favoritesSyncStatusProvider);
    final pushedRecords = ref.watch(pushedRecordsProvider);
    final platformHealth = ref.watch(platformHealthProvider);

    final willPush = queueStats.value?['will_push'] ?? 0;
    final filtered = queueStats.value?['filtered'] ?? 0;
    final pushed = queueStats.value?['pushed'] ?? 0;
    final failedPushes = pushedRecords.value
            ?.where((record) => record.isFailed)
            .length ??
        0;
    final syncRunning = syncStatus.value?.running ?? false;
    final syncFailures = syncStatus.value?.recentRuns
            .where((run) => _automationRunString(run, 'status') == 'error')
            .length ??
        0;
    final platformIssues = platformHealth.value?.platforms
            .where((platform) => platform.health == 'error')
            .length ??
        0;

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(queueStatsProvider(null));
        ref.invalidate(favoritesSyncStatusProvider);
        ref.invalidate(pushedRecordsProvider);
        ref.invalidate(platformHealthProvider);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withValues(alpha: 0.34),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: colorScheme.primary.withValues(alpha: 0.16),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.auto_mode_rounded, color: colorScheme.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '自动化总览',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '这里只保留运行态、异常摘要和三大域入口；具体队列、历史、平台状态进入对应域处理。',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _MetricTile(
                        label: '待分发',
                        value: willPush.toString(),
                        icon: Icons.outbox_rounded,
                      ),
                      _MetricTile(
                        label: '已过滤',
                        value: filtered.toString(),
                        icon: Icons.filter_list_off_rounded,
                      ),
                      _MetricTile(
                        label: '已推送',
                        value: pushed.toString(),
                        icon: Icons.check_circle_rounded,
                      ),
                      _MetricTile(
                        label: '需处理',
                        value: (failedPushes + syncFailures + platformIssues).toString(),
                        icon: Icons.priority_high_rounded,
                        urgent: failedPushes + syncFailures + platformIssues > 0,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 900;
              final cards = [
                _AutomationDomainCard(
                  title: '收藏同步',
                  subtitle: syncRunning
                      ? '同步任务运行中'
                      : syncFailures > 0
                          ? '$syncFailures 个同步失败需处理'
                          : '平台收藏进入本地资产库',
                  icon: Icons.bookmark_added_rounded,
                  primaryMetric: syncStatus.when(
                    data: (status) => '${status.enabledPlatforms.length} 个平台启用',
                    loading: () => '加载中',
                    error: (_, _) => '状态不可用',
                  ),
                  secondaryMetric: syncStatus.when(
                    data: (status) => status.running ? '运行中' : '未运行',
                    loading: () => '读取状态',
                    error: (_, _) => '需检查',
                  ),
                  urgent: syncFailures > 0,
                  onOpen: () => setState(() => _section = _AutomationSection.sync),
                ),
                _AutomationDomainCard(
                  title: '分发',
                  subtitle: failedPushes > 0
                      ? '$failedPushes 条推送失败'
                      : '队列、规则和推送历史',
                  icon: Icons.send_rounded,
                  primaryMetric: '待分发 $willPush',
                  secondaryMetric: '历史 ${pushedRecords.value?.length ?? 0}',
                  urgent: failedPushes > 0,
                  onOpen: () => setState(() {
                    _section = _AutomationSection.distribution;
                    _distributionView = _DistributionDomainView.queue;
                  }),
                ),
                _AutomationDomainCard(
                  title: '解析 / 后处理',
                  subtitle: platformIssues > 0
                      ? '$platformIssues 个平台或处理链路异常'
                      : '平台、发现源和推送目标健康',
                  icon: Icons.health_and_safety_rounded,
                  primaryMetric: platformHealth.when(
                    data: (health) => '${health.platforms.length} 个平台',
                    loading: () => '加载中',
                    error: (_, _) => '状态不可用',
                  ),
                  secondaryMetric: platformIssues > 0 ? '需处理' : '状态摘要',
                  urgent: platformIssues > 0,
                  onOpen: () => setState(() => _section = _AutomationSection.processing),
                ),
              ];

              if (!wide) {
                return Column(
                  children: [
                    for (final card in cards) ...[
                      card,
                      const SizedBox(height: 12),
                    ],
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final card in cards) ...[
                    Expanded(child: card),
                    if (card != cards.last) const SizedBox(width: 12),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 18),
          if (failedPushes + syncFailures + platformIssues > 0)
            _AttentionPanel(
              failedPushes: failedPushes,
              syncFailures: syncFailures,
              platformIssues: platformIssues,
              onOpenDistribution: () => setState(() {
                _section = _AutomationSection.distribution;
                _distributionView = _DistributionDomainView.history;
              }),
              onOpenSync: () => setState(() => _section = _AutomationSection.sync),
              onOpenProcessing: () =>
                  setState(() => _section = _AutomationSection.processing),
            ),
        ],
      ),
    );
  }

  Widget _buildDistributionDomain() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Row(
            children: [
              Expanded(
                child: SegmentedButton<_DistributionDomainView>(
                  segments: const [
                    ButtonSegment(
                      value: _DistributionDomainView.queue,
                      icon: Icon(Icons.format_list_bulleted_rounded, size: 18),
                      label: Text('队列与规则'),
                    ),
                    ButtonSegment(
                      value: _DistributionDomainView.history,
                      icon: Icon(Icons.history_rounded, size: 18),
                      label: Text('推送历史'),
                    ),
                  ],
                  selected: {_distributionView},
                  onSelectionChanged: (selection) {
                    setState(() => _distributionView = selection.first);
                  },
                  showSelectedIcon: false,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: switch (_distributionView) {
            _DistributionDomainView.queue => _buildQueueTab(),
            _DistributionDomainView.history => _buildHistoryTab(),
          },
        ),
      ],
    );
  }

  Widget _buildQueueTab() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWideScreen = constraints.maxWidth > 900;

        if (isWideScreen) {
          return Row(
            children: [
              SizedBox(width: 360, child: _buildRuleSidebar()),
              VerticalDivider(
                width: 1,
                thickness: 1,
                color: Theme.of(
                  context,
                ).colorScheme.outlineVariant.withValues(alpha: 0.3),
              ),
              Expanded(
                child: Container(
                  color: Theme.of(context).colorScheme.surface,
                  child: _buildQueueContent(),
                ),
              ),
            ],
          );
        } else {
          return Column(
            children: [
              _buildRuleSelector(),
              Expanded(child: _buildQueueContent()),
            ],
          );
        }
      },
    ).animate().fadeIn(duration: 400.ms);
  }

  Widget _buildRuleSidebar() {
    final rulesAsync = ref.watch(distributionRulesProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
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
                  onPressed: _showCreateRuleDialog,
                  tooltip: '新建规则',
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SearchBar(
              hintText: '搜索规则...',
              leading: const Icon(Icons.search_rounded, size: 20),
              elevation: WidgetStateProperty.all(0),
              backgroundColor: WidgetStateProperty.all(
                colorScheme.surfaceContainerHigh,
              ),
            ),
          ),
          Expanded(
            child: rulesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, st) => Center(child: Text('加载失败: $e')),
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
        _buildAllContentCard(colorScheme, theme),
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
          _buildEmptyRulesPlaceholder(theme)
        else
          ...rules.asMap().entries.map(
            (entry) => RuleListTile(
              index: entry.key,
              rule: entry.value,
              isSelected: _selectedRuleId == entry.value.id,
              onTap: () {
                setState(() => _selectedRuleId = entry.value.id);
                ref
                    .read(queueFilterProvider.notifier)
                    .setRuleId(entry.value.id);
              },
              onEdit: () => _showEditRuleDialog(entry.value),
              onDelete: () => _confirmDeleteRule(entry.value),
              onToggleEnabled: (enabled) =>
                  _toggleRuleEnabled(entry.value, enabled),
            ),
          ),
      ],
    );
  }

  Widget _buildAllContentCard(ColorScheme colorScheme, ThemeData theme) {
    final isSelected = _selectedRuleId == null;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isSelected
              ? colorScheme.primary
              : colorScheme.outlineVariant.withValues(alpha: 0.3),
          width: isSelected ? 2 : 1,
        ),
      ),
      color: isSelected
          ? colorScheme.primaryContainer.withValues(alpha: 0.3)
          : colorScheme.surfaceContainerHigh,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          setState(() => _selectedRuleId = null);
          ref.read(queueFilterProvider.notifier).setRuleId(null);
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color:
                      (isSelected ? colorScheme.primary : colorScheme.outline)
                          .withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.all_inclusive_rounded,
                  size: 20,
                  color: isSelected ? colorScheme.primary : colorScheme.outline,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '全部内容',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isSelected ? colorScheme.primary : null,
                      ),
                    ),
                    Text(
                      '显示所有分发任务',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyRulesPlaceholder(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Icon(
            Icons.rule_rounded,
            size: 48,
            color: theme.colorScheme.outline.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          const Text('暂无自定义规则'),
          const SizedBox(height: 16),
          FilledButton.tonalIcon(
            onPressed: _showCreateRuleDialog,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('立即创建'),
          ),
        ],
      ),
    );
  }

  Widget _buildRuleSelector() {
    final rulesAsync = ref.watch(distributionRulesProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: rulesAsync.when(
        loading: () => const LinearProgressIndicator(),
        error: (e, st) =>
            Padding(padding: const EdgeInsets.all(8), child: Text('加载失败: $e')),
        data: (rules) {
          final selectedRule = _selectedRuleId != null
              ? rules.where((r) => r.id == _selectedRuleId).firstOrNull
              : null;

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: DropdownMenu<int?>(
                        initialSelection: _selectedRuleId,
                        dropdownMenuEntries: [
                          const DropdownMenuEntry<int?>(
                            value: null,
                            label: '全部规则',
                            leadingIcon: Icon(
                              Icons.all_inclusive_rounded,
                              size: 18,
                            ),
                          ),
                          ...rules.map(
                            (rule) => DropdownMenuEntry<int?>(
                              value: rule.id,
                              label: rule.name,
                              leadingIcon: const Icon(
                                Icons.rule_rounded,
                                size: 18,
                              ),
                            ),
                          ),
                        ],
                        onSelected: (value) {
                          setState(() {
                            _selectedRuleId = value;
                            _portraitRuleConfigExpanded = false;
                          });
                          ref
                              .read(queueFilterProvider.notifier)
                              .setRuleId(value);
                        },
                        leadingIcon: const Icon(
                          Icons.filter_list_rounded,
                          size: 20,
                        ),
                        expandedInsets: EdgeInsets.zero,
                        inputDecorationTheme: InputDecorationTheme(
                          filled: true,
                          fillColor: colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.5),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (selectedRule != null)
                      IconButton.filledTonal(
                        icon: AnimatedRotation(
                          turns: _portraitRuleConfigExpanded ? 0.5 : 0,
                          duration: 300.ms,
                          child: const Icon(Icons.expand_more_rounded),
                        ),
                        onPressed: () {
                          setState(() {
                            _portraitRuleConfigExpanded =
                                !_portraitRuleConfigExpanded;
                          });
                        },
                      ),
                    const SizedBox(width: 4),
                    IconButton.filledTonal(
                      icon: const Icon(Icons.add_rounded),
                      onPressed: _showCreateRuleDialog,
                    ),
                  ],
                ),
              ),
              AnimatedSize(
                duration: 300.ms,
                curve: Curves.easeOutQuart,
                child: (selectedRule != null && _portraitRuleConfigExpanded)
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        child: _buildRuleConfigPanelWithTargets(selectedRule),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildRuleConfigPanelWithTargets(DistributionRule rule) {
    final targetsAsync = ref.watch(distributionTargetsProvider(rule.id));
    final targets = targetsAsync.value ?? const [];
    return RuleConfigPanel(
      rule: rule,
      targets: targets,
      expanded: true,
      onEdit: () => _showEditRuleDialog(rule),
      onDelete: () => _confirmDeleteRule(rule),
      onToggleEnabled: (enabled) => _toggleRuleEnabled(rule, enabled),
    );
  }

  Widget _buildQueueContent() {
    return Column(
      children: [
        _buildStatusTabs(),
        Expanded(child: _buildQueueList()),
      ],
    );
  }

  Widget _buildStatusTabs() {
    final filter = ref.watch(queueFilterProvider);
    final rulesAsync = ref.watch(distributionRulesProvider);
    final statsAsync = ref.watch(queueStatsProvider(_selectedRuleId));
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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
          final willPush = stats['will_push'] ?? 0;
          final filtered = stats['filtered'] ?? 0;
          final pushed = stats['pushed'] ?? 0;

          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<QueueStatus>(
              segments: [
                ButtonSegment<QueueStatus>(
                  value: QueueStatus.willPush,
                  icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                  label: Text('待推送($willPush)'),
                ),
                ButtonSegment<QueueStatus>(
                  value: QueueStatus.filtered,
                  icon: const Icon(Icons.filter_list_off_rounded, size: 18),
                  label: Text('已过滤($filtered)'),
                ),
                ButtonSegment<QueueStatus>(
                  value: QueueStatus.pushed,
                  icon: const Icon(Icons.check_circle_rounded, size: 18),
                  label: Text('已推送($pushed)'),
                ),
              ],
              selected: {filter.status},
              onSelectionChanged: (Set<QueueStatus> newSelection) {
                ref
                    .read(queueFilterProvider.notifier)
                    .setStatus(newSelection.first);
              },
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                visualDensity: VisualDensity.comfortable,
                selectedBackgroundColor: colorScheme.primary,
                selectedForegroundColor: colorScheme.onPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildQueueList() {
    final queueAsync = ref.watch(contentQueueProvider);
    final filter = ref.watch(queueFilterProvider);

    return queueAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text('加载失败: $e'),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: () => ref.invalidate(contentQueueProvider),
              child: const Text('重试'),
            ),
          ],
        ),
      ),
      data: (response) {
        return QueueContentList(
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

  Widget _buildHistoryTab() {
    final recordsAsync = ref.watch(pushedRecordsProvider);

    return recordsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text('加载失败: $e'),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: () => ref.invalidate(pushedRecordsProvider),
              child: const Text('重试'),
            ),
          ],
        ),
      ),
      data: (records) {
        if (records.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.history_rounded,
                  size: 64,
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.3),
                ),
                const SizedBox(height: 16),
                Text('暂无推送记录', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(pushedRecordsProvider),
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 16),
            itemCount: records.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final record = records[index];
              return PushedRecordTile(
                record: record,
                onRetry: record.isFailed ? () => _retryPush(record) : null,
              ).animate().fadeIn(delay: (index % 15 * 50).ms);
            },
          ),
        );
      },
    );
  }

  void _showCreateRuleDialog() {
    final chats = ref.read(botChatsProvider).asData?.value ?? const <BotChat>[];
    showDialog(
      context: context,
      builder: (ctx) => DistributionRuleDialog(
        availableChats: chats,
        onCreate:
            (rule, selectedChatIds, backfillMode, backfillRecentDays) async {
              try {
                final newRule = await ref
                    .read(distributionRulesProvider.notifier)
                    .createRule(rule);
                final uniqueChatIds = selectedChatIds.toSet();
                var backfilledCount = 0;
                final confirmed = await _confirmBackfillIfNeeded(
                  ruleId: newRule.id,
                  chatIds: uniqueChatIds,
                  backfillMode: backfillMode,
                  backfillRecentDays: backfillRecentDays,
                );
                if (!confirmed) {
                  if (mounted) {
                    Toast.show(context, '规则已创建，目标回填已取消');
                  }
                  return;
                }
                for (final chatId in uniqueChatIds) {
                  final result = await ref
                      .read(distributionTargetsProvider(newRule.id).notifier)
                      .createTargetWithResult(
                        newRule.id,
                        DistributionTargetCreate(botChatId: chatId),
                        backfillMode: backfillMode,
                        backfillRecentDays: backfillRecentDays,
                      );
                  backfilledCount += result.backfilledCount;
                }
                ref.invalidate(botChatsProvider);
                ref.invalidate(contentQueueProvider);
                ref.invalidate(queueStatsProvider(_selectedRuleId));
                if (mounted) {
                  Toast.show(
                    context,
                    backfilledCount > 0
                        ? '规则创建成功，已补建 $backfilledCount 条队列'
                        : '规则创建成功',
                  );
                }
              } catch (e) {
                if (mounted) {
                  Toast.show(context, '创建失败: $e', isError: true);
                }
              }
            },
      ),
    );
  }

  void _showEditRuleDialog(DistributionRule rule) {
    final chats = ref.read(botChatsProvider).asData?.value ?? const <BotChat>[];
    final existingTargets =
        ref.read(distributionTargetsProvider(rule.id)).value ??
        const <DistributionTarget>[];
    final existingByChatId = {
      for (final target in existingTargets) target.botChatId: target,
    };
    showDialog(
      context: context,
      builder: (ctx) => DistributionRuleDialog(
        rule: rule,
        availableChats: chats,
        initialSelectedChatIds: existingByChatId.keys.toList(),
        onCreate:
            (ruleData, selectedChatIds, backfillMode, backfillRecentDays) {},
        onUpdate:
            (
              id,
              update,
              selectedChatIds,
              backfillMode,
              backfillRecentDays,
            ) async {
              try {
                await ref
                    .read(distributionRulesProvider.notifier)
                    .updateRule(id, update);
                final selected = selectedChatIds.toSet();
                var backfilledCount = 0;
                var addedCount = 0;
                var removedCount = 0;
                final addedChatIds = selected
                    .where((chatId) => !existingByChatId.containsKey(chatId))
                    .toSet();
                final confirmed = await _confirmBackfillIfNeeded(
                  ruleId: id,
                  chatIds: addedChatIds,
                  backfillMode: backfillMode,
                  backfillRecentDays: backfillRecentDays,
                );
                if (!confirmed) {
                  if (mounted) {
                    Toast.show(context, '规则已更新，目标回填已取消');
                  }
                  return;
                }

                for (final target in existingTargets) {
                  if (!selected.contains(target.botChatId)) {
                    await ref
                        .read(distributionTargetsProvider(id).notifier)
                        .deleteTarget(id, target.id);
                    removedCount++;
                  }
                }

                for (final chatId in addedChatIds) {
                  final result = await ref
                      .read(distributionTargetsProvider(id).notifier)
                      .createTargetWithResult(
                        id,
                        DistributionTargetCreate(botChatId: chatId),
                        backfillMode: backfillMode,
                        backfillRecentDays: backfillRecentDays,
                      );
                  backfilledCount += result.backfilledCount;
                  addedCount++;
                }
                ref.invalidate(distributionTargetsProvider(id));
                ref.invalidate(contentQueueProvider);
                ref.invalidate(queueStatsProvider(_selectedRuleId));
                if (mounted) {
                  final parts = <String>['规则更新成功'];
                  if (addedCount > 0) parts.add('新增 $addedCount 个目标');
                  if (removedCount > 0) parts.add('移除 $removedCount 个目标');
                  if (backfilledCount > 0) parts.add('补建 $backfilledCount 条队列');
                  Toast.show(context, parts.join('，'));
                }
              } catch (e) {
                if (mounted) {
                  Toast.show(context, '更新失败: $e', isError: true);
                }
              }
            },
      ),
    );
  }

  Future<bool> _confirmBackfillIfNeeded({
    required int ruleId,
    required Set<int> chatIds,
    required String backfillMode,
    required int? backfillRecentDays,
  }) async {
    if (backfillMode == 'new_only' || chatIds.isEmpty) return true;

    var candidateCount = 0;
    for (final chatId in chatIds) {
      candidateCount += await ref
          .read(distributionTargetsProvider(ruleId).notifier)
          .previewBackfill(
            ruleId,
            chatId,
            backfillMode: backfillMode,
            backfillRecentDays: backfillRecentDays,
          );
    }
    if (candidateCount <= 0 || !mounted) return true;

    final modeLabel = backfillMode == 'recent_days'
        ? '最近 ${backfillRecentDays ?? 30} 天'
        : '全部历史';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认回填历史内容'),
        content: Text('将为 $modeLabel 中匹配规则的内容补建约 $candidateCount 条分发队列。'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认回填'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  void _confirmDeleteRule(DistributionRule rule) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除规则"${rule.name}" 吗？'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
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
                  Toast.show(context, '删除失败: $e', isError: true);
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
        Toast.show(context, '操作失败: $e', isError: true);
      }
    }
  }

  Future<void> _retryPush(PushedRecord record) async {
    try {
      final dio = ref.read(apiClientProvider);
      await dio.post(
        '/distribution-queue/content/${record.contentId}/repush-now',
        queryParameters: {'target_id': record.targetId},
      );
      ref.invalidate(pushedRecordsProvider);
      ref.invalidate(contentQueueProvider);
      ref.invalidate(queueStatsProvider(_selectedRuleId));
      ref.read(queueFilterProvider.notifier).setStatus(QueueStatus.willPush);
      if (mounted) {
        Toast.show(context, '已加入立即重推队列');
      }
    } catch (e) {
      if (mounted) {
        Toast.show(context, '操作失败: $e', isError: true);
      }
    }
  }
}
