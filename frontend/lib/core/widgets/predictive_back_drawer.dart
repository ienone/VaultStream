import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../../theme/design_tokens.dart';
import '../../routing/navigation_scope.dart';

/// Preview the drawer itself; Scaffold still owns its drag and local history.
class PredictiveBackDrawer extends StatefulWidget {
  const PredictiveBackDrawer({
    super.key,
    required this.child,
    required this.isOpen,
    required this.close,
    this.alignment = Alignment.centerLeft,
  });

  final Widget child;
  final bool Function() isOpen;
  final VoidCallback close;
  final Alignment alignment;

  @override
  State<PredictiveBackDrawer> createState() => _PredictiveBackDrawerState();
}

class _PredictiveBackDrawerState extends State<PredictiveBackDrawer>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final _progress = AnimationController(
    vsync: this,
    duration: AppMotion.surfaceExit,
  );
  ModalRoute<dynamic>? _route;
  double _fromProgress = 0;
  double _toProgress = 0;
  double _fromOffset = 0;
  double _toOffset = 0;

  double get _preview =>
      _fromProgress + (_toProgress - _fromProgress) * _progress.value;
  double get _offset =>
      _fromOffset + (_toOffset - _fromOffset) * _progress.value;

  void _retarget(double preview, double offset) {
    final currentPreview = _preview;
    final currentOffset = _offset;
    _progress.stop();
    _fromProgress = currentPreview;
    _fromOffset = currentOffset;
    _toProgress = preview;
    _toOffset = offset;
    _progress.value = 0;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
  }

  @override
  bool handleStartBackGesture(PredictiveBackEvent event) {
    final route = _route;
    if (event.isButtonEvent ||
        MediaQuery.disableAnimationsOf(context) ||
        route == null ||
        !route.isCurrent ||
        !widget.isOpen() ||
        !AppNavigationScope.isActiveOf(context) ||
        !TickerMode.valuesOf(context).enabled) {
      return false;
    }
    _retarget(1, event.swipeEdge == SwipeEdge.left ? 16 : -16);
    _progress.value = event.progress;
    return true;
  }

  @override
  void handleUpdateBackGestureProgress(PredictiveBackEvent event) {
    if (_route?.isCurrent ?? false) _progress.value = event.progress;
  }

  Future<void> _restore() async {
    _retarget(0, 0);
    await _progress.animateTo(1, curve: AppMotion.standardCurve);
  }

  @override
  void handleCancelBackGesture() => _restore();

  @override
  void handleCommitBackGesture() {
    if (_route?.isCurrent == true && widget.isOpen()) widget.close();
    _restore();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _progress,
    child: widget.child,
    builder: (context, child) => Transform.translate(
      offset: Offset(_offset, 0),
      child: Transform.scale(
        alignment: widget.alignment,
        scale: 1 - .04 * _preview,
        child: child,
      ),
    ),
  );
}
