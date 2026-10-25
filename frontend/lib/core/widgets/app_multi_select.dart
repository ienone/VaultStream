import 'package:material_ui/material_ui.dart';

import 'menu_back_scope.dart';

/// Multi-selection uses the same menu surface as single-value filters.
class AppMultiSelect extends StatefulWidget {
  const AppMultiSelect({
    super.key,
    required this.label,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.hint = '不限',
  });
  final String label;
  final String hint;
  final Map<String, String> options;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;
  @override
  State<AppMultiSelect> createState() => _AppMultiSelectState();
}

class _AppMultiSelectState extends State<AppMultiSelect> {
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
      final names = widget.selected.map((key) => widget.options[key] ?? key);
      final summary = names.isEmpty ? widget.hint : names.join('、');
      const shape = RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      );
      final style = ButtonStyle(
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        ),
        minimumSize: WidgetStatePropertyAll(Size(width, 48)),
        shape: const WidgetStatePropertyAll(RoundedRectangleBorder()),
      );
      Widget header(bool expanded) => SizedBox(
        width: width - 32,
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.label, style: theme.textTheme.labelSmall),
                  Text(
                    summary,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Icon(expanded ? Icons.expand_less : Icons.expand_more),
          ],
        ),
      );
      return MenuBackScope(
        open: _open,
        close: _controller.close,
        child: MenuAnchor(
          controller: _controller,
          useRootOverlay: true,
          crossAxisUnconstrained: false,
          childFocusNode: _focus,
          animated: !MediaQuery.disableAnimationsOf(context),
          consumeOutsideTap: true,
          onOpen: () => setState(() => _open = true),
          onClose: () {
            if (mounted) setState(() => _open = false);
          },
          style: MenuStyle(
            alignment: Alignment.topLeft,
            surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
            elevation: const WidgetStatePropertyAll(3),
            padding: const WidgetStatePropertyAll(EdgeInsets.zero),
            shape: const WidgetStatePropertyAll(shape),
            backgroundColor: WidgetStatePropertyAll(
              theme.colorScheme.surfaceContainerHigh,
            ),
            minimumSize: WidgetStatePropertyAll(Size(width, 0)),
            maximumSize: WidgetStatePropertyAll(
              Size(width, MediaQuery.sizeOf(context).height - 32),
            ),
          ),
          menuChildren: [
            MenuItemButton(
              style: style,
              onPressed: _controller.close,
              child: header(true),
            ),
            const Divider(height: 1),
            MenuItemButton(
              style: style,
              closeOnActivate: false,
              onPressed: widget.selected.isEmpty
                  ? null
                  : () => widget.onChanged({}),
              child: const Text('清除选择'),
            ),
            for (final entry in widget.options.entries)
              CheckboxMenuButton(
                style: style,
                closeOnActivate: false,
                value: widget.selected.contains(entry.key),
                onChanged: (value) {
                  final next = Set<String>.of(widget.selected);
                  value == true ? next.add(entry.key) : next.remove(entry.key);
                  widget.onChanged(next);
                },
                child: Text(entry.value),
              ),
          ],
          builder: (context, controller, child) => Opacity(
            opacity: _open ? 0 : 1,
            child: MergeSemantics(
              child: Semantics(
                button: true,
                expanded: _open,
                label: '${widget.label}，$summary',
                child: TextButton(
                  focusNode: _focus,
                  style: TextButton.styleFrom(
                    backgroundColor: theme.colorScheme.surfaceContainerHigh,
                    foregroundColor: theme.colorScheme.onSurface,
                    shape: shape,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    minimumSize: Size(width, 56),
                  ),
                  onPressed: widget.options.isEmpty
                      ? null
                      : () => controller.open(position: Offset.zero),
                  child: ExcludeSemantics(child: header(false)),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
