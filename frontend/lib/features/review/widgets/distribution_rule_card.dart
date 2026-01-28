import 'package:flutter/material.dart';
import '../models/distribution_rule.dart';

class DistributionRuleCard extends StatelessWidget {
  final DistributionRule rule;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final ValueChanged<bool>? onToggleEnabled;

  const DistributionRuleCard({
    super.key,
    required this.rule,
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
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          rule.name,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (rule.description != null &&
                            rule.description!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              rule.description!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Switch(
                    value: rule.enabled,
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
                    icon: Icons.priority_high,
                    label: '优先级: ${rule.priority}',
                    color: colorScheme.tertiary,
                  ),
                  _buildChip(
                    context,
                    icon: _getNsfwIcon(rule.nsfwPolicy),
                    label: _getNsfwLabel(rule.nsfwPolicy),
                    color: _getNsfwColor(rule.nsfwPolicy, colorScheme),
                  ),
                  if (rule.approvalRequired)
                    _buildChip(
                      context,
                      icon: Icons.approval,
                      label: '需审批',
                      color: colorScheme.secondary,
                    ),
                  if (rule.targets.isNotEmpty)
                    _buildChip(
                      context,
                      icon: Icons.send,
                      label: '${rule.targets.length} 个目标',
                      color: colorScheme.primary,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit, size: 18),
                    label: const Text('编辑'),
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

  IconData _getNsfwIcon(String policy) {
    switch (policy) {
      case 'allow':
        return Icons.check_circle;
      case 'block':
        return Icons.block;
      case 'separate_channel':
        return Icons.call_split;
      default:
        return Icons.help;
    }
  }

  String _getNsfwLabel(String policy) {
    switch (policy) {
      case 'allow':
        return 'NSFW: 允许';
      case 'block':
        return 'NSFW: 阻止';
      case 'separate_channel':
        return 'NSFW: 分离';
      default:
        return 'NSFW: $policy';
    }
  }

  Color _getNsfwColor(String policy, ColorScheme colorScheme) {
    switch (policy) {
      case 'allow':
        return Colors.green;
      case 'block':
        return colorScheme.error;
      case 'separate_channel':
        return Colors.orange;
      default:
        return colorScheme.outline;
    }
  }
}
