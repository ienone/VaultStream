import 'package:flutter/material.dart';
import '../models/bot_chat.dart';

class BotChatCard extends StatelessWidget {
  final BotChat chat;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final ValueChanged<bool>? onToggleEnabled;

  const BotChatCard({
    super.key,
    required this.chat,
    this.onTap,
    this.onEdit,
    this.onDelete,
    this.onToggleEnabled,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _getChatTypeColor(colorScheme).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      _getChatTypeIcon(),
                      color: _getChatTypeColor(colorScheme),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          chat.displayName,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (chat.username != null)
                          Text(
                            '@${chat.username}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.primary,
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
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  _buildChip(
                    context,
                    icon: _getChatTypeIcon(),
                    label: chat.chatTypeLabel,
                    color: _getChatTypeColor(colorScheme),
                  ),
                  if (!chat.isAccessible)
                    _buildChip(
                      context,
                      icon: Icons.warning_amber,
                      label: '不可访问',
                      color: Colors.orange,
                    ),
                  if (chat.isAdmin)
                    _buildChip(
                      context,
                      icon: Icons.admin_panel_settings,
                      label: '管理员',
                      color: Colors.green,
                    ),
                  if (chat.canPost)
                    _buildChip(
                      context,
                      icon: Icons.send,
                      label: '可发送',
                      color: Colors.blue,
                    ),
                  _buildChip(
                    context,
                    icon: Icons.upload,
                    label: '已推送 ${chat.totalPushed}',
                    color: colorScheme.tertiary,
                  ),
                  if (chat.linkedRuleIds.isNotEmpty)
                    _buildChip(
                      context,
                      icon: Icons.rule,
                      label: '${chat.linkedRuleIds.length} 规则',
                      color: colorScheme.secondary,
                    ),
                ],
              ),
              if (chat.tagFilter.isNotEmpty || chat.platformFilter.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    ...chat.tagFilter.map((tag) => Chip(
                      label: Text(tag, style: const TextStyle(fontSize: 10)),
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      backgroundColor: colorScheme.primaryContainer,
                    )),
                    ...chat.platformFilter.map((platform) => Chip(
                      label: Text(platform, style: const TextStyle(fontSize: 10)),
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      backgroundColor: colorScheme.secondaryContainer,
                    )),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (chat.lastPushedAt != null)
                    Text(
                      '最后推送: ${_formatDateTime(chat.lastPushedAt!)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    )
                  else
                    const SizedBox.shrink(),
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: onEdit,
                        icon: const Icon(Icons.edit, size: 18),
                        label: const Text('配置'),
                      ),
                      TextButton.icon(
                        onPressed: onDelete,
                        icon: Icon(Icons.delete, size: 18, color: colorScheme.error),
                        label: Text('删除', style: TextStyle(color: colorScheme.error)),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChip(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: color),
          ),
        ],
      ),
    );
  }

  IconData _getChatTypeIcon() {
    switch (chat.chatType) {
      case 'channel':
        return Icons.campaign;
      case 'group':
        return Icons.group;
      case 'supergroup':
        return Icons.groups;
      case 'private':
        return Icons.person;
      default:
        return Icons.chat;
    }
  }

  Color _getChatTypeColor(ColorScheme colorScheme) {
    switch (chat.chatType) {
      case 'channel':
        return colorScheme.primary;
      case 'group':
        return colorScheme.secondary;
      case 'supergroup':
        return colorScheme.tertiary;
      case 'private':
        return Colors.orange;
      default:
        return colorScheme.outline;
    }
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
