import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

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

class ExpandableSettingTile extends StatefulWidget {
  const ExpandableSettingTile({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    required this.expandedContent,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget expandedContent;

  @override
  State<ExpandableSettingTile> createState() => _ExpandableSettingTileState();
}

class _ExpandableSettingTileState extends State<ExpandableSettingTile>
    with AutomaticKeepAliveClientMixin {
  bool _expanded = false;

  @override
  bool get wantKeepAlive => _expanded;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    const shape = RoundedRectangleBorder(
      borderRadius: AppShape.cardMediaBorder,
    );
    return ListTileTheme.merge(
      shape: shape,
      child: ExpansionTile(
        title: Text(widget.title, style: theme.textTheme.titleMedium),
        subtitle: widget.subtitle == null || widget.subtitle!.isEmpty
            ? null
            : Text(
                widget.subtitle!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
        leading: widget.icon == null ? null : Icon(widget.icon, size: 22),
        tilePadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        childrenPadding: const EdgeInsets.fromLTRB(4, 8, 4, 16),
        shape: shape,
        collapsedShape: shape,
        clipBehavior: Clip.antiAlias,
        maintainState: true,
        expansionAnimationStyle: MediaQuery.disableAnimationsOf(context)
            ? AnimationStyle.noAnimation
            : const AnimationStyle(
                duration: AppMotion.contentSwap,
                curve: AppMotion.standardCurve,
              ),
        onExpansionChanged: (expanded) {
          setState(() => _expanded = expanded);
          updateKeepAlive();
        },
        children: [
          ExcludeFocus(
            excluding: !_expanded,
            child: SizedBox(
              width: double.infinity,
              child: widget.expandedContent,
            ),
          ),
        ],
      ),
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
