import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../media/media_candidate_resolver.dart';

class NetworkThumbnail extends StatefulWidget {
  const NetworkThumbnail({
    super.key,
    required this.imageUrl,
    this.fallbackUrls = const [],
    this.httpHeaders,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.maxHeightDiskCache,
    this.maxWidthDiskCache,
    this.errorIcon = Icons.hide_image_outlined,
  });

  final String imageUrl;
  final List<String> fallbackUrls;
  final Map<String, String>? httpHeaders;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final int? maxHeightDiskCache;
  final int? maxWidthDiskCache;
  final IconData errorIcon;

  @override
  State<NetworkThumbnail> createState() => _NetworkThumbnailState();
}

class _NetworkThumbnailState extends State<NetworkThumbnail> {
  late MediaCandidateResolver _resolver;
  bool _advanceScheduled = false;

  @override
  void initState() {
    super.initState();
    _resetResolver();
  }

  @override
  void didUpdateWidget(covariant NetworkThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl ||
        oldWidget.fallbackUrls != widget.fallbackUrls) {
      _resetResolver();
    }
  }

  void _resetResolver() {
    _resolver = MediaCandidateResolver([
      widget.imageUrl,
      ...widget.fallbackUrls,
    ]);
    _advanceScheduled = false;
  }

  Widget _onError(ColorScheme colorScheme) {
    if (_resolver.hasNext && !_advanceScheduled) {
      _advanceScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _resolver.moveNext();
          _advanceScheduled = false;
        });
      });
      return _LoadingThumbnail(colorScheme: colorScheme);
    }
    return _ErrorThumbnail(
      colorScheme: colorScheme,
      errorIcon: widget.errorIcon,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final imageUrl = _resolver.current;
    if (imageUrl == null) {
      return _ErrorThumbnail(
        colorScheme: colorScheme,
        errorIcon: widget.errorIcon,
      );
    }
    final headers = _resolver.index == 0 ? widget.httpHeaders : null;
    final image = headers != null && headers.isNotEmpty
        // CachedNetworkImage 在 Web 上可能退化为不支持自定义请求头的
        // <img> 加载。需要鉴权的本地媒体必须使用 Flutter 的字节解码
        // 路径，才能通过 XHR 带上 X-API-Token。
        ? Image.network(
            imageUrl,
            headers: headers,
            key: ValueKey(imageUrl),
            width: widget.width,
            height: widget.height,
            fit: widget.fit,
            cacheHeight: widget.maxHeightDiskCache,
            cacheWidth: widget.maxWidthDiskCache,
            loadingBuilder: (context, child, progress) => progress == null
                ? child
                : _LoadingThumbnail(colorScheme: colorScheme),
            errorBuilder: (context, error, stackTrace) => _onError(colorScheme),
          )
        : CachedNetworkImage(
            key: ValueKey(imageUrl),
            imageUrl: imageUrl,
            width: widget.width,
            height: widget.height,
            fit: widget.fit,
            maxHeightDiskCache: widget.maxHeightDiskCache,
            maxWidthDiskCache: widget.maxWidthDiskCache,
            placeholder: (context, url) =>
                _LoadingThumbnail(colorScheme: colorScheme),
            errorWidget: (context, url, error) => _onError(colorScheme),
          );

    final radius = widget.borderRadius;
    if (radius == null) {
      return image;
    }
    return ClipRRect(borderRadius: radius, child: image);
  }
}

class _LoadingThumbnail extends StatelessWidget {
  const _LoadingThumbnail({required this.colorScheme});

  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: colorScheme.surfaceContainerHighest,
    child: const Center(
      child: SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    ),
  );
}

class _ErrorThumbnail extends StatelessWidget {
  const _ErrorThumbnail({required this.colorScheme, required this.errorIcon});

  final ColorScheme colorScheme;
  final IconData errorIcon;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: colorScheme.errorContainer,
    child: Center(
      child: Icon(errorIcon, color: colorScheme.onErrorContainer, size: 20),
    ),
  );
}
