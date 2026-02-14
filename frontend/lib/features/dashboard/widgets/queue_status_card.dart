import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../models/stats.dart';

class QueueStatusCard extends StatelessWidget {
  final QueueOverviewStats queue;

  const QueueStatusCard({super.key, required this.queue});

  @override
  Widget build(BuildContext context) {
    final parse = queue.parse;
    final distribution = queue.distribution;
    final total = parse.total;
    if (total == 0) return const Center(child: Text('队列为空'));

    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(32),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            _buildQueueRow(
              context,
              '未处理',
              parse.unprocessed,
              total,
              colorScheme.tertiary,
              0,
            ),
            const SizedBox(height: 16),
            _buildQueueRow(
              context,
              '解析中',
              parse.processing,
              total,
              colorScheme.primary,
              1,
            ),
            const SizedBox(height: 16),
            _buildQueueRow(
              context,
              '解析成功',
              parse.parseSuccess,
              total,
              colorScheme.secondary,
              2,
            ),
            const SizedBox(height: 16),
            _buildQueueRow(
              context,
              '解析失败',
              parse.parseFailed,
              total,
              colorScheme.error,
              3,
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _StatusChip(label: '待推送 ${distribution.willPush}', color: colorScheme.primary),
                _StatusChip(label: '已过滤 ${distribution.filtered}', color: colorScheme.secondary),
                _StatusChip(label: '待审阅 ${distribution.pendingReview}', color: colorScheme.tertiary),
                _StatusChip(label: '已推送 ${distribution.pushed}', color: Colors.green),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQueueRow(
    BuildContext context,
    String label,
    int value,
    int total,
    Color color,
    int index,
  ) {
    final percent = total > 0 ? value / total : 0.0;
    return Row(
      children: [
        Container(
          width: 8,
          height: 32,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 3,
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(
          flex: 6,
          child: Stack(
            children: [
              Container(
                height: 10,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
              FractionallySizedBox(
                widthFactor: percent,
                child: Container(
                  height: 10,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [color, color.withValues(alpha: 0.7)],
                    ),
                    borderRadius: BorderRadius.circular(5),
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.3),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ).animate().shimmer(delay: (index * 200).ms, duration: 1.5.seconds),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        SizedBox(
          width: 90,
          child: Text(
            '$value (${(percent * 100).toStringAsFixed(1)}%)',
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontFeatures: [const FontFeature.tabularFigures()],
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
      ],
    ).animate().fadeIn(delay: (index * 100).ms).slideX(begin: 0.1, end: 0);
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }
}
