import 'dart:ui';
import 'package:flutter/material.dart';
import '../../../../../core/media/media_asset.dart';
import '../../../../../core/widgets/network_thumbnail.dart';
import '../../../../../core/utils/toast.dart';
import '../../../../../theme/design_tokens.dart';

class FullScreenGallery extends StatefulWidget {
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
  State<FullScreenGallery> createState() => _FullScreenGalleryState();
}

class _FullScreenGalleryState extends State<FullScreenGallery> {
  late int _currentIndex;
  late PageController _controller;
  double _dragOffset = 0;
  int _rotationTurns = 0;
  final Map<int, TransformationController> _transformControllers = {};
  bool _isZoomed = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _controller = PageController(initialPage: widget.initialIndex);
    // opaque:false 路由下 PageController.initialPage 并不总是可靠，
    // 使用 post-frame 回调确保跳转到正确位置。
    if (widget.initialIndex > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _controller.hasClients) {
          _controller.jumpToPage(widget.initialIndex);
        }
      });
    }
  }

  @override
  void dispose() {
    for (final controller in _transformControllers.values) {
      controller.dispose();
    }
    _controller.dispose();
    super.dispose();
  }

  TransformationController _getTransformController(int index) {
    return _transformControllers.putIfAbsent(index, () {
      final controller = TransformationController();
      controller.addListener(() {
        final scale = controller.value.getMaxScaleOnAxis();
        final zoomed = scale > 1.01;
        if (zoomed != _isZoomed) {
          setState(() => _isZoomed = zoomed);
        }
      });
      return controller;
    });
  }

  void _handleDoubleTap(int index) {
    final controller = _getTransformController(index);
    if (controller.value != Matrix4.identity()) {
      controller.value = Matrix4.identity();
    } else {
      controller.value = Matrix4.diagonal3Values(2.0, 2.0, 1.0);
    }
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
  Widget build(BuildContext context) {
    final opacity = (1 - (_dragOffset.abs() / 300)).clamp(0.0, 1.0);
    final theme = Theme.of(context);
    final colorScheme = widget.contentColor != null
        ? ColorScheme.fromSeed(
            seedColor: widget.contentColor!,
            brightness: theme.brightness,
          )
        : theme.colorScheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Glass Background
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(
                  color: Colors.black.withValues(alpha: 0.6 * opacity),
                ),
              ),
            ),
          ),
          // Images
          GestureDetector(
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
                      setState(() {
                        _dragOffset = 0;
                      });
                    }
                  },
            child: Transform.translate(
              offset: Offset(0, _dragOffset),
              child: PageView.builder(
                controller: _controller,
                physics: _isZoomed
                    ? const NeverScrollableScrollPhysics()
                    : const PageScrollPhysics(),
                itemCount: widget.images.length,
                onPageChanged: (i) {
                  setState(() {
                    _currentIndex = i;
                    _rotationTurns = 0;
                  });
                  widget.onPageChanged?.call(i);
                },
                itemBuilder: (context, index) {
                  final transformController = _getTransformController(index);
                  return GestureDetector(
                    onTap: () => Navigator.pop(context),
                    onDoubleTap: () => _handleDoubleTap(index),
                    child: InteractiveViewer(
                      transformationController: transformController,
                      minScale: 1.0,
                      maxScale: 4.0,
                      panEnabled: true,
                      scaleEnabled: true,
                      child: Center(
                        child: Hero(
                          tag: _getHeroTag(index),
                          child: RotatedBox(
                            quarterTurns: index == _currentIndex
                                ? _rotationTurns
                                : 0,
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

          // Capsule Toolbar (compact)
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 0,
            right: 0,
            child: Center(
              child: ClipRRect(
                borderRadius: AppShape.paneBorder,
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.xs,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer.withValues(
                        alpha: 0.35,
                      ),
                      borderRadius: AppShape.paneBorder,
                      border: Border.all(
                        color: colorScheme.onPrimaryContainer.withValues(
                          alpha: 0.15,
                        ),
                        width: 0.5,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${_currentIndex + 1} / ${widget.images.length}',
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: colorScheme.onPrimaryContainer,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Container(
                          width: 1,
                          height: 14,
                          color: colorScheme.onPrimaryContainer.withValues(
                            alpha: 0.2,
                          ),
                        ),
                        const SizedBox(width: 2),
                        IconButton(
                          constraints: const BoxConstraints(),
                          padding: const EdgeInsets.all(4),
                          icon: Icon(
                            Icons.rotate_right_rounded,
                            color: colorScheme.onPrimaryContainer,
                            size: 18,
                          ),
                          onPressed: () {
                            setState(() {
                              _rotationTurns = (_rotationTurns + 1) % 4;
                            });
                          },
                        ),
                        IconButton(
                          constraints: const BoxConstraints(),
                          padding: const EdgeInsets.all(4),
                          icon: Icon(
                            Icons.download_rounded,
                            color: colorScheme.onPrimaryContainer,
                            size: 18,
                          ),
                          onPressed: () {
                            Toast.show(context, '下载功能正在开发中...');
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Navigation buttons (for desktop/large screen) with blur effect
          if (widget.images.length > 1) ...[
            if (_currentIndex > 0)
              Positioned(
                left: 16,
                top: 0,
                bottom: 0,
                child: Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.xl),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                      child: Container(
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer.withValues(
                            alpha: 0.35,
                          ),
                          borderRadius: BorderRadius.circular(AppRadius.xl),
                          border: Border.all(
                            color: colorScheme.onPrimaryContainer.withValues(
                              alpha: 0.15,
                            ),
                            width: 0.5,
                          ),
                        ),
                        child: IconButton(
                          icon: Icon(
                            Icons.chevron_left,
                            color: colorScheme.onPrimaryContainer,
                          ),
                          onPressed: () {
                            _controller.previousPage(
                              duration: AppMotion.standard,
                              curve: AppMotion.emphasizedCurve,
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (_currentIndex < widget.images.length - 1)
              Positioned(
                right: 16,
                top: 0,
                bottom: 0,
                child: Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.xl),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                      child: Container(
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer.withValues(
                            alpha: 0.35,
                          ),
                          borderRadius: BorderRadius.circular(AppRadius.xl),
                          border: Border.all(
                            color: colorScheme.onPrimaryContainer.withValues(
                              alpha: 0.15,
                            ),
                            width: 0.5,
                          ),
                        ),
                        child: IconButton(
                          icon: Icon(
                            Icons.chevron_right,
                            color: colorScheme.onPrimaryContainer,
                          ),
                          onPressed: () {
                            _controller.nextPage(
                              duration: AppMotion.standard,
                              curve: AppMotion.emphasizedCurve,
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
