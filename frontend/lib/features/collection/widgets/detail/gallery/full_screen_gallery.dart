import '../../../../../core/widgets/media_image_hero.dart';

import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import '../../../../../core/motion/shared_transition.dart';
import '../../../../../core/motion/shared_transition_surface.dart';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../../../core/media/media_manifest_client.dart';
import '../../../../../core/media/media_source_session.dart';
import '../../../../../core/network/api_client.dart';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../../../../../core/media/media_asset.dart';
import '../../../../../core/widgets/network_thumbnail.dart';
import '../../../../../core/widgets/media_overlay_surface.dart';
import '../../../../../core/utils/toast.dart';
import '../../../../../theme/design_tokens.dart';

class FullScreenGallery extends ConsumerStatefulWidget {
  final List<String> images;
  final int initialIndex;
  final Map<String, List<String>> fallbackUrlsByImage;
  final Map<String, MediaAsset> mediaAssetsByImage;
  final int contentId;
  final List<MediaImageIdentity> identities;
  final SharedTransitionSession transition;
  final Function(int)? onPageChanged;

  const FullScreenGallery({
    super.key,
    required this.images,
    required this.initialIndex,
    this.fallbackUrlsByImage = const {},
    this.mediaAssetsByImage = const {},
    required this.contentId,
    required this.identities,
    required this.transition,
    this.onPageChanged,
  });

  @override
  ConsumerState<FullScreenGallery> createState() => _FullScreenGalleryState();
}

class _FullScreenGalleryState extends ConsumerState<FullScreenGallery>
    with TickerProviderStateMixin {
  late int _currentIndex;
  late int _requestedIndex;
  late PageController _controller;
  final FocusNode _keyboardFocus = FocusNode(debugLabel: 'fullscreen-gallery');
  final GlobalKey _viewportKey = GlobalKey();
  final _dragOffset = ValueNotifier(Offset.zero);
  Offset _dragOrigin = Offset.zero;
  Offset _dragStartOffset = Offset.zero;
  bool _dragging = false;
  final _dismissal = ValueNotifier(0.0);
  final Map<int, int> _rotationTurns = {};
  final Map<int, TransformationController> _transformControllers = {};
  final Map<int, GlobalKey> _imageKeys = {};
  Size? _viewportSize;
  bool _isZoomed = false;
  bool _saving = false;
  Offset _doubleTapPosition = Offset.zero;
  late final AnimationController _dragReturn;
  late final AnimationController _zoomMotion;
  Offset _dragReturnStart = Offset.zero;
  Matrix4Tween? _zoomTween;
  TransformationController? _zoomTarget;

  Future<void> _saveCurrentImage() async {
    if (_saving) return;
    final index = _currentIndex;
    final url = widget.images[index];
    final asset = widget.mediaAssetsByImage[url];
    setState(() => _saving = true);
    final client = http.Client();
    try {
      final session = asset == null
          ? MediaSourceSession.fromUrls([
              url,
              ...?widget.fallbackUrlsByImage[url],
            ])
          : MediaSourceSession.fromAsset(
              await refreshMediaManifest(
                ref.read(apiClientProvider),
                assetId: asset.id,
                purpose: MediaPurpose.detail,
              ),
            );
      http.Response? image;
      do {
        final source = session.current;
        if (source == null) break;
        if (!source.clientFetchAllowed) continue;
        try {
          // Resource URLs use their own signatures, never the API client token.
          final response = await client
              .get(Uri.parse(source.url))
              .timeout(const Duration(seconds: 30));
          if (response.statusCode == 401 || response.statusCode == 403) {
            throw const FormatException('图片访问未获授权');
          }
          if (response.statusCode == 200 &&
              (response.headers['content-type'] ?? '').startsWith('image/') &&
              response.bodyBytes.isNotEmpty) {
            image = response;
            break;
          }
        } on http.ClientException {
          // Use the next source in the existing manifest order.
        }
      } while (session.moveNext());
      if (image == null) throw const FormatException('图片读取失败，请重试');
      if (!mounted) return;
      final mime = image.headers['content-type']!.split(';').first.trim();
      final extension = switch (mime) {
        'image/jpeg' => 'jpg',
        'image/png' => 'png',
        'image/webp' => 'webp',
        'image/gif' => 'gif',
        'image/avif' => 'avif',
        _ => 'img',
      };
      final name = 'vaultstream-${widget.contentId}-${index + 1}.$extension';
      final location = await getSaveLocation(suggestedName: name);
      if (location == null || !mounted) return;
      await XFile.fromData(
        image.bodyBytes,
        mimeType: mime,
        name: name,
      ).saveTo(location.path);
      if (mounted) Toast.show(context, kIsWeb ? '已交给浏览器下载' : '图片已保存');
    } catch (error) {
      if (mounted) {
        Toast.show(
          context,
          error is FormatException ? error.message : '图片保存失败，请重试',
          isError: true,
        );
      }
    } finally {
      client.close();
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _currentIndex = _requestedIndex = widget.initialIndex;
    widget.transition.prepareClose = _stopMotion;
    _dragOffset.addListener(() {
      _dismissal.value = (_dragOffset.value.distance / 300).clamp(0.0, 1.0);
    });
    _controller = PageController(initialPage: widget.initialIndex);
    _dragReturn =
        AnimationController(vsync: this, duration: AppMotion.contentSwap)
          ..addListener(() {
            _dragOffset.value =
                _dragReturnStart *
                (1 - AppMotion.standardCurve.transform(_dragReturn.value));
          });
    _zoomMotion = AnimationController(vsync: this, duration: AppMotion.standard)
      ..addListener(() {
        _zoomTarget?.value = _zoomTween!.transform(
          AppMotion.standardCurve.transform(_zoomMotion.value),
        );
      });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _keyboardFocus.requestFocus();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = MediaQuery.sizeOf(context);
    final previous = _viewportSize;
    _viewportSize = next;
    if (previous == null || previous == next || previous.isEmpty) return;
    _dragReturn.stop();
    _dragOffset.value = Offset.zero;
    _zoomMotion.stop();
    for (final entry in _transformControllers.entries) {
      final controller = entry.value;
      final scale = controller.value.getMaxScaleOnAxis();
      if (scale <= 1.01) continue;
      final image = _imageKeys[entry.key]?.currentContext?.findRenderObject();
      final asset = widget.mediaAssetsByImage[widget.images[entry.key]];
      final intrinsic =
          image is RenderBox && image.hasSize && !image.size.isEmpty
          ? image.size
          : Size(
              (asset?.width ?? previous.width).toDouble(),
              (asset?.height ?? previous.height).toDouble(),
            );
      final rotated = (_rotationTurns[entry.key] ?? 0).isOdd
          ? Size(intrinsic.height, intrinsic.width)
          : intrinsic;
      final before = applyBoxFit(BoxFit.contain, rotated, previous).destination;
      final after = applyBoxFit(BoxFit.contain, rotated, next).destination;
      final focal =
          controller.toScene(previous.center(Offset.zero)) -
          previous.center(Offset.zero);
      final scene =
          next.center(Offset.zero) + focal * (after.width / before.width);
      final translation = next.center(Offset.zero) - scene * scale;
      controller.value = Matrix4.diagonal3Values(scale, scale, 1)
        ..setTranslationRaw(translation.dx, translation.dy, 0);
    }
  }

  @override
  void dispose() {
    _dragReturn.dispose();
    _dragOffset.dispose();
    _dismissal.dispose();
    widget.transition.prepareClose = null;
    _zoomMotion.dispose();
    for (final controller in _transformControllers.values) {
      controller.dispose();
    }
    _controller.dispose();
    _keyboardFocus.dispose();
    super.dispose();
  }

  TransformationController _getTransformController(int index) {
    return _transformControllers.putIfAbsent(index, () {
      final controller = TransformationController();
      controller.addListener(() {
        if (index != _currentIndex) return;
        final scale = controller.value.getMaxScaleOnAxis();
        final zoomed = scale > 1.01;
        if (zoomed != _isZoomed) {
          setState(() => _isZoomed = zoomed);
        }
      });
      return controller;
    });
  }

  void _handleDoubleTap(int index) => _toggleZoom(index, _doubleTapPosition);

  void _zoomFromToolbar() {
    final viewport =
        _viewportKey.currentContext?.findRenderObject() as RenderBox?;
    if (viewport == null) return;
    _toggleZoom(_currentIndex, viewport.size.center(Offset.zero));
  }

  void _toggleZoom(int index, Offset anchor) {
    final controller = _getTransformController(index);
    _zoomMotion.stop();
    final target = controller.value != Matrix4.identity()
        ? Matrix4.identity()
        : (Matrix4.diagonal3Values(2.0, 2.0, 1.0)
            ..setTranslationRaw(-anchor.dx, -anchor.dy, 0));
    if (MediaQuery.disableAnimationsOf(context)) {
      controller.value = target;
      return;
    }
    _zoomTarget = controller;
    _zoomTween = Matrix4Tween(begin: controller.value.clone(), end: target);
    _zoomMotion.forward(from: 0);
  }

  void _returnFromDrag() {
    if (_dragOffset.value == Offset.zero) return;
    _dragReturn.stop();
    if (MediaQuery.disableAnimationsOf(context)) {
      _dragOffset.value = Offset.zero;
      return;
    }
    _dragReturnStart = _dragOffset.value;
    _dragReturn.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
          _changePage(-1),
      const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
          _changePage(1),
      const SingleActivator(LogicalKeyboardKey.escape): _close,
    },
    child: Focus(
      focusNode: _keyboardFocus,
      autofocus: true,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: Theme.of(context).brightness == Brightness.dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        child: Builder(builder: _buildGallery),
      ),
    ),
  );

  void _close() => widget.transition.close();

  void _stopMotion() {
    _dragReturn.stop();
    _zoomMotion.stop();
    if (_controller.hasClients) {
      _controller.position.jumpTo(_controller.position.pixels);
    }
  }

  void _changePage(int delta) {
    if (widget.transition.closing) return;
    final target = _requestedIndex + delta;
    if (target < 0 || target >= widget.images.length) return;
    _requestedIndex = target;
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.jumpToPage(target);
      return;
    }
    _controller.animateToPage(
      target,
      duration: AppMotion.standard,
      curve: AppMotion.emphasizedCurve,
    );
  }

  Widget _buildGallery(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Fade the overlay while keeping the source page visible during a drag.
          Positioned.fill(
            child: GestureDetector(
              excludeFromSemantics: true,
              onTap: () => _close(),
              child: SharedTransitionSurface(
                session: widget.transition,
                dismissal: _dismissal,
                backdrop: true,
                child: const SizedBox.expand(),
              ),
            ),
          ),
          // Images
          ValueListenableBuilder<Offset>(
            valueListenable: _dragOffset,
            builder: (context, offset, child) => Transform.translate(
              offset: offset,
              child: Transform.scale(
                scale: 1 - (offset.distance / 300).clamp(0.0, 1.0) * .18,
                child: child,
              ),
            ),
            child: PageView.builder(
              key: _viewportKey,
              controller: _controller,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: widget.images.length,
              onPageChanged: (i) {
                _zoomMotion.stop();
                setState(() {
                  _currentIndex = i;
                  _isZoomed =
                      (_transformControllers[i]?.value.getMaxScaleOnAxis() ??
                          1.0) >
                      1.01;
                });
                _keyboardFocus.requestFocus();
                widget.onPageChanged?.call(i);
                widget.transition.select(widget.identities[i]);
              },
              itemBuilder: (context, index) {
                final transformController = _getTransformController(index);
                return GestureDetector(
                  excludeFromSemantics: true,
                  onTap: () => _close(),
                  onDoubleTapDown: (details) {
                    _doubleTapPosition = details.localPosition;
                  },
                  onDoubleTap: () => _handleDoubleTap(index),
                  child: InteractiveViewer(
                    onInteractionStart: (details) {
                      _zoomMotion.stop();
                      _dragReturn.stop();
                      _dragging = !_isZoomed;
                      _dragOrigin = details.focalPoint;
                      _dragStartOffset = _dragOffset.value;
                    },
                    onInteractionUpdate: (details) {
                      if (details.pointerCount > 1 || details.scale > 1.01) {
                        _dragging = false;
                        _returnFromDrag();
                      } else if (_dragging) {
                        _dragOffset.value =
                            _dragStartOffset + details.focalPoint - _dragOrigin;
                      }
                    },
                    onInteractionEnd: (details) {
                      final velocity = details.velocity.pixelsPerSecond;
                      final offset = _dragOffset.value;
                      final movingOutward =
                          offset.dx * velocity.dx + offset.dy * velocity.dy >=
                          0;
                      if (_dragging &&
                          movingOutward &&
                          (offset.distance > 90 ||
                              (offset.distance > 24 &&
                                  velocity.distance > 850))) {
                        _close();
                      } else {
                        _returnFromDrag();
                      }
                      _dragging = false;
                    },
                    transformationController: transformController,
                    minScale: 1.0,
                    maxScale: 4.0,
                    panEnabled: _isZoomed,
                    scaleEnabled: true,
                    child: Center(
                      child: _RotatingGalleryImage(
                        quarterTurns: _rotationTurns[index] ?? 0,
                        child: HeroMode(
                          enabled: index == _currentIndex,
                          child: _GalleryImageBounds(
                            asset:
                                widget.mediaAssetsByImage[widget.images[index]],
                            child: MediaImageHero(
                              key: _imageKeys.putIfAbsent(index, GlobalKey.new),
                              identity: widget.identities[index],
                              session: widget.transition,
                              child: NetworkThumbnail(
                                imageUrl: widget.images[index],
                                mediaAsset: widget
                                    .mediaAssetsByImage[widget.images[index]],
                                purpose: MediaPurpose.detail,
                                fallbackUrls:
                                    widget.fallbackUrlsByImage[widget
                                        .images[index]] ??
                                    const [],
                                fit: BoxFit.contain,
                                errorIcon: Icons.broken_image,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              top: false,
              minimum: const EdgeInsets.all(AppSpacing.sm),
              child: Align(
                alignment: Alignment.bottomCenter,
                child: SharedTransitionSurface(
                  session: widget.transition,
                  dismissal: _dismissal,
                  child: MediaOverlaySurface(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.xxs),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: '关闭图集',
                            onPressed: () => _close(),
                            icon: const Icon(Icons.close_rounded),
                          ),
                          Flexible(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.xs,
                              ),
                              child: Text(
                                '${_currentIndex + 1} / ${widget.images.length}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.labelLarge
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onPrimaryContainer,
                                    ),
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: _isZoomed ? '还原图片' : '放大图片',
                            icon: Icon(
                              _isZoomed
                                  ? Icons.zoom_out_rounded
                                  : Icons.zoom_in_rounded,
                            ),
                            onPressed: _zoomFromToolbar,
                          ),
                          IconButton(
                            tooltip: '旋转图片',
                            icon: const Icon(Icons.rotate_right_rounded),
                            onPressed: () => setState(() {
                              _rotationTurns[_currentIndex] =
                                  (_rotationTurns[_currentIndex] ?? 0) + 1;
                            }),
                          ),
                          IconButton(
                            tooltip: _saving ? '正在保存' : '保存图片',
                            icon: const Icon(Icons.download_rounded),
                            onPressed: _saving ? null : _saveCurrentImage,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (_currentIndex > 0) _pageButton(context, previous: true),
          if (_currentIndex < widget.images.length - 1)
            _pageButton(context, previous: false),
        ],
      ),
    );
  }

  Widget _pageButton(BuildContext context, {required bool previous}) =>
      Positioned.fill(
        child: SharedTransitionSurface(
          session: widget.transition,
          dismissal: _dismissal,
          child: SafeArea(
            minimum: const EdgeInsets.all(AppSpacing.md),
            child: Align(
              alignment: previous
                  ? Alignment.centerLeft
                  : Alignment.centerRight,
              child: MediaOverlaySurface(
                child: IconButton(
                  tooltip: previous ? '上一张' : '下一张',
                  icon: Icon(
                    previous
                        ? Icons.chevron_left_rounded
                        : Icons.chevron_right_rounded,
                  ),
                  onPressed: () => _changePage(previous ? -1 : 1),
                ),
              ),
            ),
          ),
        ),
      );
}

/// Keeps the image endpoint stable while its full-resolution pixels load.
class _GalleryImageBounds extends StatelessWidget {
  const _GalleryImageBounds({required this.asset, required this.child});

  final MediaAsset? asset;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final width = asset?.width;
    final height = asset?.height;
    if (width == null || height == null || width <= 0 || height <= 0) {
      return child;
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = applyBoxFit(
          BoxFit.contain,
          Size(width.toDouble(), height.toDouble()),
          constraints.biggest,
        ).destination;
        return Center(
          child: SizedBox.fromSize(size: size, child: child),
        );
      },
    );
  }
}

/// Fits the rotating canvas throughout the turn, including non-square viewports.
class _RotatingGalleryImage extends StatelessWidget {
  const _RotatingGalleryImage({
    required this.quarterTurns,
    required this.child,
  });

  final int quarterTurns;
  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: quarterTurns.toDouble(), end: quarterTurns.toDouble()),
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : AppMotion.standard,
    curve: AppMotion.standardCurve,
    child: child,
    builder: (context, turns, child) => LayoutBuilder(
      builder: (context, constraints) {
        final angle = turns * math.pi / 2;
        final sine = math.sin(angle).abs();
        final cosine = math.cos(angle).abs();
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final swap = sine * sine;
        final canvasWidth = lerpDouble(width, height, swap)!;
        final canvasHeight = lerpDouble(height, width, swap)!;
        final scale = math.min(
          width / (canvasWidth * cosine + canvasHeight * sine),
          height / (canvasWidth * sine + canvasHeight * cosine),
        );
        return Transform.rotate(
          angle: angle,
          child: Transform.scale(
            scale: scale,
            child: OverflowBox(
              minWidth: canvasWidth,
              maxWidth: canvasWidth,
              minHeight: canvasHeight,
              maxHeight: canvasHeight,
              child: Center(child: child),
            ),
          ),
        );
      },
    ),
  );
}
