import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/stats.dart';

class BackgroundDiagnosticsCard extends StatelessWidget {
  const BackgroundDiagnosticsCard({super.key, required this.diagnostics});

  final BackgroundTaskDiagnostics diagnostics;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasFailures = diagnostics.totalFailures > 0;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  hasFailures
                      ? Icons.report_problem_outlined
                      : Icons.task_alt_rounded,
                  color: hasFailures ? colorScheme.error : Colors.green,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    hasFailures ? '后台任务存在失败' : '后台任务正常',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text('${diagnostics.totalFailures}'),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _CountChip(
                  label: '解析失败',
                  count: diagnostics.failedParseTasks.length,
                ),
                _CountChip(
                  label: '分发失败',
                  count: diagnostics.failedDistributionItems.length,
                ),
                _CountChip(
                  label: '发现源错误',
                  count: diagnostics.failedDiscoverySources.length,
                ),
                _CountChip(
                  label: '任务错误',
                  count: diagnostics.taskStates
                      .where((state) => state.status == 'error')
                      .length,
                ),
              ],
            ),
            if (hasFailures) ...[
              const SizedBox(height: 12),
              ..._failureLines()
                  .take(5)
                  .map(
                    (line) => Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.subdirectory_arrow_right_rounded,
                            size: 16,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              line,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
            ],
            if (diagnostics.recentTaskRuns.isNotEmpty) ...[
              const SizedBox(height: 16),
              Divider(color: colorScheme.outlineVariant),
              const SizedBox(height: 4),
              Text(
                '最近运行',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              ...diagnostics.recentTaskRuns
                  .take(5)
                  .map((run) => _TaskRunRow(run: run)),
            ],
          ],
        ),
      ),
    );
  }

  Iterable<String> _failureLines() sync* {
    for (final task in diagnostics.failedParseTasks) {
      yield '解析任务 #${task.id}: ${task.lastError ?? '无错误详情'}';
    }
    for (final item in diagnostics.failedDistributionItems) {
      yield '分发队列 #${item.id}: ${item.title ?? item.contentId} -> ${item.targetPlatform}/${item.targetId}';
    }
    for (final source in diagnostics.failedDiscoverySources) {
      yield '发现源 ${source.name}: ${source.lastError ?? '无错误详情'}';
    }
    for (final state in diagnostics.taskStates.where(
      (s) => s.status == 'error',
    )) {
      yield '任务 ${state.task}: ${state.lastError ?? '无错误详情'}';
    }
  }
}

class _TaskRunRow extends StatelessWidget {
  const _TaskRunRow({required this.run});

  final BackgroundTaskRun run;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final statusColor = _statusColor(colorScheme, run.status);
    final started = run.startedAt?.toLocal();

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => context.push('/tasks/${Uri.encodeComponent(run.runId)}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(Icons.history_rounded, size: 18, color: statusColor),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    run.task,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '#${run.shortRunId}${started == null ? '' : ' · ${_formatLocalTime(started)}'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              run.status,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: statusColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
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

String _formatLocalTime(DateTime value) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(value.month)}/${two(value.day)} ${two(value.hour)}:${two(value.minute)}';
}

class _CountChip extends StatelessWidget {
  const _CountChip({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = count > 0 ? colorScheme.error : colorScheme.primary;
    return Chip(
      visualDensity: VisualDensity.compact,
      side: BorderSide(color: color.withValues(alpha: 0.25)),
      backgroundColor: color.withValues(alpha: 0.08),
      label: Text('$label $count'),
    );
  }
}
