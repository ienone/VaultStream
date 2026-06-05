import 'package:flutter/material.dart';

import '../../discovery/models/discovery_models.dart';
import '../models/stats.dart';

class ActionSummaryCard extends StatelessWidget {
  const ActionSummaryCard({
    super.key,
    required this.queue,
    required this.discovery,
    required this.diagnostics,
    required this.onOpenBacklog,
    required this.onOpenFailures,
    required this.onOpenInbox,
    required this.onOpenAutomation,
  });

  final QueueOverviewStats queue;
  final DiscoveryStats discovery;
  final BackgroundTaskDiagnostics diagnostics;
  final VoidCallback onOpenBacklog;
  final VoidCallback onOpenFailures;
  final VoidCallback onOpenInbox;
  final VoidCallback onOpenAutomation;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final parseBacklog = queue.parse.unprocessed + queue.parse.processing;
    final parseFailures = queue.parse.parseFailed;
    final distributionPending = queue.distribution.willPush;
    final inboxVisible =
        discovery.byState['visible'] ??
        discovery.byState['new'] ??
        discovery.total;
    final failureCount = diagnostics.totalFailures > parseFailures
        ? diagnostics.totalFailures
        : parseFailures;
    final pendingCount = parseBacklog + distributionPending + inboxVisible;
    final hasFailures = failureCount > 0;
    final hasPending = pendingCount > 0;

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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color:
                        (hasFailures ? colorScheme.error : colorScheme.primary)
                            .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    hasFailures
                        ? Icons.priority_high_rounded
                        : Icons.bolt_rounded,
                    color: hasFailures
                        ? colorScheme.error
                        : colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hasFailures
                            ? '有 $failureCount 个异常需要处理'
                            : hasPending
                            ? '有 $pendingCount 个待处理动态'
                            : '暂无需要立即处理的事项',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        hasFailures
                            ? '优先处理后台失败、解析失败和分发异常，再查看同步与收件箱结果。'
                            : hasPending
                            ? '系统已汇总解析积压、待分发内容和收件箱候选。'
                            : '后台任务、队列和收件箱当前没有明显积压。',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _MetricButton(
                  label: '解析积压',
                  value: parseBacklog,
                  icon: Icons.hourglass_top_rounded,
                  color: colorScheme.tertiary,
                  onPressed: onOpenBacklog,
                ),
                _MetricButton(
                  label: '失败异常',
                  value: failureCount,
                  icon: Icons.report_problem_outlined,
                  color: colorScheme.error,
                  onPressed: onOpenFailures,
                ),
                _MetricButton(
                  label: '待分发',
                  value: distributionPending,
                  icon: Icons.outbox_rounded,
                  color: colorScheme.secondary,
                  onPressed: onOpenAutomation,
                ),
                _MetricButton(
                  label: '收件箱',
                  value: inboxVisible,
                  icon: Icons.inbox_rounded,
                  color: colorScheme.primary,
                  onPressed: onOpenInbox,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricButton extends StatelessWidget {
  const _MetricButton({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  final String label;
  final int value;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: 148,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.all(12),
          side: BorderSide(color: color.withValues(alpha: 0.25)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value.toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
