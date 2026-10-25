import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'menu_back_scope.dart';

/// A select whose current value and alternatives share one expanding surface.
class AppFilterMenu extends StatefulWidget {
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
  State<AppFilterMenu> createState() => _AppFilterMenuState();
}

class _AppFilterMenuState extends State<AppFilterMenu> {
  final _controller = MenuController();
  final _focus = FocusNode();
  bool _open = false;
  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final theme = Theme.of(context);
      final width = box.hasBoundedWidth ? box.maxWidth : 320.0;
      const shape = RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      );
      final current = widget.options[widget.value] ?? widget.value;
      Widget heading(bool expanded) => SizedBox(
        width: width - 32,
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(current, style: theme.textTheme.bodyLarge),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Icon(expanded ? Icons.expand_less : Icons.expand_more),
          ],
        ),
      );
      final itemStyle = ButtonStyle(
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        ),
        minimumSize: WidgetStatePropertyAll(Size(width, 48)),
        shape: const WidgetStatePropertyAll(RoundedRectangleBorder()),
      );
      return MenuBackScope(
        open: _open,
        close: _controller.close,
        child: MenuAnchor(
          controller: _controller,
          crossAxisUnconstrained: false,
          childFocusNode: _focus,
          animated: !MediaQuery.disableAnimationsOf(context),
          consumeOutsideTap: true,
          style: MenuStyle(
            alignment: Alignment.topLeft,
            padding: const WidgetStatePropertyAll(EdgeInsets.zero),
            shape: const WidgetStatePropertyAll(shape),
            backgroundColor: WidgetStatePropertyAll(
              theme.colorScheme.surfaceContainerHigh,
            ),
            surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
            elevation: const WidgetStatePropertyAll(3),
            minimumSize: WidgetStatePropertyAll(Size(width, 0)),
            maximumSize: WidgetStatePropertyAll(
              Size(width, MediaQuery.sizeOf(context).height - 32),
            ),
          ),
          onOpen: () {
            widget.onOpened?.call();
            setState(() => _open = true);
          },
          onClose: () {
            if (mounted) setState(() => _open = false);
          },
          menuChildren: [
            MenuItemButton(
              style: itemStyle.copyWith(
                minimumSize: WidgetStatePropertyAll(Size(width, 56)),
              ),
              onPressed: _controller.close,
              child: heading(true),
            ),
            const Divider(height: 1),
            for (final entry in widget.options.entries)
              if (entry.key != widget.value)
                MenuItemButton(
                  style: itemStyle,
                  onPressed: () => widget.onSelected(entry.key),
                  child: Text(entry.value),
                ),
          ],
          builder: (context, controller, child) => Opacity(
            opacity: _open ? 0 : 1,
            child: MergeSemantics(
              child: Semantics(
                button: true,
                label: '${widget.label}，$current',
                expanded: _open,
                child: TextButton(
                  focusNode: _focus,
                  style: TextButton.styleFrom(
                    backgroundColor: theme.colorScheme.surfaceContainerHigh,
                    foregroundColor: theme.colorScheme.onSurface,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    minimumSize: Size(width, 56),
                    shape: shape,
                  ),
                  onPressed: !widget.enabled || widget.options.isEmpty
                      ? null
                      : () => controller.open(position: Offset.zero),
                  child: ExcludeSemantics(child: heading(false)),
                ),
              ),
            ),
          ),
        ),
      );
    },
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
