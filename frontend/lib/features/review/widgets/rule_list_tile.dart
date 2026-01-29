import 'package:flutter/material.dart';
import '../models/distribution_rule.dart';

class RuleListTile extends StatefulWidget {
  const RuleListTile({
    super.key,
    required this.rule,
    required this.isSelected,
    required this.onTap,
    this.onEdit,
    this.onDelete,
    this.onToggleEnabled,
  });

  final DistributionRule rule;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final void Function(bool)? onToggleEnabled;

  @override
  State<RuleListTile> createState() => _RuleListTileState();
}

class _RuleListTileState extends State<RuleListTile> {
  bool _menuExpanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final hasMenu = widget.onEdit != null || widget.onDelete != null;
    final rule = widget.rule;
    final conditions = rule.matchConditions;

    return Card(
      margin: EdgeInsets.zero,
      color: widget.isSelected ? colorScheme.primaryContainer : null,
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: widget.onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  if (!rule.enabled)
                    Icon(Icons.visibility_off, size: 16, color: colorScheme.outline),
                  if (!rule.enabled) const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          rule.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                            color: widget.isSelected ? colorScheme.onPrimaryContainer : null,
                          ),
                        ),
                        if (rule.description != null)
                          Text(
                            rule.description!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: widget.isSelected
                                  ? colorScheme.onPrimaryContainer.withValues(alpha: 0.7)
                                  : colorScheme.outline,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (rule.approvalRequired)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Icon(Icons.pending_actions, size: 12, color: Colors.blue),
                    ),
                  if (hasMenu)
                    IconButton(
                      icon: Icon(
                        _menuExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                        size: 20,
                        color: colorScheme.outline,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => setState(() => _menuExpanded = !_menuExpanded),
                    ),
                ],
              ),
            ),
          ),
          // Expanded dropdown with rule details and actions
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 200),
            crossFadeState: _menuExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            firstChild: const SizedBox.shrink(),
            secondChild: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(height: 1),
                  const SizedBox(height: 16),
                  // Rule enabled toggle
                  Row(
                    children: [
                      Icon(Icons.power_settings_new, size: 18, color: colorScheme.outline),
                      const SizedBox(width: 8),
                      Text('启用状态', style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.outline)),
                      const Spacer(),
                      Switch(
                        value: rule.enabled,
                        onChanged: widget.onToggleEnabled,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Tag filters
                  _buildDetailRow(context, Icons.label_outline, '标签筛选', _buildTagSummary(conditions)),
                  const SizedBox(height: 12),
                  // NSFW policy
                  _buildDetailRow(context, Icons.warning_amber, 'NSFW策略', _getNsfwLabel(rule.nsfwPolicy)),
                  const SizedBox(height: 12),
                  // Rate limit
                  _buildDetailRow(
                    context,
                    Icons.speed,
                    '频率限制',
                    rule.rateLimit != null
                        ? '${rule.rateLimit}条/${_formatWindow(rule.timeWindow)}'
                        : '无限制',
                  ),
                  const SizedBox(height: 12),
                  // Approval required
                  _buildDetailRow(
                    context,
                    Icons.pending_actions,
                    '人工审批',
                    rule.approvalRequired ? '需要' : '不需要',
                  ),
                  const SizedBox(height: 20),
                  // Action buttons at bottom
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            // Keep expanded when editing
                            widget.onEdit?.call();
                          },
                          icon: const Icon(Icons.edit, size: 18),
                          label: const Text('编辑规则'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                             setState(() => _menuExpanded = false);
                             widget.onDelete?.call();
                          },
                          icon: const Icon(Icons.delete, size: 18),
                          label: const Text('删除规则'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: colorScheme.error,
                            side: BorderSide(color: colorScheme.error),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(BuildContext context, IconData icon, String label, String value) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Row(
      children: [
        Icon(icon, size: 16, color: colorScheme.outline),
        const SizedBox(width: 8),
        Text(label, style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.outline)),
        const Spacer(),
        Text(value, style: theme.textTheme.bodyMedium),
      ],
    );
  }

  String _buildTagSummary(Map<String, dynamic> conditions) {
    final tags = (conditions['tags'] as List?)?.cast<String>() ?? [];
    final excludeTags = (conditions['tags_exclude'] as List?)?.cast<String>() ?? [];
    if (tags.isEmpty && excludeTags.isEmpty) return '无';
    final parts = <String>[];
    if (tags.isNotEmpty) parts.add('包含${tags.length}个');
    if (excludeTags.isNotEmpty) parts.add('排除${excludeTags.length}个');
    return parts.join(', ');
  }

  String _getNsfwLabel(String policy) {
    return switch (policy) {
      'allow' => '允许',
      'block' => '阻止',
      'separate_channel' => '分离频道',
      _ => policy,
    };
  }

  String _formatWindow(int? seconds) {
    if (seconds == null) return '小时';
    if (seconds < 3600) return '${seconds ~/ 60}分钟';
    return '${seconds ~/ 3600}小时';
  }
}
