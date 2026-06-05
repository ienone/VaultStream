import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/utils/toast.dart';
import '../../settings/providers/favorites_sync_provider.dart';

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
          child: SelectableText(
            [
              '状态: ${_runStatusLabel(status)}',
              '范围: ${_runString(run, 'scope') ?? 'all'}',
              '触发: ${_runString(run, 'trigger') ?? '-'}',
              '开始: ${_runString(run, 'started_at') ?? '-'}',
              '结束: ${_runString(run, 'finished_at') ?? '-'}',
              if (_runString(run, 'retry_of') != null)
                '重试自: ${_runString(run, 'retry_of')}',
              if (_runString(run, 'error') != null)
                '错误: ${_runString(run, 'error')}',
              if (run['result'] != null) '结果: ${run['result']}',
            ].join('\n'),
          ),
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
