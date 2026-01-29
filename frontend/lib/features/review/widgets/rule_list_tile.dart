import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
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
    this.index = 0,
  });

  final DistributionRule rule;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final void Function(bool)? onToggleEnabled;
  final int index;

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
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(
          color: widget.isSelected 
            ? colorScheme.primary 
            : colorScheme.outlineVariant.withValues(alpha: 0.3),
          width: widget.isSelected ? 2 : 1,
        ),
      ),
      color: widget.isSelected 
          ? colorScheme.primaryContainer.withValues(alpha: 0.3) 
          : colorScheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: widget.onTap,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: (rule.enabled ? colorScheme.primary : colorScheme.outline).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      rule.enabled ? Icons.rule_rounded : Icons.rule_outlined,
                      size: 20,
                      color: rule.enabled ? colorScheme.primary : colorScheme.outline,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          rule.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: widget.isSelected ? colorScheme.primary : null,
                          ),
                        ),
                        if (rule.description != null)
                          Text(
                            rule.description!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (rule.approvalRequired)
                    Tooltip(
                      message: '需要人工审批',
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: colorScheme.tertiaryContainer.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.pending_actions_rounded, size: 14, color: colorScheme.onTertiaryContainer),
                      ),
                    ),
                  if (hasMenu)
                    IconButton.filledTonal(
                      icon: AnimatedRotation(
                        turns: _menuExpanded ? 0.5 : 0,
                        duration: 300.ms,
                        child: const Icon(Icons.expand_more_rounded, size: 18),
                      ),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => setState(() => _menuExpanded = !_menuExpanded),
                    ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: 300.ms,
            curve: Curves.easeOutQuart,
            alignment: Alignment.topCenter,
            child: _menuExpanded 
              ? Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Divider(height: 1),
                      const SizedBox(height: 20),
                      _buildDetailRow(context, Icons.power_settings_new_rounded, '启用状态', 
                        Switch(
                          value: rule.enabled,
                          onChanged: widget.onToggleEnabled,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildDetailRow(context, Icons.label_rounded, '标签筛选', 
                        _buildBadge(context, _buildTagSummary(conditions), colorScheme.secondary)),
                      const SizedBox(height: 12),
                      _buildDetailRow(context, Icons.warning_rounded, 'NSFW策略', 
                        _buildBadge(context, _getNsfwLabel(rule.nsfwPolicy), colorScheme.error)),
                      const SizedBox(height: 12),
                      _buildDetailRow(context, Icons.speed_rounded, '频率限制', 
                        Text(rule.rateLimit != null ? '${rule.rateLimit}条/${_formatWindow(rule.timeWindow)}' : '无限制', 
                        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold))),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.tonalIcon(
                              onPressed: widget.onEdit,
                              icon: const Icon(Icons.edit_rounded, size: 18),
                              label: const Text('编辑'),
                              style: FilledButton.styleFrom(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: widget.onDelete,
                              icon: const Icon(Icons.delete_outline_rounded, size: 18),
                              label: const Text('删除'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: colorScheme.error,
                                side: BorderSide(color: colorScheme.error.withValues(alpha: 0.5)),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                )
              : const SizedBox.shrink(),
          ),
        ],
      ),
    )
    .animate()
    .fadeIn(delay: (widget.index * 50).ms, duration: 400.ms)
    .slideX(begin: 0.1, end: 0, curve: Curves.easeOutCubic);
  }

  Widget _buildDetailRow(BuildContext context, IconData icon, String label, Widget valueWidget) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
        const SizedBox(width: 12),
        Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const Spacer(),
        valueWidget,
      ],
    );
  }

  Widget _buildBadge(BuildContext context, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.bold),
      ),
    );
  }

  String _buildTagSummary(Map<String, dynamic> conditions) {
    final tags = (conditions['tags'] as List?)?.cast<String>() ?? [];
    final excludeTags = (conditions['tags_exclude'] as List?)?.cast<String>() ?? [];
    if (tags.isEmpty && excludeTags.isEmpty) return '全部';
    final parts = <String>[];
    if (tags.isNotEmpty) parts.add('含${tags.length}个');
    if (excludeTags.isNotEmpty) parts.add('排${excludeTags.length}个');
    return parts.join('/');
  }

  String _getNsfwLabel(String policy) {
    return switch (policy) {
      'allow' => '允许',
      'block' => '阻止',
      'separate_channel' => '分离',
      _ => policy,
    };
  }

  String _formatWindow(int? seconds) {
    if (seconds == null) return '时';
    if (seconds < 3600) return '${seconds ~/ 60}分';
    return '${seconds ~/ 3600}时';
  }
}