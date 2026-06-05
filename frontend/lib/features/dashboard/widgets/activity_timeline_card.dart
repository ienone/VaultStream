import 'package:flutter/material.dart';

import '../models/stats.dart';

class ActivityTimelineCard extends StatelessWidget {
  const ActivityTimelineCard({
    super.key,
    required this.runs,
    required this.onOpenTask,
  });

  final List<BackgroundTaskRun> runs;
  final void Function(BackgroundTaskRun run) onOpenTask;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final displayRuns = runs.take(8).toList(growable: false);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.timeline_rounded, color: cs.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '最近后台运行',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  '${displayRuns.length}',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (displayRuns.isEmpty)
              Text(
                '暂无后台运行记录',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              )
            else
              for (final entry in displayRuns.indexed) ...[
                _TimelineRow(
                  run: entry.$2,
                  isLast: entry.$1 == displayRuns.length - 1,
                  onOpen: () => onOpenTask(entry.$2),
                ),
              ],
          ],
        ),
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.run,
    required this.isLast,
    required this.onOpen,
  });

  final BackgroundTaskRun run;
  final bool isLast;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final color = _statusColor(cs, run.status);
    final started = run.startedAt?.toLocal();
    final error = run.error;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 26,
          child: Column(
            children: [
              Container(
                width: 12,
                height: 12,
                margin: const EdgeInsets.only(top: 8),
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              if (!isLast)
                Container(
                  width: 2,
                  height: error == null ? 42 : 58,
                  color: cs.outlineVariant,
                ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        _taskLabel(run.task),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _statusLabel(run.status),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (started != null) _formatLocalTime(started),
                    '#${run.shortRunId}',
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                if (error != null && error.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    error,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: cs.error),
                  ),
                ],
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: onOpen,
                    icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                    label: const Text('查看'),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(48, 28),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

Color _statusColor(ColorScheme colorScheme, String status) {
  return switch (status) {
    'success' || 'ok' => Colors.green,
    'running' => colorScheme.primary,
    'error' || 'failed' => colorScheme.error,
    _ => colorScheme.onSurfaceVariant,
  };
}

String _statusLabel(String status) {
  return switch (status) {
    'success' => '成功',
    'running' => '运行中',
    'error' || 'failed' => '失败',
    _ => status,
  };
}

String _taskLabel(String task) {
  return switch (task) {
    'favorites_sync' => '收藏同步',
    'discovery_sync' => '发现源同步',
    'discovery_patrol' => 'AI 巡逻',
    'content_parse' => '内容解析',
    'content_embedding' => '语义索引',
    'content_reparse' => '重新解析',
    'content_summary' => '摘要生成',
    'distribution_push' => '内容推送',
    'distribution_schedule' => '分发排期',
    'distribution_worker_poll' => '分发轮询',
    'semantic_reindex' => '索引重建',
    _ => task,
  };
}

String _formatLocalTime(DateTime value) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(value.month)}/${two(value.day)} ${two(value.hour)}:${two(value.minute)}';
}
