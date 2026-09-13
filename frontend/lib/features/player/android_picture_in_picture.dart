import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import 'global_playback_controller.dart';

final pictureInPictureProvider =
    NotifierProvider<
      PictureInPictureController,
      ({bool supported, bool active})
    >(PictureInPictureController.new);

class PictureInPictureController
    extends Notifier<({bool supported, bool active})> {
  static const _channel = MethodChannel('vaultstream/picture_in_picture');
  Object? _owner;
  Map<String, Object>? _target;

  @override
  ({bool supported, bool active}) build() {
    ref.onDispose(() => _channel.setMethodCallHandler(null));
    return (supported: false, active: false);
  }

  Future<void> initialize() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'modeChanged') {
        state = (supported: state.supported, active: call.arguments == true);
      } else if (call.method == 'dismissed') {
        await ref.read(globalPlaybackProvider.notifier).pause();
      }
    });
    final supported = await _channel.invokeMethod<bool>('isSupported') ?? false;
    state = (supported: supported, active: false);
  }

  Future<void> updateTarget(
    Object owner,
    Rect bounds,
    double ratio,
    bool playing,
  ) async {
    if (!state.supported || state.active) return;
    final target = <String, Object>{
      'left': bounds.left.round(),
      'top': bounds.top.round(),
      'right': bounds.right.round(),
      'bottom': bounds.bottom.round(),
      'ratio': ratio,
      'playing': playing,
    };
    _owner = owner;
    if (mapEquals(_target, target)) return;
    _target = target;
    await _channel.invokeMethod<void>('configure', target);
  }

  void removeTarget(Object owner) {
    if (_owner != owner) return;
    _owner = null;
    _target = null;
    if (state.supported) {
      unawaited(_channel.invokeMethod<void>('disable'));
    }
  }

  Future<bool> enter() async {
    if (!state.supported || _target == null) return false;
    return await _channel.invokeMethod<bool>('enter') ?? false;
  }
}

/// Tracks only the visible video rectangle, never the surrounding page chrome.
class PictureInPictureTarget extends ConsumerStatefulWidget {
  const PictureInPictureTarget({
    super.key,
    required this.controller,
    required this.child,
  });
  final VideoPlayerController controller;
  final Widget child;

  @override
  ConsumerState<PictureInPictureTarget> createState() =>
      _PictureInPictureTargetState();
}

class _PictureInPictureTargetState
    extends ConsumerState<PictureInPictureTarget> {
  late PictureInPictureController _pip;
  bool _scheduled = false;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _pip = ref.read(pictureInPictureProvider.notifier);
    widget.controller.addListener(_schedule);
  }

  @override
  void didUpdateWidget(covariant PictureInPictureTarget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_schedule);
      widget.controller.addListener(_schedule);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visible =
        ModalRoute.isCurrentOf(context) != false &&
        TickerMode.valuesOf(context).enabled;
    _schedule();
  }

  void _schedule() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) return;
      if (!_visible) {
        // During PiP the original page remains mounted but hidden.
        if (!ref.read(pictureInPictureProvider).active) _pip.removeTarget(this);
        return;
      }
      final box = context.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return;
      final ratio = widget.controller.value.aspectRatio;
      final scale = MediaQuery.devicePixelRatioOf(context);
      final origin = box.localToGlobal(Offset.zero) * scale;
      final bounds = (origin & (box.size * scale)).intersect(
        Offset.zero & (MediaQuery.sizeOf(context) * scale),
      );
      if (bounds.isEmpty) {
        _pip.removeTarget(this);
        return;
      }
      unawaited(
        _pip.updateTarget(
          this,
          bounds,
          ratio,
          widget.controller.value.isPlaying,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(pictureInPictureProvider.select((s) => s.supported));
    _schedule();
    return widget.child;
  }

  @override
  void dispose() {
    widget.controller.removeListener(_schedule);
    _pip.removeTarget(this);
    super.dispose();
  }
}

/// Preserve the navigation tree at its original size while the native window
/// displays just the existing decoder's video texture.
class AndroidPictureInPictureHost extends ConsumerStatefulWidget {
  const AndroidPictureInPictureHost({super.key, required this.child});
  final Widget child;
  @override
  ConsumerState<AndroidPictureInPictureHost> createState() =>
      _AndroidPictureInPictureHostState();
}

class _AndroidPictureInPictureHostState
    extends ConsumerState<AndroidPictureInPictureHost> {
  Size? _pageSize;
  MediaQueryData? _pageMedia;
  @override
  Widget build(BuildContext context) {
    final status = ref.watch(pictureInPictureProvider);
    if (!status.supported) return widget.child;
    final pip = status.active;
    final state = ref.watch(globalPlaybackProvider);
    final player = ref.read(globalPlaybackProvider.notifier).videoController;
    if (!pip) _pageMedia = MediaQuery.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!pip) _pageSize = constraints.biggest;
        // The early Android callback precedes the resize. Keep the source
        // page in place until the window actually has its PiP dimensions.
        final showVideoOnly = pip && constraints.biggest != _pageSize;
        final video =
            player != null &&
                state.initialized &&
                state.request?.audioOnly == false &&
                !state.videoAudioOnly
            ? AspectRatio(
                aspectRatio: player.value.aspectRatio,
                child: VideoPlayer(player),
              )
            : const Icon(Icons.graphic_eq_rounded, color: Colors.white);
        return Stack(
          fit: StackFit.expand,
          children: [
            Offstage(
              offstage: showVideoOnly,
              child: TickerMode(
                enabled: !showVideoOnly,
                child: OverflowBox(
                  minWidth: _pageSize?.width,
                  maxWidth: _pageSize?.width,
                  minHeight: _pageSize?.height,
                  maxHeight: _pageSize?.height,
                  child: MediaQuery(data: _pageMedia!, child: widget.child),
                ),
              ),
            ),
            if (showVideoOnly)
              ColoredBox(
                color: Colors.black,
                child: Center(child: video),
              ),
          ],
        );
      },
    );
  }
}
