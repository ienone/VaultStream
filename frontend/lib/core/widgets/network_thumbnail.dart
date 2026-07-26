import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

class NetworkThumbnail extends StatelessWidget {
  const NetworkThumbnail({
    super.key,
    required this.imageUrl,
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
  final Map<String, String>? httpHeaders;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final int? maxHeightDiskCache;
  final int? maxWidthDiskCache;
  final IconData errorIcon;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final headers = httpHeaders;
    final image = headers != null && headers.isNotEmpty
        // CachedNetworkImage 在 Web 上可能退化为不支持自定义请求头的
        // <img> 加载。需要鉴权的本地媒体必须使用 Flutter 的字节解码
        // 路径，才能通过 XHR 带上 X-API-Token。
        ? Image.network(
            imageUrl,
            headers: headers,
            width: width,
            height: height,
            fit: fit,
            cacheHeight: maxHeightDiskCache,
            cacheWidth: maxWidthDiskCache,
            loadingBuilder: (context, child, progress) => progress == null
                ? child
                : _LoadingThumbnail(colorScheme: colorScheme),
            errorBuilder: (context, error, stackTrace) =>
                _ErrorThumbnail(colorScheme: colorScheme, errorIcon: errorIcon),
          )
        : CachedNetworkImage(
            imageUrl: imageUrl,
            width: width,
            height: height,
            fit: fit,
            maxHeightDiskCache: maxHeightDiskCache,
            maxWidthDiskCache: maxWidthDiskCache,
            placeholder: (context, url) =>
                _LoadingThumbnail(colorScheme: colorScheme),
            errorWidget: (context, url, error) =>
                _ErrorThumbnail(colorScheme: colorScheme, errorIcon: errorIcon),
          );

    final radius = borderRadius;
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
