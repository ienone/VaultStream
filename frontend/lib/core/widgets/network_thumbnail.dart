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
    final image = CachedNetworkImage(
      imageUrl: imageUrl,
      httpHeaders: httpHeaders,
      width: width,
      height: height,
      fit: fit,
      maxHeightDiskCache: maxHeightDiskCache,
      maxWidthDiskCache: maxWidthDiskCache,
      placeholder: (context, url) => ColoredBox(
        color: colorScheme.surfaceContainerHighest,
        child: const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
      errorWidget: (context, url, error) => ColoredBox(
        color: colorScheme.errorContainer,
        child: Center(
          child: Icon(errorIcon, color: colorScheme.onErrorContainer, size: 20),
        ),
      ),
    );

    final radius = borderRadius;
    if (radius == null) {
      return image;
    }
    return ClipRRect(borderRadius: radius, child: image);
  }
}
