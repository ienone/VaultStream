import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../review/providers/bot_chats_provider.dart';

class BotOverviewCard extends ConsumerWidget {
  const BotOverviewCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(botStatusProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(32),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      color: colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: statusAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text('加载失败', style: TextStyle(color: colorScheme.error)),
          data: (status) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: status.isRunning ? Colors.green : Colors.red,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: (status.isRunning ? Colors.green : Colors.red).withValues(alpha: 0.4),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    status.isRunning ? 'Bot 运行中' : 'Bot 离线',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _buildStatRow(context, Icons.groups_rounded, '活跃群组', '${status.connectedChats}'),
              const SizedBox(height: 12),
              _buildStatRow(context, Icons.send_rounded, '今日推送', '${status.totalPushedToday}'),
              const SizedBox(height: 12),
              _buildStatRow(context, Icons.timer_outlined, '在线时间', status.uptimeFormatted),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonal(
                  onPressed: () => ref.invalidate(botStatusProvider),
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text('刷新状态'),
                ),
              ),
            ],
          ),
        ),
      ),
    ).animate().fadeIn().slideY(begin: 0.1, end: 0);
  }

  Widget _buildStatRow(BuildContext context, IconData icon, String label, String value) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.outline),
        const SizedBox(width: 12),
        Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const Spacer(),
        Text(value, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.primary)),
      ],
    );
  }
}
