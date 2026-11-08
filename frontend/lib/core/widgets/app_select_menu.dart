import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../theme/design_tokens.dart';
import 'menu_back_scope.dart';

/// Keeps the field visible while its own surface expands into a menu.
class AppSelectMenu extends StatefulWidget {
  const AppSelectMenu({
    super.key,
    required this.label,
    required this.summary,
    required this.items,
    this.enabled = true,
    this.onOpened,
  });

  final String label;
  final String summary;
  final List<Widget> Function(void Function(VoidCallback action) close) items;
  final bool enabled;
  final VoidCallback? onOpened;

  @override
  State<AppSelectMenu> createState() => _AppSelectMenuState();
}

class _AppSelectMenuState extends State<AppSelectMenu>
    with SingleTickerProviderStateMixin {
  final _menu = MenuController();
  final _focus = FocusNode();
  final _menuFocus = FocusScopeNode(
    traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
  );
  late final _motion = AnimationController(
    vsync: this,
    duration: AppMotion.surfaceEnter,
    reverseDuration: AppMotion.surfaceExit,
  );
  late final _progress = CurvedAnimation(
    parent: _motion,
    curve: AppMotion.standardCurve,
    reverseCurve: AppMotion.standardCurve,
  );
  bool _open = false;
  VoidCallback? _afterClose;

  @override
  void dispose() {
    _progress.dispose();
    _motion.dispose();
    _focus.dispose();
    _menuFocus.dispose();
    super.dispose();
  }

  Widget _surface({required bool expanded, double? maxHeight}) {
    final theme = Theme.of(context);
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(
        color: expanded ? theme.colorScheme.primary : theme.colorScheme.outline,
      ),
    );
    return InputDecorator(
      isFocused: expanded,
      decoration: InputDecoration(
        labelText: widget.label,
        floatingLabelBehavior: FloatingLabelBehavior.always,
        isDense: true,
        filled: false,
        enabled: widget.enabled,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: border,
        enabledBorder: border,
        focusedBorder: border,
        disabledBorder: border,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: expanded ? _menu.close : null,
            borderRadius: BorderRadius.circular(8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.summary,
                    style: theme.textTheme.bodyLarge,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 12),
                RotationTransition(
                  turns: _progress.drive(Tween(begin: 0.0, end: .5)),
                  child: const Icon(Icons.expand_more),
                ),
              ],
            ),
          ),
          if (expanded)
            SizeTransition(
              sizeFactor: _progress,
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: math.max(
                    0,
                    maxHeight! -
                        40 -
                        MediaQuery.textScalerOf(context)
                                .scale(theme.textTheme.bodyLarge!.fontSize!) *
                            (theme.textTheme.bodyLarge!.height ?? 1.5),
                  ),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(top: 12),
                  child: MenuTheme(
                    data: MenuThemeData(
                      style: MenuStyle(
                        backgroundColor: WidgetStatePropertyAll(
                          theme.colorScheme.surfaceContainerHigh,
                        ),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: widget.items((action) {
                        _afterClose = action;
                        _menu.close();
                      }),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => MenuBackScope(
    open: _open,
    close: _menu.close,
    child: RawMenuAnchor(
      controller: _menu,
      childFocusNode: _focus,
      useRootOverlay: true,
      consumeOutsideTaps: true,
      onOpen: () {
        widget.onOpened?.call();
        setState(() => _open = true);
      },
      onClose: () {
        if (!mounted) return;
        setState(() => _open = false);
        final action = _afterClose;
        _afterClose = null;
        action?.call();
      },
      onOpenRequested: (position, showOverlay) {
        showOverlay();
        if (MediaQuery.disableAnimationsOf(context)) {
          _motion.value = 1;
        } else {
          _motion.forward();
        }
      },
      onCloseRequested: (hideOverlay) async {
        if (MediaQuery.disableAnimationsOf(context)) {
          _motion.value = 0;
        } else {
          try {
            await _motion.reverse().orCancel;
          } on TickerCanceled {
            return;
          }
        }
        hideOverlay();
      },
      overlayBuilder: (context, info) {
        final media = MediaQuery.of(context);
        final bottom = info.overlaySize.height - media.viewInsets.bottom - 12;
        final top = media.padding.top + 12;
        final maxHeight = math.min(400.0, bottom - top);
        return Positioned.fill(
          child: CustomSingleChildLayout(
            delegate: _SelectMenuLayout(
              info.anchorRect,
              top,
              bottom,
              maxHeight,
            ),
            child: TapRegion(
              groupId: info.tapRegionGroupId,
              consumeOutsideTaps: true,
              onTapOutside: (_) => _menu.close(),
              child: FocusScope(
                autofocus: true,
                node: _menuFocus,
                child: Shortcuts(
                  shortcuts: const {
                    SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
                    SingleActivator(LogicalKeyboardKey.arrowDown):
                        NextFocusIntent(),
                    SingleActivator(LogicalKeyboardKey.arrowUp):
                        PreviousFocusIntent(),
                  },
                  child: Actions(
                    actions: {
                      DismissIntent: CallbackAction<DismissIntent>(
                        onInvoke: (_) {
                          _menu.close();
                          return null;
                        },
                      ),
                    },
                    child: Material(
                      color: Theme.of(context).colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(16),
                      child: _surface(expanded: true, maxHeight: maxHeight),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
      builder: (context, controller, child) => ExcludeSemantics(
        excluding: _open,
        child: Opacity(
          opacity: _open ? 0 : 1,
          child: Material(
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              focusNode: _focus,
              borderRadius: BorderRadius.circular(16),
              onTap: widget.enabled ? () => _menu.open() : null,
              child: Semantics(
                button: true,
                expanded: _open,
                child: _surface(expanded: false),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _SelectMenuLayout extends SingleChildLayoutDelegate {
  const _SelectMenuLayout(this.anchor, this.top, this.bottom, this.maxHeight);
  final Rect anchor;
  final double top, bottom, maxHeight;
  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.tightFor(width: anchor.width)
          .copyWith(maxHeight: maxHeight);
  @override
  Offset getPositionForChild(Size size, Size childSize) => Offset(
    anchor.left,
    math.max(top, math.min(anchor.top, bottom - childSize.height)),
  );
  @override
  bool shouldRelayout(_SelectMenuLayout old) =>
      anchor != old.anchor ||
      top != old.top ||
      bottom != old.bottom ||
      maxHeight != old.maxHeight;
}
