import 'package:flutter/material.dart';

import '../../theme/design_tokens.dart';

class AppFilterMenu extends StatelessWidget {
  const AppFilterMenu({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onSelected,
    this.onOpened,
  });
  final String label;
  final String value;
  final Map<String, String> options;
  final ValueChanged<String> onSelected;
  final VoidCallback? onOpened;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) => Material(
        type: MaterialType.transparency,
        child: PopupMenuButton<String>(
          useRootNavigator: true,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          menuPadding: EdgeInsets.zero,
          initialValue: value,
          tooltip: '',
          onOpened: onOpened,
          borderRadius: BorderRadius.circular(AppRadius.md),
          constraints: BoxConstraints(
            minWidth: constraints.maxWidth,
            maxWidth: constraints.maxWidth,
          ),
          popUpAnimationStyle: MediaQuery.disableAnimationsOf(context)
              ? AnimationStyle.noAnimation
              : null,
          itemBuilder: (context) => [
            for (final option in options.entries)
              CheckedPopupMenuItem<String>(
                value: option.key,
                checked: option.key == value,
                child: Text(option.value),
              ),
          ],
          onSelected: (next) {
            if (next != value) onSelected(next);
          },
          child: Semantics(
            label: '$label：${options[value]}',
            button: true,
            excludeSemantics: true,
            child: Ink(
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 40),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                          Text(
                            options[value]!,
                            style: theme.textTheme.bodyLarge,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    const Icon(Icons.arrow_drop_down_rounded),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
