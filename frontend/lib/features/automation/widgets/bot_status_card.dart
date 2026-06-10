import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../providers/bot_chats_provider.dart';
import '../models/bot_chat.dart';

class BotStatusCard extends ConsumerWidget {
  final VoidCallback? onSync;
  final VoidCallback? onRefreshStatus;
  final VoidCallback? onStartTelegram;
  final VoidCallback? onStopTelegram;
  final VoidCallback? onRestartTelegram;
  final bool isSyncing;
  final bool isControllingTelegram;

  const BotStatusCard({
    super.key,
    this.onSync,
    this.onRefreshStatus,
    this.onStartTelegram,
    this.onStopTelegram,
    this.onRestartTelegram,
    this.isSyncing = false,
    this.isControllingTelegram = false,
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
              _buildBotRow(context, status, theme, colorScheme),
              const SizedBox(height: 24),
              const Divider(height: 1),
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
                    child: FilledButton.tonalIcon(
                      onPressed: onRefreshStatus,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('刷新状态'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: isControllingTelegram ? null : onStartTelegram,
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('启动'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: isControllingTelegram ? null : onStopTelegram,
                      icon: const Icon(Icons.stop_rounded),
                      label: const Text('停止'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: isControllingTelegram ? null : onRestartTelegram,
                      icon: isControllingTelegram
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.restart_alt_rounded),
                      label: Text(isControllingTelegram ? '处理中...' : '重启'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ).animate().fadeIn().scale(begin: const Offset(0.98, 0.98), curve: Curves.easeOutCubic);
  }

  Widget _buildBotRow(BuildContext context, BotStatus status, ThemeData theme, ColorScheme colorScheme) {
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
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
              ),
            ),
          ],
        ),
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

}
