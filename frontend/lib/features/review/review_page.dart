import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/network/api_client.dart';
import '../../core/widgets/frosted_app_bar.dart';
import 'models/distribution_rule.dart';
import 'models/bot_chat.dart';
import 'models/pushed_record.dart';
import 'models/queue_item.dart';
import 'providers/distribution_rules_provider.dart';
import 'providers/pushed_records_provider.dart';
import 'providers/bot_chats_provider.dart';
import 'providers/queue_provider.dart';
import 'widgets/pushed_record_tile.dart';
import 'widgets/distribution_rule_dialog.dart';
import 'widgets/bot_chat_card.dart';
import 'widgets/bot_chat_dialog.dart';
import 'widgets/bot_status_card.dart';
import 'widgets/rule_config_panel.dart';
import 'widgets/queue_content_list.dart';
import 'widgets/rule_list_tile.dart';

class ReviewPage extends ConsumerStatefulWidget {
  const ReviewPage({super.key});

  @override
  ConsumerState<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends ConsumerState<ReviewPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _isSyncingChats = false;
  int? _selectedRuleId;
  bool _portraitRuleConfigExpanded = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: FrostedAppBar(
        title: const Text('审批与分发'),
        bottom: TabBar(
          controller: _tabController,
          dividerColor: Colors.transparent,
          indicatorSize: TabBarIndicatorSize.label,
          indicatorWeight: 3,
          labelStyle: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold),
          unselectedLabelStyle: theme.textTheme.labelLarge,
          tabs: const [
            Tab(text: '内容队列'),
            Tab(text: 'Bot 群组'),
            Tab(text: '推送历史'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildQueueTab(),
          _buildBotChatsTab(),
          _buildHistoryTab(),
        ],
      ),
      floatingActionButton: _buildFab(),
    );
  }

  Widget? _buildFab() {
    return AnimatedBuilder(
      animation: _tabController,
      builder: (context, _) {
        if (_tabController.index == 1) {
          return FloatingActionButton.extended(
            onPressed: _showAddBotChatDialog,
            icon: const Icon(Icons.add_rounded, size: 24),
            label: const Text('添加群组'),
            isExtended: true,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          ).animate().scale(curve: Curves.easeOutBack, duration: 400.ms);
        }
        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildQueueTab() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWideScreen = constraints.maxWidth > 900;

        if (isWideScreen) {
          return Row(
            children: [
              SizedBox(
                width: 360,
                child: _buildRuleSidebar(),
              ),
              VerticalDivider(
                width: 1, 
                thickness: 1, 
                color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.3)
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
      color: colorScheme.surfaceContainerLow, // Added consistent background color
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
              backgroundColor: WidgetStateProperty.all(colorScheme.surfaceContainerHigh),
              onChanged: (value) {
                // TODO: Implement rule filtering if needed
              },
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
                style: theme.textTheme.labelSmall?.copyWith(color: colorScheme.outline, fontWeight: FontWeight.bold)
              ),
            ),
            const Expanded(child: Divider()),
          ],
        ),
        const SizedBox(height: 16),
        if (rules.isEmpty)
          _buildEmptyRulesPlaceholder(theme)
        else
          ...rules.asMap().entries.map((entry) => RuleListTile(
                index: entry.key,
                rule: entry.value,
                isSelected: _selectedRuleId == entry.value.id,
                onTap: () {
                  setState(() => _selectedRuleId = entry.value.id);
                  ref.read(queueFilterProvider.notifier).setRuleId(entry.value.id);
                },
                onEdit: () => _showEditRuleDialog(entry.value),
                onDelete: () => _confirmDeleteRule(entry.value),
                onToggleEnabled: (enabled) => _toggleRuleEnabled(entry.value, enabled),
              )),
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
            color: isSelected ? colorScheme.primary : colorScheme.outlineVariant.withValues(alpha: 0.3),
            width: isSelected ? 2 : 1,
          ),
        ),
        color: isSelected ? colorScheme.primaryContainer.withValues(alpha: 0.3) : colorScheme.surfaceContainerHigh,
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
                    color: (isSelected ? colorScheme.primary : colorScheme.outline).withValues(alpha: 0.1),
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
                Icon(Icons.rule_rounded, size: 48, color: theme.colorScheme.outline.withValues(alpha: 0.5)),
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
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.3))),
      ),
      child: rulesAsync.when(
        loading: () => const LinearProgressIndicator(),
        error: (e, st) => Padding(
          padding: const EdgeInsets.all(8),
          child: Text('加载失败: $e'),
        ),
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
                            leadingIcon: Icon(Icons.all_inclusive_rounded, size: 18),
                          ),
                          ...rules.map((rule) => DropdownMenuEntry<int?>(
                            value: rule.id,
                            label: rule.name,
                            leadingIcon: const Icon(Icons.rule_rounded, size: 18),
                          )),
                        ],
                        onSelected: (value) {
                          setState(() {
                            _selectedRuleId = value;
                            _portraitRuleConfigExpanded = false;
                          });
                          ref.read(queueFilterProvider.notifier).setRuleId(value);
                        },
                        leadingIcon: const Icon(Icons.filter_list_rounded, size: 20),
                        expandedInsets: EdgeInsets.zero,
                        inputDecorationTheme: InputDecorationTheme(
                          filled: true,
                          fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
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
                            _portraitRuleConfigExpanded = !_portraitRuleConfigExpanded;
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
                        child: RuleConfigPanel(
                          rule: selectedRule,
                          expanded: true,
                          onEdit: () => _showEditRuleDialog(selectedRule),
                          onDelete: () => _confirmDeleteRule(selectedRule),
                          onToggleEnabled: (enabled) =>
                              _toggleRuleEnabled(selectedRule, enabled),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          );
        },
      ),
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
    final statsAsync = ref.watch(queueStatsProvider(_selectedRuleId));
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
        ),
      ),
      child: statsAsync.when(
        loading: () => const LinearProgressIndicator(),
        error: (e, st) => const SizedBox.shrink(),
        data: (stats) {
          final willPush = stats['will_push'] ?? 0;
          final filtered = stats['filtered'] ?? 0;
          final pending = stats['pending_review'] ?? 0;
          final pushed = stats['pushed'] ?? 0;

          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<QueueStatus>(
              segments: [
                ButtonSegment<QueueStatus>(
                  value: QueueStatus.willPush,
                  icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                  label: Text('待推送 ($willPush)'),
                ),
                ButtonSegment<QueueStatus>(
                  value: QueueStatus.filtered,
                  icon: const Icon(Icons.filter_list_off_rounded, size: 18),
                  label: Text('已过滤 ($filtered)'),
                ),
                ButtonSegment<QueueStatus>(
                  value: QueueStatus.pendingReview,
                  icon: const Icon(Icons.rate_review_rounded, size: 18),
                  label: Text('待审批 ($pending)'),
                ),
                ButtonSegment<QueueStatus>(
                  value: QueueStatus.pushed,
                  icon: const Icon(Icons.check_circle_rounded, size: 18),
                  label: Text('已推送 ($pushed)'),
                ),
              ],
              selected: {filter.status},
              onSelectionChanged: (Set<QueueStatus> newSelection) {
                ref.read(queueFilterProvider.notifier).setStatus(newSelection.first);
              },
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                visualDensity: VisualDensity.comfortable,
                selectedBackgroundColor: colorScheme.primary,
                selectedForegroundColor: colorScheme.onPrimary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
            Icon(Icons.error_outline_rounded, size: 48, color: Theme.of(context).colorScheme.error),
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

  Widget _buildBotChatsTab() {
    final chatsAsync = ref.watch(botChatsProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return chatsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline_rounded, size: 48, color: colorScheme.error),
            const SizedBox(height: 16),
            Text('加载失败: $e'),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: () => ref.invalidate(botChatsProvider),
              child: const Text('重试'),
            ),
          ],
        ),
      ),
      data: (chats) {
        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(botChatsProvider);
            ref.invalidate(botStatusProvider);
          },
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              BotStatusCard(
                isSyncing: _isSyncingChats,
                onSync: _syncBotChats,
                onTriggerPush: _triggerPush,
              ),
              const SizedBox(height: 32),
              Row(
                children: [
                  Icon(Icons.groups_rounded, size: 20, color: colorScheme.primary),
                  const SizedBox(width: 12),
                  Text('群组与频道', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                  const Spacer(),
                  Text('${chats.length} 个配置', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: colorScheme.outline)),
                ],
              ),
              const SizedBox(height: 20),
              if (chats.isEmpty)
                _buildEmptyChatsPlaceholder(colorScheme)
              else
                ...chats.asMap().entries.map((entry) => Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: BotChatCard(
                        index: entry.key,
                        chat: entry.value,
                        onEdit: () => _showEditBotChatDialog(entry.value),
                        onDelete: () => _confirmDeleteBotChat(entry.value),
                        onToggleEnabled: (enabled) => _toggleBotChatEnabled(entry.value),
                      ),
                    )),
              const SizedBox(height: 100),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyChatsPlaceholder(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 64),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.05),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.smart_toy_rounded, size: 64, color: colorScheme.primary.withValues(alpha: 0.5)),
          ),
          const SizedBox(height: 24),
          Text('暂无关联的群组/频道', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          const Text('点击右下角按钮添加第一个推送目标'),
        ],
      ),
    );
  }

  Future<void> _syncBotChats() async {
    if (_isSyncingChats) return;
    setState(() => _isSyncingChats = true);

    try {
      final result = await ref.read(botChatsProvider.notifier).syncChats();
      if (mounted) {
        ref.invalidate(botStatusProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            content: Text('同步完成: ${result.updated} 个配置已更新'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('同步失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncingChats = false);
    }
  }

  Future<void> _triggerPush() async {
    try {
      final dio = ref.read(apiClientProvider);
      await dio.post('/distribution/trigger-run');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            content: const Text('已触发分发任务，正在后台处理...'),
          ),
        );
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            ref.invalidate(botStatusProvider);
            ref.invalidate(queueStatsProvider(_selectedRuleId));
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('触发失败: $e')),
        );
      }
    }
  }

  Widget _buildHistoryTab() {
    final recordsAsync = ref.watch(pushedRecordsProvider);

    return recordsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline_rounded, size: 48, color: Theme.of(context).colorScheme.error),
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
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                ),
                const SizedBox(height: 16),
                Text(
                  '暂无推送记录',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
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
    showDialog(
      context: context,
      builder: (ctx) => DistributionRuleDialog(
        onCreate: (rule) async {
          try {
            await ref.read(distributionRulesProvider.notifier).createRule(rule);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('规则创建成功')),
              );
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('创建失败: $e')),
              );
            }
          }
        },
      ),
    );
  }

  void _showEditRuleDialog(DistributionRule rule) {
    showDialog(
      context: context,
      builder: (ctx) => DistributionRuleDialog(
        rule: rule,
        onCreate: (_) {},
        onUpdate: (id, update) async {
          try {
            await ref.read(distributionRulesProvider.notifier).updateRule(id, update);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('规则更新成功')),
              );
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('更新失败: $e')),
              );
            }
          }
        },
      ),
    );
  }

  void _confirmDeleteRule(DistributionRule rule) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除规则 "${rule.name}" 吗？'),
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
                await ref.read(distributionRulesProvider.notifier).deleteRule(rule.id);
                if (_selectedRuleId == rule.id) {
                  setState(() => _selectedRuleId = null);
                  ref.read(queueFilterProvider.notifier).setRuleId(null);
                }
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('规则已删除')),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('删除失败: $e')),
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
      await ref.read(distributionRulesProvider.notifier).toggleEnabled(rule.id, enabled);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('操作失败: $e')),
        );
      }
    }
  }

  Future<void> _retryPush(PushedRecord record) async {
    try {
      await ref.read(pushedRecordsProvider.notifier).deleteRecord(record.id);
      await ref.read(contentQueueProvider.notifier).moveToStatus(
        record.contentId,
        QueueStatus.willPush,
      );
      ref.invalidate(pushedRecordsProvider);
      ref.invalidate(contentQueueProvider);
      ref.invalidate(queueStatsProvider(_selectedRuleId));
      ref.read(queueFilterProvider.notifier).setStatus(QueueStatus.willPush);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已重置状态，内容已移至待推送队列')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('操作失败: $e')),
        );
      }
    }
  }

  void _showAddBotChatDialog() {
    showDialog(
      context: context,
      builder: (ctx) => BotChatDialog(
        onCreate: (chat) async {
          try {
            await ref.read(botChatsProvider.notifier).createChat(chat);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('群组添加成功')),
              );
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('添加失败: $e')),
              );
            }
          }
        },
      ),
    );
  }

  void _showEditBotChatDialog(BotChat chat) {
    showDialog(
      context: context,
      builder: (ctx) => BotChatDialog(
        chat: chat,
        onCreate: (_) {},
        onUpdate: (chatId, update) async {
          try {
            await ref.read(botChatsProvider.notifier).updateChat(chatId, update);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('配置更新成功')),
              );
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('更新失败: $e')),
              );
            }
          }
        },
      ),
    );
  }

  void _confirmDeleteBotChat(BotChat chat) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除群组 "${chat.displayName}" 吗？'),
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
                await ref.read(botChatsProvider.notifier).deleteChat(chat.chatId);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('群组已删除')),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('删除失败: $e')),
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

  Future<void> _toggleBotChatEnabled(BotChat chat) async {
    try {
      await ref.read(botChatsProvider.notifier).toggleChat(chat.chatId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('操作失败: $e')),
        );
      }
    }
  }
}