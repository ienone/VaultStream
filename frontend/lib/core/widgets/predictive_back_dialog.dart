import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/design_tokens.dart';

/// Adds a reversible back preview to a dialog without changing its result,
/// barrier, focus handling, or the form's PopScope contract.
class PredictiveBackDialog extends StatefulWidget {
  const PredictiveBackDialog({super.key, required this.child});

  final Widget child;

  @override
  State<PredictiveBackDialog> createState() => _PredictiveBackDialogState();
}

class _PredictiveBackDialogState extends State<PredictiveBackDialog>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final _progress = AnimationController(
    vsync: this,
    duration: AppMotion.surfaceExit,
  );
  ModalRoute<dynamic>? _route;
  NavigatorState? _gestureNavigator;
  double _fromProgress = 0;
  double _toProgress = 0;
  double _fromOffset = 0;
  double _toOffset = 0;
  int _generation = 0;

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

  void _releaseGesture() {
    _gestureNavigator?.didStopUserGesture();
    _gestureNavigator = null;
  }

  @override
  bool handleStartBackGesture(PredictiveBackEvent event) {
    final route = _route;
    if (event.isButtonEvent ||
        MediaQuery.disableAnimationsOf(context) ||
        route == null ||
        !route.isCurrent ||
        !route.popGestureEnabled) {
      return false;
    }
    _generation++;
    _retarget(1, event.swipeEdge == SwipeEdge.left ? 16 : -16);
    _releaseGesture();
    _gestureNavigator = route.navigator!..didStartUserGesture();
    _progress.value = event.progress;
    return true;
  }

  @override
  void handleUpdateBackGestureProgress(PredictiveBackEvent event) {
    if (_route?.isCurrent ?? false) _progress.value = event.progress;
  }

  Future<void> _restore() async {
    final generation = ++_generation;
    _retarget(0, 0);
    await _progress.animateTo(1, curve: AppMotion.standardCurve);
    if (mounted && generation == _generation) _releaseGesture();
  }

  @override
  void handleCancelBackGesture() => _restore();

  @override
  void handleCommitBackGesture() async {
    final route = _route;
    final navigator = _gestureNavigator;
    _generation++;
    _releaseGesture();
    if (route == null || !route.isCurrent || navigator == null) {
      _restore();
      return;
    }
    // A guard can change while the finger is down. Recheck it at commit.
    await navigator.maybePop();
    if (mounted && route.isCurrent) _restore();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _generation++;
    _releaseGesture();
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _progress,
    child: widget.child,
    builder: (context, child) => Transform.translate(
      offset: Offset(_offset, 0),
      child: Transform.scale(scale: 1 - .04 * _preview, child: child),
    ),
  );
}
