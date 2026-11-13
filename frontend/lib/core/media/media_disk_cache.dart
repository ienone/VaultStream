import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

bool get supportsMediaDiskCache =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS);

String privateCacheKey(String scope, String identity) =>
    sha256.convert(utf8.encode(jsonEncode([scope, identity]))).toString();

final _cache = CacheManager(
  Config(
    'vaultstreamReading',
    stalePeriod: const Duration(days: 365),
    maxNrOfCacheObjects: 2000,
  ),
);

Future<Uint8List?> readCachedBytes(String key) async {
  if (!supportsMediaDiskCache) return null;
  try {
    final entry = await _cache.getFileFromCache(key);
    return await entry?.file.readAsBytes();
  } catch (_) {
    return null;
  }
}

Future<void> cacheBytes(String key, Uint8List bytes) async {
  if (!supportsMediaDiskCache) return;
  try {
    await _cache.putFile(
      key,
      bytes,
      key: key,
      maxAge: const Duration(days: 365),
    );
  } catch (_) {
    // A full or unavailable cache must not interrupt reading.
  }
}

Future<void> forgetCachedBytes(String key) async {
  if (!supportsMediaDiskCache) return;
  try {
    await _cache.removeFile(key);
  } catch (_) {
    // Cache files may already have been evicted by the OS.
  }
}
