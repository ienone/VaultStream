import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';

import '../../theme/design_tokens.dart';
import '../../routing/overlay_back_observer.dart';

/// Registers mounted presentation endpoints, not business or navigation state.
class SharedTransitionScope extends StatefulWidget {
  const SharedTransitionScope({super.key, required this.child});
  final Widget child;

  @override
  State<SharedTransitionScope> createState() => _SharedTransitionScopeState();
}

class _SharedTransitionScopeState extends State<SharedTransitionScope> {
  final registry = _SourceRegistry();

  @override
  Widget build(BuildContext context) =>
      _RegistryScope(registry: registry, child: widget.child);
}

class _RegistryScope extends InheritedWidget {
  const _RegistryScope({required this.registry, required super.child});
  final _SourceRegistry registry;

  static _SourceRegistry of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_RegistryScope>()!.registry;

  @override
  bool updateShouldNotify(_RegistryScope oldWidget) =>
      registry != oldWidget.registry;
}

class _SourceRegistry {
  final sources = <_SharedElementState>{};
  final active = <NavigatorState, Future<void>>{};

  _SharedElementState? find(
    Object identity,
    Route<dynamic>? owner, {
    BuildContext? origin,
    _SharedElementState? preferred,
  }) {
    final candidates = sources.where(
      (source) =>
          source.widget.identity == identity &&
          source.owner == owner &&
          source.visible,
    );
    if (preferred != null && candidates.contains(preferred)) return preferred;
    if (origin != null) {
      for (final source in candidates) {
        var inside = source.context == origin;
        source.context.visitAncestorElements((element) {
          if (element == origin) inside = true;
          return !inside;
        });
        if (inside) return source;
      }
    }
    return candidates.firstOrNull;
  }
}

/// One route owns one transition. Repeated opens share its completion future.
abstract final class SharedTransition {
  static Future<void> openOverlay({
    required BuildContext context,
    required Object identity,
    required Widget Function(SharedTransitionSession session) builder,
  }) {
    final registry = _RegistryScope.of(context);
    final navigator = Navigator.of(context, rootNavigator: true);
    final active = registry.active[navigator];
    if (active != null) return active;
    final session = SharedTransitionSession._(
      registry,
      identity,
      ModalRoute.of(context),
      context,
    );
    final route = _SharedTransitionRoute(
      session: session,
      reduceMotion: MediaQuery.disableAnimationsOf(context),
      builder: builder,
    );
    session._route = route;
    final completion = _present(navigator, route, session, registry);
    registry.active[navigator] = completion;
    return completion;
  }

  static Future<void> _present(
    NavigatorState navigator,
    _SharedTransitionRoute route,
    SharedTransitionSession session,
    _SourceRegistry registry,
  ) async {
    try {
      await navigator.push<void>(route);
      await route.completed;
      session._target?.restoreFocus();
    } finally {
      registry.active.remove(navigator);
      session.dispose();
    }
  }
}

class SharedTransitionSession extends ChangeNotifier {
  SharedTransitionSession._(
    this._registry,
    this._identity,
    this._owner,
    BuildContext origin,
  ) {
    _target = _registry.find(_identity, _owner, origin: origin);
    _origin = _target;
  }

  final _SourceRegistry _registry;
  final Route<dynamic>? _owner;
  Object _identity;
  _SharedElementState? _target;
  _SharedElementState? _origin;
  late final _SharedTransitionRoute _route;
  bool _closing = false;
  VoidCallback? prepareClose;
  bool get closing => _closing;
  Animation<double> get progress => _route.animation!;

  void select(Object identity) {
    if (_closing || identity == _identity) return;
    _identity = identity;
    _target = _registry.find(identity, _owner);
    notifyListeners();
  }

  Object? _tagFor(Object identity) =>
      identity == _identity ? _target?.tag : null;

  /// The caller settles its own selection/gesture before handing back control.
  Future<void> close() async {
    if (_closing || !_route.isCurrent) return;
    _prepareClose();
    // Publish the return endpoint before HeroController collects both routes.
    await WidgetsBinding.instance.endOfFrame;
    if (_route.isCurrent) _route.navigator!.pop();
  }

  void _prepareClose() {
    if (_closing) return;
    _closing = true;
    prepareClose?.call();
    _target = _registry.find(_identity, _owner, preferred: _target ?? _origin);
    notifyListeners();
  }
}

class _SharedTransitionRoute extends PageRouteBuilder<void>
    implements PredictiveOverlayRoute {
  _SharedTransitionRoute({
    required this.session,
    required bool reduceMotion,
    required Widget Function(SharedTransitionSession) builder,
  }) : super(
         opaque: false,
         transitionDuration: reduceMotion
             ? Duration.zero
             : AppMotion.surfaceEnter,
         reverseTransitionDuration: reduceMotion
             ? Duration.zero
             : AppMotion.standard,
         pageBuilder: (context, animation, secondaryAnimation) =>
             AnimatedBuilder(
               animation: session,
               child: builder(session),
               builder: (context, child) =>
                   IgnorePointer(ignoring: session.closing, child: child),
             ),
         transitionsBuilder: (context, animation, secondaryAnimation, child) =>
             child,
       );

  @override
  void prepareBackGesture() => session.prepareClose?.call();

  final SharedTransitionSession session;

  @override
  bool didPop(void result) {
    session._prepareClose();
    return super.didPop(result);
  }
}

/// Each mounted source gets a unique flight tag, including repeated objects.
/// Destinations resolve a visible source in the originating route at close time.
class SharedElement extends StatefulWidget {
  const SharedElement({
    super.key,
    required this.identity,
    required this.child,
    this.session,
    this.flightShuttleBuilder,
  });
  final Object identity;
  final Widget child;
  final SharedTransitionSession? session;
  final HeroFlightShuttleBuilder? flightShuttleBuilder;

  @override
  State<SharedElement> createState() => _SharedElementState();
}

class _SharedElementState extends State<SharedElement> {
  final tag = Object();
  _SourceRegistry? registry;
  Route<dynamic>? owner;
  FocusNode? focus;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    registry?.sources.remove(this);
    if (widget.session == null) {
      registry = _RegistryScope.of(context)..sources.add(this);
      owner = ModalRoute.of(context);
      focus = Focus.maybeOf(context);
    }
  }

  bool get visible {
    if (!mounted || !TickerMode.valuesOf(context).enabled) {
      return false;
    }
    var enabled = true;
    context.visitAncestorElements((element) {
      if (element.widget case HeroMode(enabled: false)) enabled = false;
      return enabled;
    });
    if (!enabled) return false;
    final box = context.findRenderObject();
    if (box is! RenderBox ||
        !box.attached ||
        !box.hasSize ||
        box.size.isEmpty) {
      return false;
    }
    var rect = MatrixUtils.transformRect(
      box.getTransformTo(null),
      Offset.zero & box.size,
    );
    RenderObject child = box;
    for (var parent = child.parent; parent != null; parent = child.parent) {
      if (parent is RenderOffstage && parent.offstage) return false;
      final clip = parent.describeApproximatePaintClip(child);
      if (clip != null) {
        rect = rect.intersect(
          MatrixUtils.transformRect(parent.getTransformTo(null), clip),
        );
      }
      child = parent;
    }
    rect = rect.intersect(Offset.zero & MediaQuery.sizeOf(context));
    return rect.width > 1 && rect.height > 1;
  }

  void restoreFocus() {
    if (visible && focus?.canRequestFocus == true) focus!.requestFocus();
  }

  @override
  void dispose() {
    registry?.sources.remove(this);
    super.dispose();
  }

  Widget _hero(Object flightTag) => HeroMode(
    enabled:
        TickerMode.valuesOf(context).enabled &&
        !MediaQuery.disableAnimationsOf(context),
    child: Hero(
      tag: flightTag,
      transitionOnUserGestures: true,
      flightShuttleBuilder: widget.flightShuttleBuilder,
      child: widget.child,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    if (session == null) return _hero(tag);
    return AnimatedBuilder(
      animation: session,
      builder: (context, _) {
        final flightTag = session._tagFor(widget.identity);
        return FadeTransition(
          opacity: flightTag == null
              ? session.progress
              : kAlwaysCompleteAnimation,
          child: _hero(flightTag ?? tag),
        );
      },
    );
  }
}
