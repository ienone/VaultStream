import 'dart:async';

import 'package:http/http.dart' as http;

import 'media_disk_cache.dart';

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/local_settings_provider.dart';

final mediaImageCacheScopeProvider = Provider<String>((ref) {
  final settings = ref.watch(localSettingsProvider);
  return privateCacheKey(settings.baseUrl, settings.apiToken);
});

class AssetImageDecodeException implements Exception {
  const AssetImageDecodeException(this.cause);
  final Object cause;
  @override
  String toString() => cause.toString();
}

class AssetImageProvider extends ImageProvider<AssetImageProvider> {
  const AssetImageProvider(
    this.url, {
    required this.cacheKey,
    required this.scope,
    this.coverSize,
  });

  final String url;
  final String cacheKey;
  final String scope;
  final Size? coverSize;

  @override
  Future<AssetImageProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    AssetImageProvider key,
    ImageDecoderCallback decode,
  ) {
    final size = key.coverSize;
    Future<ui.Codec> decodeImage(
      ui.ImmutableBuffer buffer, {
      ui.TargetImageSizeCallback? getTargetSize,
    }) async {
      try {
        if (size == null) {
          return await decode(buffer, getTargetSize: getTargetSize);
        }
        return await decode(
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
      } catch (error) {
        throw AssetImageDecodeException(error);
      }
    }

    if (!supportsMediaDiskCache) {
      final image = NetworkImage(key.url);
      return image.loadImage(image, decodeImage);
    }
    Future<ui.Codec> load() async {
      final diskKey = privateCacheKey(scope, cacheKey);
      final bytes = await readCachedBytes(diskKey);
      if (bytes != null) {
        try {
          return await decodeImage(
            await ui.ImmutableBuffer.fromUint8List(bytes),
          );
        } on AssetImageDecodeException {
          await forgetCachedBytes(diskKey);
        }
      }
      final uri = Uri.parse(url);
      final response = await http.get(uri).timeout(const Duration(seconds: 45));
      if (response.statusCode != 200) {
        throw NetworkImageLoadException(
          statusCode: response.statusCode,
          uri: uri,
        );
      }
      final codec = await decodeImage(
        await ui.ImmutableBuffer.fromUint8List(response.bodyBytes),
      );
      unawaited(cacheBytes(diskKey, response.bodyBytes));
      return codec;
    }

    return MultiFrameImageStreamCompleter(
      codec: load().catchError((Object error, StackTrace stack) {
        scheduleMicrotask(() => PaintingBinding.instance.imageCache.evict(key));
        Error.throwWithStackTrace(error, stack);
      }),
      scale: 1,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AssetImageProvider &&
      scope == other.scope &&
      cacheKey == other.cacheKey &&
      coverSize == other.coverSize;

  @override
  int get hashCode => Object.hash(scope, cacheKey, coverSize);
}
