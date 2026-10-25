import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/local_settings_provider.dart';

// A new opaque scope on server/account changes; credentials never enter image keys.
final mediaImageCacheScopeProvider = Provider<Object>((ref) {
  ref.watch(
    localSettingsProvider.select((value) => (value.baseUrl, value.apiToken)),
  );
  return Object();
});

class AssetImageProvider extends ImageProvider<AssetImageProvider> {
  const AssetImageProvider(
    this.url, {
    required this.cacheKey,
    required this.scope,
    this.coverSize,
  });

  final String url;
  final String cacheKey;
  final Object scope;
  final Size? coverSize;

  @override
  Future<AssetImageProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    AssetImageProvider key,
    ImageDecoderCallback decode,
  ) {
    final image = NetworkImage(key.url);
    final size = key.coverSize;
    if (size == null) return image.loadImage(image, decode);
    return image.loadImage(image, (buffer, {getTargetSize}) {
      return decode(
        buffer,
        getTargetSize: (width, height) {
          // Keep enough pixels on both axes for cover cropping, without upscaling.
          final scale = math.min(
            1.0,
            math.max(size.width / width, size.height / height),
          );
          return ui.TargetImageSize(
            width: (width * scale).ceil(),
            height: (height * scale).ceil(),
          );
        },
      );
    });
  }

  @override
  bool operator ==(Object other) =>
      other is AssetImageProvider &&
      identical(scope, other.scope) &&
      cacheKey == other.cacheKey &&
      coverSize == other.coverSize;

  @override
  int get hashCode => Object.hash(scope, cacheKey, coverSize);
}
