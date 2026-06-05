import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../core/utils/toast.dart';
import '../../settings/providers/favorites_sync_provider.dart';
import '../../settings/providers/settings_provider.dart';

class FavoritesSyncAutomationPanel extends ConsumerWidget {
  const FavoritesSyncAutomationPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(favoritesSyncStatusProvider);

    return statusAsync.when(
      data: (status) => RefreshIndicator(
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
      ),
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
            const _PolicyLine(
              icon: Icons.difference_rounded,
              label: '重复处理',
              value: '预览会区分预计新增和已存在；导入时跳过重复内容，不覆盖已有收藏。',
            ),
            const _PolicyLine(
              icon: Icons.delete_outline_rounded,
              label: '取消收藏',
              value: '当前不会因为远端取消收藏而自动删除本地收藏。',
            ),
            const _PolicyLine(
              icon: Icons.replay_rounded,
              label: '失败恢复',
              value: '当前支持 run 级失败重试；尚未细化到单条失败候选重试。',
            ),
          ],
        ),
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
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    item.status == 'failed'
                        ? '${_platformLabel(item.platform)}: ${item.errorHint ?? item.error ?? '预览失败'}'
                        : '${_platformLabel(item.platform)}: 新增 ${item.estimatedNew}，重复 ${item.existing}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: item.status == 'failed' ? cs.error : null,
                    ),
                  ),
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
              child: _PlatformRunResult(result: result),
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

class _PlatformRunResult extends StatelessWidget {
  const _PlatformRunResult({required this.result});

  final Map<String, dynamic> result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final status = _mapString(result, 'status') ?? 'unknown';
    final hasError = status == 'failed' || status == 'partial_success';
    final authRequired = result['auth_required'] == true;
    final retryable = result['retryable'] == true;
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
                    _platformLabel(_mapString(result, 'platform') ?? 'unknown'),
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
  required int value,
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
