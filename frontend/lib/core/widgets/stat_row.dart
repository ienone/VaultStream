import 'package:flutter/material.dart';

/// 通用统计行：左侧图标 + 标签，右侧加粗数值。
///
/// 适用于卡片内的简洁信息展示。
///
/// ```dart
/// const StatRow(
///   icon: Icons.groups_rounded,
///   label: '活跃群组',
///   value: '12',
/// )
/// ```
class StatRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const StatRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.outline),
        const SizedBox(width: 12),
        Text(
          label,
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const Spacer(),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.primary,
          ),
        ),
      ],
    );
  }
}
