import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'app_select_menu.dart';

class AppFilterMenu extends StatelessWidget {
  const AppFilterMenu({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onSelected,
    this.onOpened,
    this.enabled = true,
  });
  final String label;
  final String value;
  final Map<String, String> options;
  final ValueChanged<String> onSelected;
  final VoidCallback? onOpened;
  final bool enabled;

  @override
  Widget build(BuildContext context) => AppSelectMenu(
    label: label,
    summary: options[value] ?? value,
    enabled: enabled && options.isNotEmpty,
    onOpened: onOpened,
    items: (close) => [
      for (final entry in options.entries)
        if (entry.key != value)
          MenuItemButton(
            closeOnActivate: false,
            style: const ButtonStyle(
              padding: WidgetStatePropertyAll(EdgeInsets.zero),
            ),
            onPressed: () {
              close(() => onSelected(entry.key));
            },
            child: Text(entry.value),
          ),
    ],
  );
}

/// Fits short filters on one row; wraps only when their labels need more space.
class AppFilterMenuRow extends StatelessWidget {
  const AppFilterMenuRow({super.key, required this.menus});
  final List<AppFilterMenu> menus;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final theme = Theme.of(context);
      double textWidth(String value, TextStyle? style) {
        final painter = TextPainter(
          text: TextSpan(text: value, style: style),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();
        final width = painter.width;
        painter.dispose();
        return width;
      }

      final minimums = [
        for (final menu in menus)
          [
                textWidth(menu.label, theme.textTheme.labelSmall),
                ...menu.options.values.map(
                  (label) => textWidth(label, theme.textTheme.bodyLarge),
                ),
              ].reduce((a, b) => a > b ? a : b) +
              68,
      ];
      final required =
          minimums.fold(0.0, (sum, width) => sum + width) +
          (menus.length - 1) * 8;
      final inline = required <= box.maxWidth;
      final extra = inline ? (box.maxWidth - required) / menus.length : 0.0;
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (var i = 0; i < menus.length; i++)
            SizedBox(
              width: inline
                  ? math.min(
                      minimums[i] + extra,
                      math.max(
                        minimums[i],
                        280 * MediaQuery.textScalerOf(context).scale(16) / 16,
                      ),
                    )
                  : box.maxWidth,
              child: menus[i],
            ),
        ],
      );
    },
  );
}
