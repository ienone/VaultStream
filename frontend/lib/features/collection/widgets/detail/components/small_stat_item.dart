import 'package:flutter/material.dart';

class SmallStatItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const SmallStatItem({
    super.key,
    required this.icon,
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
        Icon(icon, size: 14, color: colorScheme.outline),
        const SizedBox(width: 4),
        Text(
          '$value $label',
          style: theme.textTheme.labelSmall?.copyWith(
            color: colorScheme.outline,
          ),
        ),
      ],
    );
  }
}
