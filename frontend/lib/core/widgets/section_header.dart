import 'package:flutter/material.dart';

/// 通用分区标题栏。
///
/// 设置页用例（紧凑，titleMedium）：
/// ```dart
/// const SectionHeader(title: '外观模式', icon: Icons.palette_rounded)
/// ```
///
/// 仪表盘页用例（宽松，titleLarge，可带尾部操作按钮）：
/// ```dart
/// SectionHeader(
///   title: '探索概览',
///   icon: Icons.explore_rounded,
///   textStyle: theme.textTheme.titleLarge?.copyWith(
///     fontWeight: FontWeight.bold, letterSpacing: -0.5),
///   padding: EdgeInsets.zero,
///   action: TextButton(onPressed: ..., child: Text('前往')),
/// )
/// ```
class SectionHeader extends StatelessWidget {
  final String title;
  final IconData? icon;

  /// 尾部操作区域（如"前往探索"按钮），不传则不显示
  final Widget? action;

  /// 标题 TextStyle；不传则使用 [TextTheme.titleMedium]（适合设置页）
  final TextStyle? textStyle;

  /// 整体内边距，默认 `fromLTRB(4, 8, 8, 16)` 匹配设置页视觉节奏
  final EdgeInsetsGeometry padding;

  const SectionHeader({
    super.key,
    required this.title,
    this.icon,
    this.action,
    this.textStyle,
    this.padding = const EdgeInsets.fromLTRB(4, 8, 8, 16),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resolvedStyle = textStyle ??
        theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.onSurface,
        );

    return Padding(
      padding: padding,
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 20, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Text(title, style: resolvedStyle),
          ),
          if (action != null) action!,
        ],
      ),
    );
  }
}
