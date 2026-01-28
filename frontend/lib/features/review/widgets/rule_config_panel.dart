import 'package:flutter/material.dart';
import '../models/distribution_rule.dart';

class RuleConfigPanel extends StatelessWidget {
  const RuleConfigPanel({
    super.key,
    required this.rule,
    this.expanded = false,
    this.onToggleExpand,
    this.onEdit,
    this.onDelete,
    this.onToggleEnabled,
    this.showHeader = true,
  });

  final DistributionRule rule;
  final bool expanded;
  final VoidCallback? onToggleExpand;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final void Function(bool)? onToggleEnabled;
  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final conditions = rule.matchConditions;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      // Add background color change when expanded if needed, or handle in parent
      color: expanded ? colorScheme.surfaceContainerHigh : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showHeader)
            InkWell(
              onTap: onToggleExpand,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    if (onToggleExpand != null) ...[
                      Icon(
                        expanded ? Icons.expand_less : Icons.expand_more,
                        color: colorScheme.outline,
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            rule.name,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (rule.description != null)
                            Text(
                              rule.description!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.outline,
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
              ),
            ),
          if (expanded) ...[
            if (showHeader) const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSection(
                    context,
                    icon: Icons.label_outline,
                    title: '标签筛选',
                    child: _buildTagFilters(context, conditions),
                  ),
                  const SizedBox(height: 12),
                  _buildSection(
                    context,
                    icon: Icons.warning_amber,
                    title: 'NSFW策略',
                    child: _NsfwPolicyChip(policy: rule.nsfwPolicy),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildSection(
                          context,
                          icon: Icons.speed,
                          title: '频率限制',
                          child: Text(
                            rule.rateLimit != null
                                ? '${rule.rateLimit}条/${_formatWindow(rule.timeWindow)}'
                                : '无限制',
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      ),
                      Expanded(
                        child: _buildSection(
                          context,
                          icon: Icons.pending_actions,
                          title: '人工审批',
                          child: Row(
                            children: [
                              Icon(
                                rule.approvalRequired
                                    ? Icons.check_circle
                                    : Icons.cancel,
                                size: 16,
                                color: rule.approvalRequired
                                    ? Colors.green
                                    : colorScheme.outline,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                rule.approvalRequired ? '需要' : '不需要',
                                style: theme.textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (rule.autoApproveConditions != null &&
                      rule.autoApproveConditions!.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _buildSection(
                      context,
                      icon: Icons.auto_awesome,
                      title: '自动审批条件',
                      child: _buildAutoApproveConditions(
                          context, rule.autoApproveConditions!),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: onEdit,
                          icon: const Icon(Icons.edit, size: 18),
                          label: const Text('编辑规则'),
                        ),
                      ),
                      if (onDelete != null) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: onDelete,
                            icon: const Icon(Icons.delete, size: 18),
                            label: const Text('删除规则'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: colorScheme.error,
                              side: BorderSide(color: colorScheme.error),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSection(
    BuildContext context, {
    required IconData icon,
    required String title,
    required Widget child,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: theme.colorScheme.outline),
            const SizedBox(width: 4),
            Text(
              title,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        child,
      ],
    );
  }

  Widget _buildTagFilters(BuildContext context, Map<String, dynamic> conditions) {
    final tags = (conditions['tags'] as List?)?.cast<String>() ?? [];
    final excludeTags = (conditions['tags_exclude'] as List?)?.cast<String>() ?? [];
    final matchMode = conditions['tags_match_mode'] as String? ?? 'any';
    final theme = Theme.of(context);

    if (tags.isEmpty && excludeTags.isEmpty) {
      return Text('无标签筛选', style: theme.textTheme.bodyMedium);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (tags.isNotEmpty) ...[
          Row(
            children: [
              Text(
                matchMode == 'all' ? '包含全部:' : '包含任一:',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: tags.map((tag) => _TagChip(tag: tag)).toList(),
                ),
              ),
            ],
          ),
        ],
        if (excludeTags.isNotEmpty) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              Text('排除:', style: theme.textTheme.bodySmall),
              const SizedBox(width: 8),
              Expanded(
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: excludeTags
                      .map((tag) => _TagChip(tag: tag, isExclude: true))
                      .toList(),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildAutoApproveConditions(
      BuildContext context, Map<String, dynamic> conditions) {
    final items = <String>[];
    if (conditions['is_nsfw'] == false) items.add('非NSFW');
    if (conditions['is_nsfw'] == true) items.add('NSFW');
    if (conditions['platform'] != null) items.add('平台: ${conditions['platform']}');
    if (conditions['tags'] != null) {
      items.add('标签: ${(conditions['tags'] as List).join(', ')}');
    }

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: items
          .map((item) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                ),
                child: Text(
                  item,
                  style: const TextStyle(fontSize: 11, color: Colors.green),
                ),
              ))
          .toList(),
    );
  }

  String _formatWindow(int? seconds) {
    if (seconds == null) return '小时';
    if (seconds < 3600) return '${seconds ~/ 60}分钟';
    return '${seconds ~/ 3600}小时';
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({required this.tag, this.isExclude = false});

  final String tag;
  final bool isExclude;

  @override
  Widget build(BuildContext context) {
    final color = isExclude ? Colors.red : Colors.blue;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isExclude) ...[
            Icon(Icons.close, size: 10, color: color),
            const SizedBox(width: 2),
          ],
          Text(
            tag,
            style: TextStyle(fontSize: 11, color: color),
          ),
        ],
      ),
    );
  }
}

class _NsfwPolicyChip extends StatelessWidget {
  const _NsfwPolicyChip({required this.policy});

  final String policy;

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (policy) {
      'allow' => ('允许', Colors.green, Icons.check_circle),
      'block' => ('阻止', Colors.red, Icons.block),
      'separate_channel' => ('分离频道', Colors.orange, Icons.call_split),
      _ => ('继承', Colors.grey, Icons.settings),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
