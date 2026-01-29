import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../models/stats.dart';

class HealthStatusCard extends StatelessWidget {
  final SystemHealth health;

  const HealthStatusCard({super.key, required this.health});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isOk = health.status == 'ok';
    final dbOk = health.components?['db'] == 'ok';
    
    final statusColor = isOk ? Colors.green : colorScheme.error;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(32),
        side: BorderSide(
          color: statusColor.withValues(alpha: 0.2),
          width: 1.5,
        ),
      ),
      color: statusColor.withValues(alpha: 0.03),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Row(
              children: [
                _buildStatusIcon(isOk, statusColor),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isOk ? '系统正常' : '服务异常',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: statusColor,
                        ),
                      ),
                      if (health.queueSize != null)
                        Text(
                          '队列任务: ${health.queueSize}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Divider(height: 1),
            const SizedBox(height: 20),
            _ComponentBadge(name: 'API & Database', isOk: dbOk),
          ],
        ),
      ),
    )
    .animate()
    .fadeIn(delay: 200.ms)
    .scale(begin: const Offset(0.95, 0.95), end: const Offset(1, 1), curve: Curves.easeOutBack);
  }

  Widget _buildStatusIcon(bool isOk, Color color) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        shape: BoxShape.circle,
      ),
      child: Icon(
        isOk ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
        color: color,
        size: 24,
      ),
    )
    .animate(onPlay: (controller) => isOk ? controller.repeat(reverse: true) : null)
    .shimmer(delay: 2.seconds, duration: 1.5.seconds, color: Colors.white24);
  }
}

class _ComponentBadge extends StatelessWidget {
  final String name;
  final bool isOk;

  const _ComponentBadge({required this.name, required this.isOk});

  @override
  Widget build(BuildContext context) {
    final color = isOk ? Colors.green : Theme.of(context).colorScheme.error;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(isOk ? Icons.done_all_rounded : Icons.close_rounded, size: 14, color: color),
          const SizedBox(width: 8),
          Text(
            name,
            style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12),
          ),
        ],
      ),
    );
  }
}