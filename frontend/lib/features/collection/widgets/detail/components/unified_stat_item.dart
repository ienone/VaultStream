import 'package:flutter/material.dart';

import '../../../../../theme/design_tokens.dart';

class UnifiedStatItem extends StatelessWidget {
  final IconData icon;
  final String? emoji;
  final String label;
  final String value;

  const UnifiedStatItem({
    super.key,
    required this.icon,
    this.emoji,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (emoji?.isNotEmpty == true)
          Text(emoji!, style: theme.textTheme.bodySmall)
        else
          Icon(icon, size: 15, color: colorScheme.onSurfaceVariant),
        const SizedBox(width: AppSpacing.xs),
        Flexible(
          child: Text(
            '$value $label',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
