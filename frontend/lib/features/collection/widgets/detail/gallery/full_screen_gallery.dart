import '../../../../../core/widgets/media_image_hero.dart';
import 'dart:math' as math;
import 'dart:ui';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../../../../../core/media/media_manifest_client.dart';
import '../../../../../core/media/media_source_session.dart';
import '../../../../../core/network/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../../core/media/media_asset.dart';
import '../../../../../core/widgets/network_thumbnail.dart';
import '../../../../../core/widgets/media_overlay_surface.dart';
import '../../../../../core/utils/toast.dart';
import '../../../../../theme/design_tokens.dart';
import '../../../../../theme/app_theme.dart';

class FullScreenGallery extends ConsumerStatefulWidget {
  final List<String> images;
  final int initialIndex;
  final Map<String, List<String>> fallbackUrlsByImage;
  final Map<String, MediaAsset> mediaAssetsByImage;
  final int contentId;
  final Color? contentColor;
  final String? customHeroTag;
  final Function(int)? onPageChanged;

  const FullScreenGallery({
    super.key,
    required this.images,
    required this.initialIndex,
    this.fallbackUrlsByImage = const {},
    this.mediaAssetsByImage = const {},
    required this.contentId,
    this.contentColor,
    this.customHeroTag,
    this.onPageChanged,
  });

  @override
  ConsumerState<FullScreenGallery> createState() => _FullScreenGalleryState();
}

class _FullScreenGalleryState extends ConsumerState<FullScreenGallery>
    with TickerProviderStateMixin {
  late int _currentIndex;
  late PageController _controller;
  final FocusNode _keyboardFocus = FocusNode(debugLabel: 'fullscreen-gallery');
  final GlobalKey _viewportKey = GlobalKey();
  double _dragOffset = 0;
  final Map<int, int> _rotationTurns = {};
  final Map<int, TransformationController> _transformControllers = {};
  bool _isZoomed = false;
  bool _saving = false;
  Offset _doubleTapPosition = Offset.zero;
  late final AnimationController _dragReturn;
  late final AnimationController _zoomMotion;
  double _dragReturnStart = 0;
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
    _currentIndex = widget.initialIndex;
    _controller = PageController(initialPage: widget.initialIndex);
    _dragReturn =
        AnimationController(vsync: this, duration: AppMotion.contentSwap)
          ..addListener(() {
            setState(() {
              _dragOffset =
                  _dragReturnStart *
                  (1 - AppMotion.standardCurve.transform(_dragReturn.value));
            });
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
  void dispose() {
    _dragReturn.dispose();
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
    if (_dragOffset == 0) return;
    _dragReturn.stop();
    if (MediaQuery.disableAnimationsOf(context)) {
      setState(() => _dragOffset = 0);
      return;
    }
    _dragReturnStart = _dragOffset;
    _dragReturn.forward(from: 0);
  }

  String _getHeroTag(int index) {
    if (index == widget.initialIndex && widget.customHeroTag != null) {
      return widget.customHeroTag!;
    }
    // 注意：这里的通用 Tag 必须与 RichContent.dart 或 MediaGalleryItem.dart 中的生成逻辑严格对齐
    return index == 0
        ? 'content-image-${widget.contentId}'
        : 'image-$index-${widget.contentId}';
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
          _changePage(-1),
      const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
          _changePage(1),
      const SingleActivator(LogicalKeyboardKey.escape): () =>
          Navigator.pop(context),
    },
    child: Focus(
      focusNode: _keyboardFocus,
      autofocus: true,
      child: HeroMode(
        enabled: !MediaQuery.disableAnimationsOf(context),
        child: AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle.light,
          child: Theme(
            data: AppTheme.dark(
              ColorScheme.fromSeed(
                seedColor:
                    widget.contentColor ??
                    Theme.of(context).colorScheme.primary,
                brightness: Brightness.dark,
              ),
            ),
            child: Builder(builder: _buildGallery),
          ),
        ),
      ),
    ),
  );

  void _changePage(int delta) {
    final target = _currentIndex + delta;
    if (target < 0 || target >= widget.images.length) return;
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
    final progress = ModalRoute.of(context)!.animation!;
    final dragOpacity = (1 - (_dragOffset.abs() / 300)).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Glass Background
          Positioned.fill(
            child: GestureDetector(
              excludeFromSemantics: true,
              onTap: () => Navigator.pop(context),
              child: AnimatedBuilder(
                animation: progress,
                builder: (context, _) {
                  final amount =
                      Curves.easeOutCubic.transform(progress.value) *
                      dragOpacity;
                  return BackdropFilter(
                    filter: ImageFilter.blur(
                      sigmaX: 16 * amount,
                      sigmaY: 16 * amount,
                    ),
                    child: ColoredBox(
                      color: Theme.of(
                        this.context,
                      ).colorScheme.surface.withValues(alpha: 0.2 * amount),
                    ),
                  );
                },
              ),
            ),
          ),
          // Images
          GestureDetector(
            onVerticalDragStart: _isZoomed ? null : (_) => _dragReturn.stop(),
            onVerticalDragUpdate: _isZoomed
                ? null
                : (details) {
                    setState(() {
                      _dragOffset += details.primaryDelta!;
                    });
                  },
            onVerticalDragEnd: _isZoomed
                ? null
                : (details) {
                    if (_dragOffset.abs() > 100) {
                      Navigator.pop(context);
                    } else {
                      _returnFromDrag();
                    }
                  },
            onVerticalDragCancel: _returnFromDrag,
            child: Transform.translate(
              offset: Offset(0, _dragOffset),
              child: PageView.builder(
                key: _viewportKey,
                controller: _controller,
                physics: _isZoomed
                    ? const NeverScrollableScrollPhysics()
                    : const PageScrollPhysics(),
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
                },
                itemBuilder: (context, index) {
                  final transformController = _getTransformController(index);
                  return GestureDetector(
                    excludeFromSemantics: true,
                    onTap: () => Navigator.pop(context),
                    onDoubleTapDown: (details) {
                      _doubleTapPosition = details.localPosition;
                    },
                    onDoubleTap: () => _handleDoubleTap(index),
                    child: InteractiveViewer(
                      onInteractionStart: (_) => _zoomMotion.stop(),
                      transformationController: transformController,
                      minScale: 1.0,
                      maxScale: 4.0,
                      panEnabled: true,
                      scaleEnabled: true,
                      child: Center(
                        child: _RotatingGalleryImage(
                          quarterTurns: _rotationTurns[index] ?? 0,
                          child: MediaImageHero(
                            tag: _getHeroTag(index),
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
                  );
                },
              ),
            ),
          ),

          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              minimum: const EdgeInsets.all(AppSpacing.sm),
              child: Align(
                alignment: Alignment.topCenter,
                child: FadeTransition(
                  opacity: progress,
                  child: MediaOverlaySurface(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.xxs),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: '关闭图集',
                            onPressed: () => Navigator.pop(context),
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
                                    ?.copyWith(color: Colors.white),
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
        child: FadeTransition(
          opacity: ModalRoute.of(context)!.animation!,
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
