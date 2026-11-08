import 'package:material_ui/material_ui.dart';

/// An anchored menu is an overlay, so it needs a back boundary of its own.
/// MenuAnchor retains ownership of focus, selection and the closing animation.
class MenuBackScope extends StatelessWidget {
  const MenuBackScope({
    super.key,
    required this.open,
    required this.close,
    required this.child,
  });
  final bool open;
  final VoidCallback close;
  final Widget child;

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !open,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && open) close();
    },
    child: child,
  );
}
