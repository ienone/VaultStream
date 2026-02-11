import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../models/bot_chat.dart';

class BotChatCard extends StatelessWidget {
  final BotChat chat;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final ValueChanged<bool>? onToggleEnabled;
  final int index;

  const BotChatCard({
    super.key,
    required this.chat,
    this.onTap,
    this.onEdit,
    this.onDelete,
    this.onToggleEnabled,
    this.index = 0,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final typeColor = _getChatTypeColor(colorScheme);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: BorderSide(
          color: chat.enabled 
            ? typeColor.withValues(alpha: 0.3) 
            : colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      color: chat.enabled 
        ? typeColor.withValues(alpha: 0.03) 
        : colorScheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: typeColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      _getChatTypeIcon(),
                      color: typeColor,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          chat.displayName,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.5,
                          ),
                        ),
                        if (chat.username != null)
                          Text(
                            '@${chat.username}',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colorScheme.primary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Switch(
                    value: chat.enabled,
                    onChanged: onToggleEnabled,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildStatBadge(
                    context,
                    icon: _getChatTypeIcon(),
                    label: chat.chatTypeLabel,
                    color: typeColor,
                  ),
                  if (!chat.isAccessible)
                    _buildStatBadge(
                      context,
                      icon: Icons.warning_amber_rounded,
                      label: '无法访问',
                      color: Colors.orange,
                    ),
                  if (chat.isAdmin)
                    _buildStatBadge(
                      context,
                      icon: Icons.verified_user_rounded,
                      label: '管理员',
                      color: Colors.green,
                    ),
                  _buildStatBadge(
                    context,
                    icon: Icons.rocket_launch_rounded,
                    label: '已推 ${chat.totalPushed}',
                    color: colorScheme.tertiary,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (chat.lastPushedAt != null)
                    Row(
                      children: [
                        Icon(Icons.history_rounded, size: 14, color: colorScheme.outline),
                        const SizedBox(width: 6),
                        Text(
                          '最后推送: ${_formatDateTime(chat.lastPushedAt!)}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    )
                  else
                    const SizedBox.shrink(),
                  Row(
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: onEdit,
                        icon: const Icon(Icons.settings_outlined, size: 18),
                        label: const Text('配置'),
                        style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        onPressed: onDelete,
                        icon: const Icon(Icons.delete_outline_rounded, size: 18),
                        style: IconButton.styleFrom(
                          foregroundColor: colorScheme.error,
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    )
    .animate()
    .fadeIn(delay: (index * 100).ms, duration: 500.ms)
    .slideY(begin: 0.2, end: 0, curve: Curves.easeOutCubic, delay: (index * 100).ms);
  }

  Widget _buildStatBadge(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  IconData _getChatTypeIcon() {
    switch (chat.chatType) {
      case 'channel': return Icons.campaign_rounded;
      case 'group': return Icons.group_rounded;
      case 'supergroup': return Icons.groups_rounded;
      case 'private': return Icons.person_rounded;
      case 'qq_group': return Icons.forum_rounded;
      case 'qq_private': return Icons.chat_rounded;
      default: return Icons.chat_bubble_rounded;
    }
  }

  Color _getChatTypeColor(ColorScheme colorScheme) {
    switch (chat.chatType) {
      case 'channel': return colorScheme.primary;
      case 'group': return colorScheme.secondary;
      case 'supergroup': return colorScheme.tertiary;
      case 'private': return Colors.orange;
      case 'qq_group': return Colors.blue;
      case 'qq_private': return Colors.lightBlue;
      default: return colorScheme.outline;
    }
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}