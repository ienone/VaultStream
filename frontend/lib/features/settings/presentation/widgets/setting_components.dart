import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../../core/layout/responsive_layout.dart';
import '../../../../core/utils/toast.dart';
import '../../../../theme/design_tokens.dart';

// SectionHeader 已迁移至 core/widgets，此处重新导出保持向后兼容。
export '../../../../core/widgets/section_header.dart' show SectionHeader;

class SettingGroup extends StatelessWidget {
  const SettingGroup({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (var i = 0; i < children.length; i++) ...[
        children[i],
        if (i < children.length - 1) const Divider(height: 1),
      ],
    ],
  );
}

class SettingTile extends StatelessWidget {
  const SettingTile({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.iconColor,
    this.trailing,
    this.onTap,
    this.showArrow = true,
    this.stackTrailing = false,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Color? iconColor;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool showArrow;
  final bool stackTrailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked =
            stackTrailing && constraints.maxWidth < AppPane.formMaxWidth;
        final copy = Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleMedium),
              if (subtitle != null && subtitle!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        );
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: Row(
                      children: [
                        if (icon != null) ...[
                          Icon(icon, size: 22, color: iconColor),
                          const SizedBox(width: 12),
                        ],
                        copy,
                        if (!stacked && trailing != null) ...[
                          const SizedBox(width: 12),
                          trailing!,
                        ],
                        if (trailing == null && showArrow && onTap != null)
                          const Icon(Icons.chevron_right_rounded),
                      ],
                    ),
                  ),
                  if (stacked && trailing != null) ...[
                    const SizedBox(height: 8),
                    trailing!,
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class AdaptiveTaskSurface extends StatelessWidget {
  const AdaptiveTaskSurface({
    super.key,
    required this.title,
    required this.body,
    required this.actions,
    this.maxWidth = AppPane.formMaxWidth,
  });

  final String title;
  final Widget body;
  final List<Widget> actions;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final compact = WindowMetrics.of(context).widthClass.isCompact;
    return Dialog(
      insetPadding: EdgeInsets.all(compact ? 12 : 24),
      shape: const RoundedRectangleBorder(borderRadius: AppShape.sheetBorder),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 20),
              body,
              const SizedBox(height: 16),
              OverflowBar(
                alignment: MainAxisAlignment.end,
                spacing: 12,
                overflowSpacing: 8,
                children: actions,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ExpandableSettingTile extends StatefulWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget expandedContent;
  final Widget? trailing;
  final bool isInitiallyExpanded;
  final ValueChanged<bool>? onToggle;

  const ExpandableSettingTile({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    required this.expandedContent,
    this.trailing,
    this.isInitiallyExpanded = false,
    this.onToggle,
  });

  @override
  State<ExpandableSettingTile> createState() => _ExpandableSettingTileState();
}

class _ExpandableSettingTileState extends State<ExpandableSettingTile> {
  late bool _isExpanded;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.isInitiallyExpanded;
  }

  void _toggle() {
    setState(() {
      _isExpanded = !_isExpanded;
    });
    widget.onToggle?.call(_isExpanded);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        SettingTile(
          title: widget.title,
          subtitle: widget.subtitle,
          icon: widget.icon,
          showArrow: false,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.trailing != null) ...[
                widget.trailing!,
                const SizedBox(width: 8),
              ],
              AnimatedRotation(
                turns: _isExpanded ? 0.25 : 0,
                duration: AppMotion.stateChange,
                curve: AppMotion.standardCurve,
                child: Icon(
                  Icons.chevron_right_rounded,
                  color: colorScheme.outline.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
          onTap: _toggle,
        ),
        AnimatedSize(
          duration: AppMotion.stateChange,
          curve: AppMotion.standardCurve,
          child: _isExpanded
              ? Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 16),
                  child: widget.expandedContent,
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

void showToast(BuildContext context, String message) {
  Toast.show(context, message);
}

class LoadingGroup extends StatelessWidget {
  const LoadingGroup({super.key});
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: AppShape.sheetBorder,
      ),
      child: const Center(child: CircularProgressIndicator()),
    ).animate(onPlay: (c) => c.repeat()).shimmer();
  }
}
