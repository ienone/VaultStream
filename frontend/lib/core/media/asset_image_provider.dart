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
  });

  final String url;
  final String cacheKey;
  final Object scope;

  @override
  Future<AssetImageProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    AssetImageProvider key,
    ImageDecoderCallback decode,
  ) {
    final image = NetworkImage(key.url);
    return image.loadImage(image, decode);
  }

  @override
  bool operator ==(Object other) =>
      other is AssetImageProvider &&
      identical(scope, other.scope) &&
      cacheKey == other.cacheKey;

  @override
  int get hashCode => Object.hash(scope, cacheKey);
}
