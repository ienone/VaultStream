import 'package:flutter/widgets.dart';

import 'browser_leave_guard_stub.dart'
    if (dart.library.js_interop) 'browser_leave_guard_web.dart'
    as platform;

/// Protects a mounted draft when the browser unloads the entire application.
/// In-app navigation remains the responsibility of the form's route guard.
class BrowserLeaveGuard extends StatefulWidget {
  const BrowserLeaveGuard({
    super.key,
    required this.enabled,
    required this.child,
  });

  final bool enabled;
  final Widget child;

  @override
  State<BrowserLeaveGuard> createState() => _BrowserLeaveGuardState();
}

class _BrowserLeaveGuardState extends State<BrowserLeaveGuard> {
  VoidCallback? _removeListener;

  @override
  void initState() {
    super.initState();
    _updateListener();
  }

  @override
  void didUpdateWidget(BrowserLeaveGuard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled) _updateListener();
  }

  void _updateListener() {
    _removeListener?.call();
    _removeListener = widget.enabled ? platform.listenBeforeUnload() : null;
  }

  @override
  void dispose() {
    _removeListener?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
