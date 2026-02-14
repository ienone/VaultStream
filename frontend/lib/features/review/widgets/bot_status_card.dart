import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../providers/bot_chats_provider.dart';
import '../models/bot_chat.dart';

class BotStatusCard extends ConsumerWidget {
  final VoidCallback? onSync;
  final VoidCallback? onTriggerPush;
  final bool isSyncing;

  const BotStatusCard({
    super.key,
    this.onSync,
    this.onTriggerPush,
    this.isSyncing = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(botStatusProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(32),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      color: colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: statusAsync.when(
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(),
            ),
          ),
          error: (e, st) => Column(
            children: [
              Icon(Icons.error_outline_rounded, size: 48, color: colorScheme.error),
              const SizedBox(height: 16),
              Text('Bot 状态加载失败', style: theme.textTheme.titleMedium?.copyWith(color: colorScheme.error)),
              const SizedBox(height: 8),
              FilledButton.tonal(
                onPressed: () => ref.invalidate(botStatusProvider),
                child: const Text('重试'),
              ),
            ],
          ),
          data: (status) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildBotRow(context, ref, status, theme, colorScheme),
              const SizedBox(height: 24),
              const Divider(height: 1),
              const SizedBox(height: 24),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _buildStatChip(
                    context,
                    icon: Icons.groups_rounded,
                    label: '${status.connectedChats} 个群组',
                    color: colorScheme.primary,
                  ),
                  _buildStatChip(
                    context,
                    icon: Icons.send_rounded,
                    label: '今日推送 ${status.totalPushedToday}',
                    color: colorScheme.secondary,
                  ),
                  if (status.uptimeSeconds != null)
                    _buildStatChip(
                      context,
                      icon: Icons.timer_outlined,
                      label: 'TG 在线 ${status.uptimeFormatted}',
                      color: colorScheme.tertiary,
                    ),
                ],
              ),
              if (status.parseStats != null) ...[
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _buildStatChip(
                      context,
                      icon: Icons.inbox_rounded,
                      label: '未处理 ${status.parseStats!.unprocessed}',
                      color: colorScheme.outline,
                    ),
                    _buildStatChip(
                      context,
                      icon: Icons.sync_rounded,
                      label: '解析中 ${status.parseStats!.processing}',
                      color: colorScheme.primary,
                    ),
                    _buildStatChip(
                      context,
                      icon: Icons.check_circle_rounded,
                      label: '解析成功 ${status.parseStats!.parseSuccess}',
                      color: Colors.green,
                    ),
                    _buildStatChip(
                      context,
                      icon: Icons.error_outline_rounded,
                      label: '解析失败 ${status.parseStats!.parseFailed}',
                      color: colorScheme.error,
                    ),
                  ],
                ),
              ],
              if (status.distributionStats != null) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _buildStatChip(
                      context,
                      icon: Icons.schedule_send_rounded,
                      label: '待推送 ${status.distributionStats!.willPush}',
                      color: colorScheme.primary,
                    ),
                    _buildStatChip(
                      context,
                      icon: Icons.filter_alt_off_rounded,
                      label: '已过滤 ${status.distributionStats!.filtered}',
                      color: colorScheme.secondary,
                    ),
                    _buildStatChip(
                      context,
                      icon: Icons.rate_review_rounded,
                      label: '待审阅 ${status.distributionStats!.pendingReview}',
                      color: colorScheme.tertiary,
                    ),
                    _buildStatChip(
                      context,
                      icon: Icons.send_rounded,
                      label: '已推送 ${status.distributionStats!.pushed}',
                      color: Colors.green,
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 32),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: isSyncing ? null : onSync,
                      icon: isSyncing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2.5),
                            )
                          : const Icon(Icons.sync_rounded),
                      label: Text(isSyncing ? '同步中...' : '同步群组'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onTriggerPush,
                      icon: const Icon(Icons.rocket_launch_rounded),
                      label: const Text('立即推送'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                    ),
                  ).animate(onPlay: (c) => c.repeat()).shimmer(delay: 3.seconds, duration: 2.seconds, color: Colors.white24),
                ],
              ),
            ],
          ),
        ),
      ),
    ).animate().fadeIn().scale(begin: const Offset(0.98, 0.98), curve: Curves.easeOutCubic);
  }

  Widget _buildBotRow(BuildContext context, WidgetRef ref, BotStatus status, ThemeData theme, ColorScheme colorScheme) {
    return Column(
      children: [
        Row(
          children: [
            _buildStatusIndicator(status.isRunning, colorScheme, Icons.smart_toy_rounded),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Telegram Bot',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(width: 12),
                      _buildStatusBadge(status.isRunning),
                    ],
                  ),
                  if (status.botUsername != null)
                    Text(
                      '@${status.botUsername}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ),
            IconButton.filledTonal(
              onPressed: () => ref.invalidate(botStatusProvider),
              icon: const Icon(Icons.refresh_rounded),
              tooltip: '刷新状态',
            ),
          ],
        ),
        if (status.isNapcatEnabled) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              _buildStatusIndicator(status.isNapcatOnline, colorScheme, Icons.forum_rounded),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'QQ Bot (Napcat)',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(width: 12),
                        _buildStatusBadge(status.isNapcatOnline, labels: _napcatStatusLabel(status.napcatStatus)),
                      ],
                    ),
                    if (!status.isNapcatOnline && status.napcatStatus != null)
                      Text(
                        _napcatStatusDetail(status.napcatStatus!),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.error,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  (String, String) _napcatStatusLabel(String? status) {
    if (status == 'online') return ('在线', '离线');
    if (status == 'misconfigured') return ('配置异常', '配置异常');
    if (status != null && status.startsWith('offline:')) return ('离线', '离线');
    if (status != null && status.startsWith('error:')) return ('异常', '异常');
    return ('在线', '离线');
  }

  String _napcatStatusDetail(String status) {
    if (status == 'misconfigured') return '未配置 NAPCAT_API_BASE';
    if (status.startsWith('offline:')) return '无法连接 Napcat 服务';
    if (status.startsWith('error:')) return 'Napcat 返回 ${status.substring(6)}';
    return status;
  }

  Widget _buildStatusIndicator(bool isRunning, ColorScheme colorScheme, IconData icon) {
    final color = isRunning ? Colors.green : Colors.red;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        shape: BoxShape.circle,
      ),
      child: Icon(
        icon,
        color: color,
        size: 32,
      ),
    ).animate(onPlay: (c) => isRunning ? c.repeat(reverse: true) : c.stop())
     .shimmer(duration: 2.seconds, color: isRunning ? Colors.greenAccent.withValues(alpha: 0.3) : null);
  }

  Widget _buildStatusBadge(bool isRunning, {(String, String)? labels}) {
    final color = isRunning ? Colors.green : Colors.red;
    final runLabel = labels?.$1 ?? '运行中';
    final stopLabel = labels?.$2 ?? '离线';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Text(
        isRunning ? runLabel : stopLabel,
        style: TextStyle(
          fontSize: 12,
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildStatChip(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.1)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
