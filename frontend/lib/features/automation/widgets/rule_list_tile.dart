import 'package:material_ui/material_ui.dart';

import '../../../theme/design_tokens.dart';
import '../../../core/widgets/swipe_action_reveal.dart';

import '../models/distribution_rule.dart';

class RuleListTile extends StatelessWidget {
  const RuleListTile({
    super.key,
    required this.rule,
    required this.backgroundColor,
    required this.isSelected,
    required this.onTap,
    this.onDelete,
    this.onToggleEnabled,
  });
  final DistributionRule rule;
  final Color backgroundColor;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback? onDelete;
  final ValueChanged<bool>? onToggleEnabled;
  @override
  Widget build(BuildContext context) => SwipeActionReveal(
    actions: onDelete == null
        ? []
        : [
            SwipeAction(
              label: '删除',
              icon: Icons.delete_outline_rounded,
              background: Theme.of(context).colorScheme.errorContainer,
              foreground: Theme.of(context).colorScheme.onErrorContainer,
              onPressed: onDelete!,
            ),
          ],
    resetKey: isSelected,
    builder: (context, showActions) => ColoredBox(
      color: backgroundColor,
      child: DistributionNavigationTile(
        title: rule.name,
        selected: isSelected,
        onTap: onTap,
        trailing: onToggleEnabled == null
            ? null
            : Semantics(
                label: '${rule.name} 启用',
                child: Switch(value: rule.enabled, onChanged: onToggleEnabled),
              ),
      ),
    ),
  );
}

class DistributionNavigationTile extends StatelessWidget {
  const DistributionNavigationTile({
    super.key,
    required this.title,
    required this.selected,
    required this.onTap,
    this.icon,
    this.trailing,
  });

  final String title;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: selected ? colors.secondaryContainer : Colors.transparent,
      borderRadius: AppShape.cardBorder,
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        selected: selected,
        selectedColor: colors.onSecondaryContainer,
        shape: RoundedRectangleBorder(borderRadius: AppShape.cardBorder),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: icon == null ? null : Icon(icon),
        title: Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
        trailing: trailing,
        onTap: onTap,
      ),
    );
  }
}
