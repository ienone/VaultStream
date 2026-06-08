import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../core/utils/toast.dart';
import '../../settings/providers/favorites_sync_provider.dart';
import '../../settings/providers/settings_provider.dart';

class FavoritesSyncAutomationPanel extends ConsumerStatefulWidget {
  const FavoritesSyncAutomationPanel({super.key, this.highlightRunId});

  final String? highlightRunId;

  @override
  ConsumerState<FavoritesSyncAutomationPanel> createState() =>
      _FavoritesSyncAutomationPanelState();
}

class _FavoritesSyncAutomationPanelState
    extends ConsumerState<FavoritesSyncAutomationPanel> {
  String? _openedRunId;

  @override
  void didUpdateWidget(FavoritesSyncAutomationPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.highlightRunId != widget.highlightRunId) {
      _openedRunId = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusAsync = ref.watch(favoritesSyncStatusProvider);

    return statusAsync.when(
      data: (status) {
        _openHighlightedRunIfReady(status.recentRuns);
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(favoritesSyncStatusProvider),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
            children: [
              _SyncOverviewCard(status: status),
              const SizedBox(height: 16),
              _SyncCommandBar(status: status),
              const SizedBox(height: 16),
              _SyncPolicyCard(status: status),
              const SizedBox(height: 16),
              _PlatformStatusGrid(platforms: status.platforms),
              const SizedBox(height: 24),
              _RecentRunsList(runs: status.recentRuns),
            ],
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline_rounded,
                size: 44,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 12),
              Text('收藏同步状态加载失败: $error'),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => ref.invalidate(favoritesSyncStatusProvider),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openHighlightedRunIfReady(List<Map<String, dynamic>> runs) {
    final highlightRunId = widget.highlightRunId;
    if (highlightRunId == null ||
        highlightRunId.isEmpty ||
        _openedRunId == highlightRunId) {
      return;
    }
    Map<String, dynamic>? matchedRun;
    for (final run in runs) {
      if (_runString(run, 'run_id') == highlightRunId) {
        matchedRun = run;
        break;
      }
    }
    if (matchedRun == null) return;

    _openedRunId = highlightRunId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showRunDetail(context, matchedRun!);
    });
  }
}

class _SyncOverviewCard extends StatelessWidget {
  const _SyncOverviewCard({required this.status});

  final FavoritesSyncStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final enabledCount = status.enabledPlatforms.length;
    final authenticatedCount = status.platforms
        .where((item) => item.authenticated)
        .length;
    final failureCount = status.recentRuns
        .where((run) => _runString(run, 'status') == 'error')
        .length;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bookmark_added_rounded, color: cs.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '收藏同步总览',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  status.running ? '自动任务运行中' : '自动任务未运行',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: status.running ? cs.primary : cs.error,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _MetricChip(label: '已启用平台', value: enabledCount),
                _MetricChip(label: '认证可用', value: authenticatedCount),
                _MetricChip(label: '失败任务', value: failureCount),
                _MetricChip(label: '单轮上限', value: status.maxItems),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '同步间隔 ${status.intervalMinutes} 分钟；最近同步 ${status.lastSyncAt ?? '尚未完成'}。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SyncPolicyCard extends ConsumerWidget {
  const _SyncPolicyCard({required this.status});

  final FavoritesSyncStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final enabledPlatforms = status.enabledPlatforms.isEmpty
        ? '暂无已启用平台'
        : status.enabledPlatforms.map(_platformLabel).join('、');

    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.rule_folder_rounded, color: cs.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '同步策略',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => context.push('/settings?tab=automation'),
                  icon: const Icon(Icons.tune_rounded, size: 18),
                  label: const Text('高级参数'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _PolicyLine(
              icon: Icons.account_tree_rounded,
              label: '同步范围',
              value: enabledPlatforms,
            ),
            _PolicyLine(
              icon: Icons.update_rounded,
              label: '拉取策略',
              value:
                  '按平台 cursor 增量拉取；每轮最多 ${status.maxItems} 条；每 ${status.intervalMinutes} 分钟自动执行。',
            ),
            const SizedBox(height: 10),
            _PolicyControlRow(
              label: '同步间隔',
              value: status.intervalMinutes,
              values: const [60, 180, 360, 720, 1440],
              suffix: '分钟',
              onChanged: (value) => _updateFavoritesSyncSetting(
                context,
                ref,
                key: 'favorites_sync_interval_minutes',
                value: value,
              ),
            ),
            _PolicyControlRow(
              label: '单轮上限',
              value: status.maxItems,
              values: const [20, 50, 100, 200],
              suffix: '条',
              onChanged: (value) => _updateFavoritesSyncSetting(
                context,
                ref,
                key: 'favorites_sync_max_items',
                value: value,
              ),
            ),
            _PolicyStringControlRow(
              label: '重复处理',
              value: status.duplicateStrategy,
              options: const {'merge': '合并已有收藏', 'skip': '跳过已有收藏'},
              description: _duplicateStrategyDescription(
                status.duplicateStrategy,
              ),
              onChanged: (value) => _updateFavoritesSyncSetting(
                context,
                ref,
                key: 'favorites_sync_duplicate_strategy',
                value: value,
              ),
            ),
            _PolicyStringControlRow(
              label: '同步范围',
              value: status.scopeStrategy,
              options: const {
                'all_favorites': '全部收藏',
                'collections_api_placeholder': '收藏夹/分组接口预留',
              },
              description: _scopeStrategyDescription(status.scopeStrategy),
              onChanged: (value) => _updateFavoritesSyncSetting(
                context,
                ref,
                key: 'favorites_sync_scope_strategy',
                value: value,
              ),
            ),
            _PolicyStringControlRow(
              label: '首次同步',
              value: status.firstSyncStrategy,
              options: const {
                'latest_page': '仅拉取当前页',
                'full_backfill_placeholder': '全量回填接口预留',
              },
              description: _firstSyncStrategyDescription(
                status.firstSyncStrategy,
              ),
              onChanged: (value) => _updateFavoritesSyncSetting(
                context,
                ref,
                key: 'favorites_sync_first_sync_strategy',
                value: value,
              ),
            ),
            _PolicyStringControlRow(
              label: '取消收藏',
              value: status.unfavoriteStrategy,
              options: const {
                'keep_local': '保留本地收藏',
                'mark_archived_placeholder': '标记归档接口预留',
              },
              description: _unfavoriteStrategyDescription(
                status.unfavoriteStrategy,
              ),
              onChanged: (value) => _updateFavoritesSyncSetting(
                context,
                ref,
                key: 'favorites_sync_unfavorite_strategy',
                value: value,
              ),
            ),
            const _PolicyLine(
              icon: Icons.replay_rounded,
              label: '失败恢复',
              value: '支持 run 级失败重试，也可在结果摘要中重试单条失败候选。',
            ),
          ],
        ),
      ),
    );
  }
}

class _PolicyStringControlRow extends StatelessWidget {
  const _PolicyStringControlRow({
    required this.label,
    required this.value,
    required this.options,
    required this.description,
    required this.onChanged,
  });

  final String label;
  final String value;
  final Map<String, String> options;
  final String description;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final normalizedValue = options.containsKey(value)
        ? value
        : options.keys.first;

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.difference_rounded, size: 18, color: cs.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          DropdownButton<String>(
            value: normalizedValue,
            underline: const SizedBox.shrink(),
            items: [
              for (final entry in options.entries)
                DropdownMenuItem(value: entry.key, child: Text(entry.value)),
            ],
            onChanged: (next) {
              if (next != null && next != normalizedValue) {
                onChanged(next);
              }
            },
          ),
        ],
      ),
    );
  }
}

class _PolicyControlRow extends StatelessWidget {
  const _PolicyControlRow({
    required this.label,
    required this.value,
    required this.values,
    required this.suffix,
    required this.onChanged,
  });

  final String label;
  final int value;
  final List<int> values;
  final String suffix;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final options = _withCurrentValue(values, value);

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Icon(Icons.tune_rounded, size: 18, color: cs.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          DropdownButton<int>(
            value: value,
            underline: const SizedBox.shrink(),
            items: [
              for (final option in options)
                DropdownMenuItem(value: option, child: Text('$option $suffix')),
            ],
            onChanged: (next) {
              if (next != null && next != value) {
                onChanged(next);
              }
            },
          ),
        ],
      ),
    );
  }
}

class _PolicyLine extends StatelessWidget {
  const _PolicyLine({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: cs.onSurfaceVariant),
          const SizedBox(width: 8),
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

class _SyncCommandBar extends ConsumerWidget {
  const _SyncCommandBar({required this.status});

  final FavoritesSyncStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        FilledButton.tonalIcon(
          onPressed: () => _triggerWithPreview(context, ref),
          icon: const Icon(Icons.sync_rounded),
          label: const Text('同步全部'),
        ),
        OutlinedButton.icon(
          onPressed: () => _showPreview(context, ref),
          icon: const Icon(Icons.manage_search_rounded),
          label: const Text('预览同步'),
        ),
        OutlinedButton.icon(
          onPressed: () => ref.invalidate(favoritesSyncStatusProvider),
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('刷新状态'),
        ),
      ],
    );
  }
}

class _PlatformStatusGrid extends StatelessWidget {
  const _PlatformStatusGrid({required this.platforms});

  final List<FavoritesPlatformStatus> platforms;

  @override
  Widget build(BuildContext context) {
    if (platforms.isEmpty) {
      return const _EmptyPanel(message: '暂无可用收藏同步平台');
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1080
            ? 3
            : constraints.maxWidth >= 720
            ? 2
            : 1;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: platforms.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            mainAxisExtent: 188,
          ),
          itemBuilder: (context, index) =>
              _PlatformStatusCard(status: platforms[index]),
        );
      },
    );
  }
}

class _PlatformStatusCard extends ConsumerWidget {
  const _PlatformStatusCard({required this.status});

  final FavoritesPlatformStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final ok = status.enabled && status.available && status.authenticated;
    final color = ok
        ? cs.primary
        : status.available
        ? cs.tertiary
        : cs.error;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_platformIcon(status.platform), color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _platformLabel(status.platform),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  _platformStateLabel(status),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '速率 ${status.ratePerMinute.toStringAsFixed(0)}/min',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            if (status.error != null || status.statusError != null) ...[
              const SizedBox(height: 6),
              Text(
                status.error ?? status.statusError.toString(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: cs.error),
              ),
            ],
            const Spacer(),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: status.available
                      ? () => _showPreview(
                          context,
                          ref,
                          platform: status.platform,
                        )
                      : null,
                  icon: const Icon(Icons.manage_search_rounded, size: 16),
                  label: const Text('预览'),
                ),
                FilledButton.tonalIcon(
                  onPressed: status.available
                      ? () => _triggerWithPreview(
                          context,
                          ref,
                          platform: status.platform,
                        )
                      : null,
                  icon: const Icon(Icons.sync_rounded, size: 16),
                  label: const Text('同步'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentRunsList extends ConsumerWidget {
  const _RecentRunsList({required this.runs});

  final List<Map<String, dynamic>> runs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    if (runs.isEmpty) {
      return const _EmptyPanel(message: '暂无同步运行记录');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '同步运行记录',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Column(
            children: [
              for (final entry in runs.take(8).indexed) ...[
                _RunTile(run: entry.$2),
                if (entry.$1 < runs.take(8).length - 1)
                  const Divider(height: 1),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _RunTile extends ConsumerWidget {
  const _RunTile({required this.run});

  final Map<String, dynamic> run;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = _runString(run, 'status') ?? 'unknown';
    final runId = _runString(run, 'run_id');
    final isError = status == 'error';
    final error = _runString(run, 'error');

    return ListTile(
      leading: Icon(
        isError ? Icons.error_outline_rounded : Icons.task_alt_rounded,
        color: isError
            ? Theme.of(context).colorScheme.error
            : Theme.of(context).colorScheme.primary,
      ),
      title: Text('${_shortId(runId)} · ${_runString(run, 'scope') ?? 'all'}'),
      subtitle: Text(
        [
          _runStatusLabel(status),
          if (_runString(run, 'trigger') != null)
            '触发: ${_runString(run, 'trigger')}',
          if (_runString(run, 'started_at') != null)
            '开始: ${_runString(run, 'started_at')}',
          if (error != null) '错误: $error',
        ].join('\n'),
        maxLines: 4,
        overflow: TextOverflow.ellipsis,
      ),
      isThreeLine: true,
      trailing: isError && runId != null
          ? OutlinedButton.icon(
              onPressed: () => _retryRun(context, ref, runId),
              icon: const Icon(Icons.replay_rounded, size: 16),
              label: const Text('重试'),
            )
          : null,
      onTap: () => _showRunDetail(context, run),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Chip(
      label: Text('$label $value'),
      backgroundColor: cs.surfaceContainerHighest,
      side: BorderSide(color: cs.outlineVariant),
    );
  }
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Text(message),
    );
  }
}

Future<void> _showPreview(
  BuildContext context,
  WidgetRef ref, {
  String? platform,
}) async {
  try {
    final preview = await ref
        .read(favoritesSyncActionsProvider)
        .previewSync(platform: platform);
    if (!context.mounted) return;
    await _showPreviewDialog(context, preview, confirmMode: false);
  } catch (e) {
    if (context.mounted) {
      Toast.show(
        context,
        formatApiErrorMessage(e, fallbackMessage: '预览同步失败'),
        isError: true,
      );
    }
  }
}

Future<void> _triggerWithPreview(
  BuildContext context,
  WidgetRef ref, {
  String? platform,
}) async {
  try {
    final actions = ref.read(favoritesSyncActionsProvider);
    final preview = await actions.previewSync(platform: platform);
    if (!context.mounted) return;
    final confirmed = await _showPreviewDialog(
      context,
      preview,
      confirmMode: true,
    );
    if (!confirmed || !context.mounted) return;

    final runId = await actions.triggerSync(platform: platform);
    if (context.mounted) {
      Toast.show(
        context,
        '已触发 ${platform == null ? '全平台' : _platformLabel(platform)} 同步${runId == null ? '' : ' #${_shortId(runId)}'}',
      );
    }
  } catch (e) {
    if (context.mounted) {
      Toast.show(
        context,
        formatApiErrorMessage(e, fallbackMessage: '触发同步失败'),
        isError: true,
      );
    }
  }
}

Future<bool> _showPreviewDialog(
  BuildContext context,
  FavoritesSyncPreview preview, {
  required bool confirmMode,
}) async {
  final theme = Theme.of(context);
  final cs = theme.colorScheme;
  final label = preview.platform == 'all'
      ? '全平台'
      : _platformLabel(preview.platform);
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(confirmMode ? '确认同步 $label 收藏' : '$label 收藏同步预览'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _MetricChip(label: '拉取', value: preview.fetched),
                  _MetricChip(label: '预计新增', value: preview.estimatedNew),
                  _MetricChip(label: '已存在', value: preview.existing),
                  _MetricChip(label: '跳过', value: preview.skipped),
                ],
              ),
              const SizedBox(height: 14),
              for (final item in preview.platforms)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _PreviewPlatformSection(item: item),
                ),
              Text(
                '预览不会导入内容或推进 cursor。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(confirmMode ? '取消' : '关闭'),
        ),
        if (confirmMode)
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('确认同步'),
          ),
      ],
    ),
  );
  return result == true;
}

class _PreviewPlatformSection extends StatelessWidget {
  const _PreviewPlatformSection({required this.item});

  final FavoritesSyncPlatformPreview item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final failed = item.status == 'failed';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          failed
              ? '${_platformLabel(item.platform)}: ${item.errorHint ?? item.error ?? '预览失败'}'
              : '${_platformLabel(item.platform)}: 新增 ${item.estimatedNew}，重复 ${item.existing}',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: failed ? cs.error : null,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (!failed && item.items.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            '候选样本',
            style: theme.textTheme.labelLarge?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          for (final sample in item.items.take(5))
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _PreviewFavoriteItem(item: sample),
            ),
        ],
      ],
    );
  }
}

class _PreviewFavoriteItem extends StatelessWidget {
  const _PreviewFavoriteItem({required this.item});

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final title = _mapString(item, 'title');
    final url = _mapString(item, 'url') ?? '-';
    final exists = item['exists'] == true;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              exists ? Icons.content_copy_rounded : Icons.add_circle_rounded,
              size: 18,
              color: exists ? cs.outline : cs.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title != null)
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  SelectableText(
                    url,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              exists ? '已存在' : '预计新增',
              style: theme.textTheme.labelMedium?.copyWith(
                color: exists ? cs.outline : cs.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _retryRun(
  BuildContext context,
  WidgetRef ref,
  String runId,
) async {
  try {
    final retryRunId = await ref
        .read(favoritesSyncActionsProvider)
        .retryRun(runId);
    if (context.mounted) {
      Toast.show(
        context,
        '已重新触发同步${retryRunId == null ? '' : ' #${_shortId(retryRunId)}'}',
      );
    }
  } catch (e) {
    if (context.mounted) {
      Toast.show(
        context,
        formatApiErrorMessage(e, fallbackMessage: '重试同步失败'),
        isError: true,
      );
    }
  }
}

Future<void> _retryFailedFavoriteItem(
  BuildContext context,
  WidgetRef ref, {
  required String platform,
  required String? sourceRunId,
  required Map<String, dynamic> item,
}) async {
  final url = _mapString(item, 'url');
  if (url == null || url.isEmpty) {
    Toast.show(context, '失败项缺少 URL，无法重试', isError: true);
    return;
  }

  try {
    final retryRunId = await ref
        .read(favoritesSyncActionsProvider)
        .retryItem(
          platform: platform,
          url: url,
          title: _mapString(item, 'title'),
          itemId: _mapString(item, 'item_id'),
          sourceRunId: sourceRunId,
        );
    if (context.mounted) {
      Toast.show(
        context,
        '已重试失败项${retryRunId == null ? '' : ' #${_shortId(retryRunId)}'}',
        action: retryRunId == null
            ? null
            : SnackBarAction(
                label: '查看日志',
                onPressed: () => context.go('/tasks/$retryRunId'),
              ),
      );
    }
  } catch (e) {
    if (context.mounted) {
      Toast.show(
        context,
        formatApiErrorMessage(e, fallbackMessage: '重试失败项失败'),
        isError: true,
      );
    }
  }
}

Future<void> _retryFailedFavoriteItems(
  BuildContext context,
  WidgetRef ref, {
  required String platform,
  required String? sourceRunId,
  required List<Map<String, dynamic>> items,
}) async {
  final retryableItems = items
      .where((item) {
        final url = _mapString(item, 'url');
        return url != null && url.isNotEmpty;
      })
      .map(
        (item) => {
          'url': _mapString(item, 'url'),
          if (_mapString(item, 'title') != null)
            'title': _mapString(item, 'title'),
          if (_mapString(item, 'item_id') != null)
            'item_id': _mapString(item, 'item_id'),
        },
      )
      .toList(growable: false);
  if (retryableItems.isEmpty) {
    Toast.show(context, '失败项缺少 URL，无法重试', isError: true);
    return;
  }

  try {
    final retryRunId = await ref
        .read(favoritesSyncActionsProvider)
        .retryItems(
          platform: platform,
          items: retryableItems,
          sourceRunId: sourceRunId,
        );
    if (context.mounted) {
      Toast.show(
        context,
        '已批量重试 ${retryableItems.length} 个失败项${retryRunId == null ? '' : ' #${_shortId(retryRunId)}'}',
        action: retryRunId == null
            ? null
            : SnackBarAction(
                label: '查看日志',
                onPressed: () => context.go('/tasks/$retryRunId'),
              ),
      );
    }
  } catch (e) {
    if (context.mounted) {
      Toast.show(
        context,
        formatApiErrorMessage(e, fallbackMessage: '批量重试失败项失败'),
        isError: true,
      );
    }
  }
}

void _showRunDetail(BuildContext context, Map<String, dynamic> run) {
  final runId = _runString(run, 'run_id');
  final status = _runString(run, 'status') ?? 'unknown';
  showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('同步任务 ${_shortId(runId)}'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: _RunDetailContent(run: run, status: status),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
}

class _RunDetailContent extends StatelessWidget {
  const _RunDetailContent({required this.run, required this.status});

  final Map<String, dynamic> run;
  final String status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final platformResults = _extractPlatformResults(run);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DetailLine(label: '状态', value: _runStatusLabel(status)),
        _DetailLine(label: '范围', value: _runString(run, 'scope') ?? 'all'),
        _DetailLine(label: '触发', value: _runString(run, 'trigger') ?? '-'),
        _DetailLine(label: '开始', value: _runString(run, 'started_at') ?? '-'),
        _DetailLine(label: '结束', value: _runString(run, 'finished_at') ?? '-'),
        if (_runString(run, 'retry_of') != null)
          _DetailLine(label: '重试自', value: _runString(run, 'retry_of')!),
        if (_runString(run, 'error') != null)
          _DetailLine(label: '错误', value: _runString(run, 'error')!),
        if (platformResults.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            '结果摘要',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MetricChip(
                label: '拉取',
                value: _sumResultCount(platformResults, 'fetched'),
              ),
              _MetricChip(
                label: '导入',
                value: _sumResultCount(platformResults, 'imported'),
              ),
              _MetricChip(
                label: '跳过',
                value: _sumResultCount(platformResults, 'skipped'),
              ),
              _MetricChip(
                label: '失败',
                value: _sumResultCount(platformResults, 'failed'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final result in platformResults)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _PlatformRunResult(
                result: result,
                sourceRunId: _runString(run, 'run_id'),
              ),
            ),
        ] else if (run['result'] != null) ...[
          const SizedBox(height: 14),
          Text(
            '原始结果',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          SelectableText(
            run['result'].toString(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ],
    );
  }
}

class _PlatformRunResult extends ConsumerWidget {
  const _PlatformRunResult({required this.result, required this.sourceRunId});

  final Map<String, dynamic> result;
  final String? sourceRunId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final status = _mapString(result, 'status') ?? 'unknown';
    final platform = _mapString(result, 'platform') ?? 'unknown';
    final hasError = status == 'failed' || status == 'partial_success';
    final authRequired = result['auth_required'] == true;
    final retryable = result['retryable'] == true;
    final failedItems = _mapListOfMaps(result, 'failed_items');
    final failedItemsTotal = _mapInt(result, 'failed_items_total');
    final displayedFailedItems = failedItems.take(20).toList();
    final totalFailedItems = failedItemsTotal > 0
        ? failedItemsTotal
        : _mapInt(result, 'failed');
    final failedItemsTruncated = result['failed_items_truncated'] == true;
    final errorText =
        _mapString(result, 'error_hint') ??
        _mapString(result, 'error') ??
        _mapString(result, 'error_message');

    return DecoratedBox(
      decoration: BoxDecoration(
        color: hasError
            ? cs.errorContainer.withValues(alpha: 0.18)
            : cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: hasError
              ? cs.error.withValues(alpha: 0.35)
              : cs.outlineVariant,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  hasError
                      ? Icons.report_problem_outlined
                      : Icons.task_alt_rounded,
                  size: 18,
                  color: hasError ? cs.error : cs.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _platformLabel(platform),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  _platformRunStatusLabel(status),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: hasError ? cs.error : cs.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _MetricChip(label: '拉取', value: _mapInt(result, 'fetched')),
                _MetricChip(label: '导入', value: _mapInt(result, 'imported')),
                _MetricChip(label: '跳过', value: _mapInt(result, 'skipped')),
                _MetricChip(label: '失败', value: _mapInt(result, 'failed')),
              ],
            ),
            if (authRequired || retryable) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (authRequired) const Chip(label: Text('需要登录')),
                  if (retryable) const Chip(label: Text('可重试')),
                ],
              ),
            ],
            if (errorText != null) ...[
              const SizedBox(height: 8),
              Text(
                errorText,
                style: theme.textTheme.bodySmall?.copyWith(color: cs.error),
              ),
            ],
            if (failedItems.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      totalFailedItems > failedItems.length ||
                              failedItemsTruncated
                          ? '失败项 · 显示 ${displayedFailedItems.length} / $totalFailedItems'
                          : '失败项',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: cs.error,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: displayedFailedItems.isEmpty
                        ? null
                        : () => _retryFailedFavoriteItems(
                            context,
                            ref,
                            platform: platform,
                            sourceRunId: sourceRunId,
                            items: displayedFailedItems,
                          ),
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text('重试可见失败项'),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              for (final item in displayedFailedItems)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: _FailedFavoriteItem(
                    item: item,
                    onRetry: () => _retryFailedFavoriteItem(
                      context,
                      ref,
                      platform: platform,
                      sourceRunId: sourceRunId,
                      item: item,
                    ),
                  ),
                ),
              if (failedItemsTruncated ||
                  totalFailedItems > displayedFailedItems.length)
                Text(
                  failedItemsTruncated
                      ? '仍有失败项未写入本次运行结果，请缩小同步范围后重试。'
                      : '仍有失败项未在此处展开，可在运行结果中查看记录列表。',
                  style: theme.textTheme.bodySmall?.copyWith(color: cs.error),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FailedFavoriteItem extends StatelessWidget {
  const _FailedFavoriteItem({required this.item, required this.onRetry});

  final Map<String, dynamic> item;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final title = _mapString(item, 'title');
    final url = _mapString(item, 'url') ?? '-';
    final error = _mapString(item, 'error') ?? _mapString(item, 'error_code');

    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.errorContainer.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.error.withValues(alpha: 0.22)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null)
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            SelectableText(
              url,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            if (error != null) ...[
              const SizedBox(height: 4),
              Text(
                error,
                style: theme.textTheme.bodySmall?.copyWith(color: cs.error),
              ),
            ],
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: url == '-' ? null : onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('重试此项'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }
}

List<Map<String, dynamic>> _extractPlatformResults(Map<String, dynamic> run) {
  final result = run['result'];
  if (result is! Map) return const [];
  final normalized = Map<String, dynamic>.from(result);
  final allResults = normalized['results'];
  if (allResults is Map) {
    return allResults.values
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }
  final singleResult = normalized['result'];
  if (singleResult is Map) {
    return [Map<String, dynamic>.from(singleResult)];
  }
  if (normalized.containsKey('platform') && normalized.containsKey('status')) {
    return [normalized];
  }
  return const [];
}

int _sumResultCount(List<Map<String, dynamic>> results, String key) {
  return results.fold<int>(0, (sum, item) => sum + _mapInt(item, key));
}

int _mapInt(Map<String, dynamic> item, String key) {
  final value = item[key];
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? 0;
}

String? _mapString(Map<String, dynamic> item, String key) {
  final value = item[key];
  if (value == null) return null;
  final text = value.toString();
  return text.isEmpty ? null : text;
}

List<Map<String, dynamic>> _mapListOfMaps(
  Map<String, dynamic> item,
  String key,
) {
  final value = item[key];
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((entry) => Map<String, dynamic>.from(entry))
      .toList(growable: false);
}

String _platformRunStatusLabel(String status) {
  return switch (status) {
    'success' => '成功',
    'partial_success' => '部分成功',
    'failed' => '失败',
    'skipped' => '已跳过',
    _ => status,
  };
}

List<int> _withCurrentValue(List<int> values, int current) {
  final set = {current, ...values}.toList()..sort();
  return set;
}

Future<void> _updateFavoritesSyncSetting(
  BuildContext context,
  WidgetRef ref, {
  required String key,
  required Object value,
}) async {
  try {
    await ref
        .read(systemSettingsProvider.notifier)
        .updateSetting(key, value, category: 'favorites_sync');
    ref.invalidate(favoritesSyncStatusProvider);
    if (context.mounted) {
      Toast.show(context, '收藏同步参数已更新');
    }
  } catch (e) {
    if (context.mounted) {
      Toast.show(
        context,
        formatApiErrorMessage(e, fallbackMessage: '更新收藏同步参数失败'),
        isError: true,
      );
    }
  }
}

String _duplicateStrategyDescription(String strategy) {
  return switch (strategy) {
    'skip' => '导入阶段发现本地已有同一 canonical URL 时直接跳过。',
    _ => '导入阶段合并来源记录，并让已有内容继续执行必要后处理。',
  };
}

String _scopeStrategyDescription(String strategy) {
  return switch (strategy) {
    'collections_api_placeholder' => '保留收藏夹/分组范围接口抽象；平台适配完成前不影响当前全部收藏同步。',
    _ => '同步该平台当前可访问的全部收藏列表。',
  };
}

String _firstSyncStrategyDescription(String strategy) {
  return switch (strategy) {
    'full_backfill_placeholder' => '保留全量回填策略位；平台分页/分组能力接入前不会强制长链路抓取。',
    _ => '没有 cursor 时只拉取当前默认页，避免首次同步失控。',
  };
}

String _unfavoriteStrategyDescription(String strategy) {
  return switch (strategy) {
    'mark_archived_placeholder' => '保留远端取消收藏后的本地归档策略位；真实差异检测接入前不改动本地内容。',
    _ => '远端取消收藏不会自动删除或归档本地内容。',
  };
}

String? _runString(Map<String, dynamic> run, String key) {
  final value = run[key];
  if (value == null) return null;
  final text = value.toString();
  return text.isEmpty ? null : text;
}

String _shortId(String? runId) {
  if (runId == null || runId.isEmpty) return '-';
  return runId.length > 8 ? runId.substring(0, 8) : runId;
}

String _runStatusLabel(String status) {
  return switch (status) {
    'success' => '成功',
    'running' => '运行中',
    'error' => '失败',
    _ => status,
  };
}

String _platformLabel(String platform) {
  return switch (platform) {
    'zhihu' => '知乎',
    'xiaohongshu' => '小红书',
    'twitter' => 'Twitter / X',
    _ => platform,
  };
}

IconData _platformIcon(String platform) {
  return switch (platform) {
    'zhihu' => Icons.question_answer_rounded,
    'xiaohongshu' => Icons.menu_book_rounded,
    'twitter' => Icons.alternate_email_rounded,
    _ => Icons.bookmarks_rounded,
  };
}

String _platformStateLabel(FavoritesPlatformStatus status) {
  if (!status.available) return '不可用';
  if (!status.enabled) return '未启用';
  if (!status.authenticated) return '未认证';
  return '可同步';
}
