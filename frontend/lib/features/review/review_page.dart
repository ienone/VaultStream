import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/api_client.dart';
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
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('审批与分发'),
        backgroundColor: colorScheme.surface.withValues(alpha: 0.8),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(color: Colors.transparent),
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.dashboard), text: '内容队列'),
            Tab(icon: Icon(Icons.smart_toy), text: 'Bot 群组'),
            Tab(icon: Icon(Icons.history), text: '推送历史'),
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
            icon: const Icon(Icons.add),
            label: const Text('添加群组'),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildQueueTab() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWideScreen = constraints.maxWidth > 800;

        if (isWideScreen) {
          return Row(
            children: [
              SizedBox(
                width: 320,
                child: _buildRuleSidebar(),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: _buildQueueContent(),
              ),
            ],
          );
        } else {
          return Stack(
            children: [
              Column(
                children: [
                  const SizedBox(height: 72), // Reserve space for rule selector header
                  Expanded(child: _buildQueueContent()),
                ],
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: _buildRuleSelector(),
              ),
            ],
          );
        }
      },
    );
  }

  Widget _buildRuleSidebar() {
    final rulesAsync = ref.watch(distributionRulesProvider);
    final theme = Theme.of(context);

    return Container(
      color: theme.colorScheme.surfaceContainerLow,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Text(
                  '分发规则',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.add, size: 20),
                  onPressed: _showCreateRuleDialog,
                  tooltip: '新建规则',
                ),
              ],
            ),
          ),
          const Divider(height: 1),
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
      padding: const EdgeInsets.all(8),
      children: [
        // "All content" is a special item without rule details
        Card(
          margin: EdgeInsets.zero,
          color: _selectedRuleId == null ? colorScheme.primaryContainer : null,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              setState(() => _selectedRuleId = null);
              ref.read(queueFilterProvider.notifier).setRuleId(null);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '全部内容',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: _selectedRuleId == null ? colorScheme.onPrimaryContainer : null,
                    ),
                  ),
                  Text(
                    '显示所有内容',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: _selectedRuleId == null
                          ? colorScheme.onPrimaryContainer.withValues(alpha: 0.7)
                          : colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Divider(),
        const SizedBox(height: 8),
        if (rules.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Icon(Icons.rule, size: 40, color: theme.colorScheme.outline),
                const SizedBox(height: 8),
                const Text('暂无规则'),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  onPressed: _showCreateRuleDialog,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('创建规则'),
                ),
              ],
            ),
          )
        else
          ...rules.map((rule) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _buildRuleItem(rule),
              )),
      ],
    );
  }

  Widget _buildRuleItem(DistributionRule rule) {
    final isSelected = _selectedRuleId == rule.id;

    return RuleListTile(
      rule: rule,
      isSelected: isSelected,
      onTap: () {
        setState(() => _selectedRuleId = rule.id);
        ref.read(queueFilterProvider.notifier).setRuleId(rule.id);
      },
      onEdit: () => _showEditRuleDialog(rule),
      onDelete: () => _confirmDeleteRule(rule),
      onToggleEnabled: (enabled) => _toggleRuleEnabled(rule, enabled),
    );
  }

  Widget _buildRuleSelector() {
    final rulesAsync = ref.watch(distributionRulesProvider);
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surface,
      elevation: _portraitRuleConfigExpanded ? 4 : 0,
      shadowColor: Colors.black26,
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: _portraitRuleConfigExpanded
              ? theme.colorScheme.surfaceContainer
              : theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
          border: _portraitRuleConfigExpanded
              ? null
              : Border(bottom: BorderSide(color: theme.colorScheme.outlineVariant)),
        ),
        child: rulesAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: LinearProgressIndicator(),
          ),
          error: (e, st) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int?>(
                          initialValue: _selectedRuleId,
                          decoration: InputDecoration(
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 12),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            prefixIcon: const Icon(Icons.rule, size: 20),
                            isDense: true,
                            fillColor: theme.colorScheme.surface,
                            filled: true,
                          ),
                          items: [
                            const DropdownMenuItem<int?>(
                              value: null,
                              child: Text('全部规则'),
                            ),
                            ...rules.map((rule) => DropdownMenuItem<int?>(
                                  value: rule.id,
                                  child: Text(rule.name),
                                )),
                          ],
                          onChanged: (value) {
                            setState(() {
                              _selectedRuleId = value;
                              _portraitRuleConfigExpanded = false;
                            });
                            ref.read(queueFilterProvider.notifier).setRuleId(value);
                          },
                        ),
                      ),
                      const SizedBox(width: 4),
                      if (selectedRule != null)
                        IconButton(
                          icon: Icon(
                            _portraitRuleConfigExpanded
                                ? Icons.expand_less
                                : Icons.expand_more,
                          ),
                          onPressed: () {
                            setState(() {
                              _portraitRuleConfigExpanded =
                                  !_portraitRuleConfigExpanded;
                            });
                          },
                          tooltip:
                              _portraitRuleConfigExpanded ? '收起规则详情' : '展开规则详情',
                        ),
                      IconButton(
                        icon: const Icon(Icons.add),
                        onPressed: _showCreateRuleDialog,
                        tooltip: '新建规则',
                      ),
                    ],
                  ),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  alignment: Alignment.topCenter,
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
                            // No onToggleExpand passed, so icon is hidden
                          ),
                        )
                      : const SizedBox(width: double.infinity),
                ),
              ],
            );
          },
        ),
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
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
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

          return SizedBox(
            width: double.infinity,
            child: SegmentedButton<QueueStatus>(
              segments: [
                ButtonSegment<QueueStatus>(
                  value: QueueStatus.willPush,
                  icon: const Icon(Icons.schedule_send),
                  label: Text('待推送 ($willPush)'),
                ),
                ButtonSegment<QueueStatus>(
                  value: QueueStatus.filtered,
                  icon: const Icon(Icons.filter_alt),
                  label: Text('不推送 ($filtered)'),
                ),
                ButtonSegment<QueueStatus>(
                  value: QueueStatus.pendingReview,
                  icon: const Icon(Icons.pending_actions),
                  label: Text('待审批 ($pending)'),
                ),
                ButtonSegment<QueueStatus>(
                  value: QueueStatus.pushed,
                  icon: const Icon(Icons.check_circle),
                  label: Text('已推送 ($pushed)'),
                ),
              ],
              selected: {filter.status},
              onSelectionChanged: (Set<QueueStatus> newSelection) {
                ref.read(queueFilterProvider.notifier).setStatus(newSelection.first);
              },
              showSelectedIcon: false,
              style: ButtonStyle(
                visualDensity: VisualDensity.comfortable,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
            Icon(Icons.error_outline, size: 48, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 16),
            Text('加载失败: $e'),
            const SizedBox(height: 16),
            FilledButton(
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

    return chatsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 16),
            Text('加载失败: $e'),
            const SizedBox(height: 16),
            FilledButton(
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
            padding: const EdgeInsets.all(16),
            children: [
              BotStatusCard(
                isSyncing: _isSyncingChats,
                onSync: _syncBotChats,
                onTriggerPush: _triggerPush,
              ),
              const SizedBox(height: 16),
              if (chats.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 48),
                  child: Column(
                    children: [
                      Icon(
                        Icons.smart_toy,
                        size: 64,
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '暂无关联的群组/频道',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      const Text('点击右下角按钮添加群组'),
                    ],
                  ),
                )
              else
                ...chats.map((chat) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: BotChatCard(
                        chat: chat,
                        onEdit: () => _showEditBotChatDialog(chat),
                        onDelete: () => _confirmDeleteBotChat(chat),
                        onToggleEnabled: (enabled) => _toggleBotChatEnabled(chat),
                      ),
                    )),
              const SizedBox(height: 80),
            ],
          ),
        );
      },
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
          SnackBar(content: Text('同步完成: ${result.updated} 更新')),
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
          const SnackBar(content: Text('已触发分发任务，正在后台处理...')),
        );
        // Refresh stats after a short delay
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
            Icon(Icons.error_outline, size: 48, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 16),
            Text('加载失败: $e'),
            const SizedBox(height: 16),
            FilledButton(
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
                  Icons.history,
                  size: 64,
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
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
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: records.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final record = records[index];
              return PushedRecordTile(
                record: record,
                onRetry: record.isFailed ? () => _retryPush(record) : null,
              );
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
      // Switch to willPush tab to show the re-queued content
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


