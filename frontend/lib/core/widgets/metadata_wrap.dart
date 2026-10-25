import 'package:material_ui/material_ui.dart';

import '../../theme/design_tokens.dart';

/// Secondary facts stay separate and wrap as whole items on narrow surfaces.
class MetadataWrap extends StatelessWidget {
  const MetadataWrap({super.key, required this.items, this.style});

  final List<String> items;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.xxs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final item in items)
          Text(
            item,
            style:
                style ??
                theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
          ),
      ],
    );
  }
}
