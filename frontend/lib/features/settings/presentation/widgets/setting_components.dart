import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../../core/utils/toast.dart';

// SectionHeader 已迁移至 core/widgets，此处重新导出保持向后兼容。
export '../../../../core/widgets/section_header.dart' show SectionHeader;

class SettingGroup extends StatelessWidget {
  final List<Widget> children;

  const SettingGroup({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // M3 Spec: 使用 Card 实现分组，利用 surfaceContainer 及其自带的 elevation 效果
    return Card(
      elevation: 0, // M3 倾向于使用色块区分而非阴影，或使用极低阴影。若需阴影可设为 1-2
      color: colorScheme.surfaceContainer, // M3 标准容器色
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20), // 大圆角
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: children.asMap().entries.map((entry) {
          final isLast = entry.key == children.length - 1;
          return Column(
            children: [
              entry.value,
              if (!isLast)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Divider(
                    height: 1,
                    thickness: 0.5,
                    color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
            ],
          );
        }).toList(),
      ),
    ).animate().fadeIn(delay: 100.ms).slideY(begin: 0.05, end: 0);
  }
}

class SettingTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color? iconColor;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool showArrow;

  const SettingTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.iconColor,
    this.trailing,
    this.onTap,
    this.showArrow = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = trailing != null && constraints.maxWidth < 560;
            final leading = Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: (iconColor ?? colorScheme.primary).withValues(
                  alpha: 0.1,
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                icon,
                color: iconColor ?? colorScheme.primary,
                size: 22,
              ),
            );
            final copy = Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            );

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              child: compact
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [leading, const SizedBox(width: 16), copy],
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: trailing!,
                          ),
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        leading,
                        const SizedBox(width: 16),
                        copy,
                        ?trailing,
                        if (trailing == null && showArrow)
                          Icon(
                            Icons.chevron_right_rounded,
                            color: colorScheme.outline.withValues(alpha: 0.5),
                          ),
                      ],
                    ),
            );
          },
        ),
      ),
    );
  }
}

class AdaptiveTaskSurface extends StatelessWidget {
  const AdaptiveTaskSurface({
    super.key,
    required this.title,
    required this.icon,
    required this.body,
    required this.actions,
    this.maxWidth = 560,
  });

  final String title;
  final IconData icon;
  final Widget body;
  final List<Widget> actions;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 640;
    final header = Row(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colorScheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(icon, color: colorScheme.primary),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
    final actionBar = OverflowBar(
      alignment: MainAxisAlignment.end,
      spacing: 12,
      overflowSpacing: 8,
      children: actions,
    );
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        const SizedBox(height: 24),
        Expanded(child: body),
        const SizedBox(height: 16),
        actionBar,
      ],
    );

    if (compact) {
      return Dialog.fullscreen(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: content,
          ),
        ),
      );
    }

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth,
          maxHeight: size.height * 0.9,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
          child: content,
        ),
      ),
    );
  }
}

class ExpandableSettingTile extends StatefulWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Widget expandedContent;
  final Widget? trailing;
  final bool isInitiallyExpanded;
  final ValueChanged<bool>? onToggle;

  const ExpandableSettingTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
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
              if (widget.trailing != null) widget.trailing!,
              const SizedBox(width: 8),
              AnimatedRotation(
                turns: _isExpanded ? 0.25 : 0,
                duration: 300.ms,
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
          duration: 300.ms,
          curve: Curves.easeOutQuart,
          child: _isExpanded
              ? Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(64, 0, 20, 24),
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
        borderRadius: BorderRadius.circular(28),
      ),
      child: const Center(child: CircularProgressIndicator()),
    ).animate(onPlay: (c) => c.repeat()).shimmer();
  }
}
