import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:extended_image/extended_image.dart';
import '../../../../../core/network/image_headers.dart';

class FullScreenGallery extends StatefulWidget {
  final List<String> images;
  final int initialIndex;
  final String apiBaseUrl;
  final String? apiToken;
  final int contentId;
  final Color? contentColor;
  final String? customHeroTag;
  final Function(int)? onPageChanged;

  const FullScreenGallery({
    super.key,
    required this.images,
    required this.initialIndex,
    required this.apiBaseUrl,
    this.apiToken,
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
                            child: ExtendedImage.network(
                              widget.images[index],
                              headers: buildImageHeaders(
                                imageUrl: widget.images[index],
                                baseUrl: widget.apiBaseUrl,
                                apiToken: widget.apiToken,
                              ),
                              fit: BoxFit.contain,
                              cache: true,
                              enableMemoryCache: true,
                              clearMemoryCacheWhenDispose: false,
                              loadStateChanged: (state) {
                                switch (state.extendedImageLoadState) {
                                  case LoadState.loading:
                                    return Center(
                                      child: CircularProgressIndicator(
                                        value: state.loadingProgress != null
                                            ? state
                                                      .loadingProgress!
                                                      .cumulativeBytesLoaded /
                                                  (state
                                                          .loadingProgress!
                                                          .expectedTotalBytes ??
                                                      1)
                                            : null,
                                      ),
                                    );
                                  case LoadState.failed:
                                    return Container(
                                      color: colorScheme.errorContainer,
                                      child: Icon(
                                        Icons.broken_image,
                                        color: colorScheme.error,
                                      ),
                                    );
                                  case LoadState.completed:
                                    return state.completedWidget;
                                }
                              },
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
                borderRadius: BorderRadius.circular(20),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer.withValues(
                        alpha: 0.35,
                      ),
                      borderRadius: BorderRadius.circular(20),
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
                          style: TextStyle(
                            color: colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(width: 8),
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
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('下载功能正在开发中...'),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
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
                    borderRadius: BorderRadius.circular(24),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                      child: Container(
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer.withValues(
                            alpha: 0.35,
                          ),
                          borderRadius: BorderRadius.circular(24),
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
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
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
                    borderRadius: BorderRadius.circular(24),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                      child: Container(
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer.withValues(
                            alpha: 0.35,
                          ),
                          borderRadius: BorderRadius.circular(24),
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
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
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
