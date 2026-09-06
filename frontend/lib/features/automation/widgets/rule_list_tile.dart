import 'package:flutter/material.dart';

import '../../../theme/design_tokens.dart';
import '../models/distribution_rule.dart';

class RuleListTile extends StatelessWidget {
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
  final ValueChanged<bool>? onToggleEnabled;

  @override
  Widget build(BuildContext context) => ListTile(
    selected: isSelected,
    selectedTileColor: Theme.of(context).colorScheme.secondaryContainer,
    shape: const RoundedRectangleBorder(borderRadius: AppShape.cardBorder),
    title: Text(rule.name, maxLines: 2, overflow: TextOverflow.ellipsis),
    subtitle: Text(rule.approvalRequired ? '需人工审批' : '自动审批'),
    onTap: onTap,
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (onToggleEnabled != null)
          Semantics(
            label: '${rule.name} 启用',
            child: Switch(value: rule.enabled, onChanged: onToggleEnabled),
          ),
        if (onEdit != null || onDelete != null)
          PopupMenuButton<String>(
            tooltip: '规则操作',
            onSelected: (action) =>
                action == 'edit' ? onEdit?.call() : onDelete?.call(),
            itemBuilder: (_) => [
              if (onEdit != null)
                const PopupMenuItem(value: 'edit', child: Text('查看与编辑')),
              if (onDelete != null)
                const PopupMenuItem(value: 'delete', child: Text('删除')),
            ],
          ),
      ],
    ),
  );
}
