import 'package:material_ui/material_ui.dart';

import '../../../theme/design_tokens.dart';

import '../models/distribution_rule.dart';

class RuleListTile extends StatelessWidget {
  const RuleListTile({
    super.key,
    required this.rule,
    required this.isSelected,
    required this.onTap,
    this.onDelete,
    this.onToggleEnabled,
  });
  final DistributionRule rule;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback? onDelete;
  final ValueChanged<bool>? onToggleEnabled;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: isSelected ? colors.secondaryContainer : Colors.transparent,
      borderRadius: AppShape.cardBorder,
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: AppShape.cardBorder),
        title: Text(rule.name, maxLines: 2, overflow: TextOverflow.ellipsis),
        selected: isSelected,
        selectedColor: colors.onSecondaryContainer,
        contentPadding: const EdgeInsetsDirectional.only(start: 12, end: 4),
        onTap: onTap,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onToggleEnabled != null)
              Semantics(
                label: '启用${rule.name}',
                child: Switch(value: rule.enabled, onChanged: onToggleEnabled),
              ),
            if (onDelete != null)
              PopupMenuButton<String>(
                tooltip: '规则操作',
                onSelected: (_) => onDelete!(),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'delete', child: Text('删除规则')),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
