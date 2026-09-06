import 'package:dio/dio.dart';
import 'package:flutter/painting.dart';

import 'media_asset.dart';

enum MediaFailureKind {
  signatureExpired,
  authorizationDenied,
  localMissing,
  remoteUnavailable,
  formatUnsupported,
  unavailable,
}

class MediaSourceSession {
  MediaSourceSession.fromAsset(MediaAsset asset) : this.fromAssets([asset]);

  MediaSourceSession.fromAssets(Iterable<MediaAsset> assets)
    : _assets = List.of(assets),
      _sources = const [] {
    _rebuildSources();
  }

  MediaSourceSession.fromUrls(Iterable<String> urls)
    : _assets = const [],
      _sources = _deduplicate(
        urls.map(
          (url) =>
              MediaSource(url: url, sourceKind: MediaSourceKind.remoteDirect),
        ),
      );

  List<MediaAsset> _assets;
  List<MediaSource> _sources;
  final Map<String, MediaAsset> _sourceAssets = {};
  int _index = 0;
  final Set<int> _automaticallyRefreshedAssets = {};

  // A persisted asset still exists when its expiring sources were omitted.
  MediaAsset? get asset =>
      current == null ? _assets.firstOrNull : _sourceAssets[current!.url];
  List<MediaAsset> get assets => List.unmodifiable(_assets);
  List<MediaSource> get sources => _sources;
  MediaSource? get current => _sources.isEmpty ? null : _sources[_index];
  int get index => _index;
  bool get hasNext => _index + 1 < _sources.length;
  bool get automaticRefreshAttempted {
    final currentAsset = asset;
    return currentAsset != null &&
        _automaticallyRefreshedAssets.contains(currentAsset.id);
  }

  bool currentSignatureExpired([DateTime? now]) {
    final source = current;
    return source?.sourceKind == MediaSourceKind.localSigned &&
        source!.isExpiredAt(now ?? DateTime.now().toUtc());
  }

  bool moveNext() {
    if (!hasNext) return false;
    _index += 1;
    return true;
  }

  void markAutomaticRefreshAttempted() {
    final currentAsset = asset;
    if (currentAsset != null) {
      _automaticallyRefreshedAssets.add(currentAsset.id);
    }
  }

  void replaceManifest(MediaAsset asset) {
    final previous = current;
    final assetIndex = _assets.indexWhere((item) => item.id == asset.id);
    if (assetIndex >= 0) {
      _assets[assetIndex] = asset;
    } else {
      _assets = [asset];
    }
    _rebuildSources();
    _index = 0;
    if (previous?.variantId != null) {
      final sameVariant = _sources.indexWhere(
        (source) => source.variantId == previous!.variantId,
      );
      if (sameVariant >= 0) _index = sameVariant;
    }
  }

  void resetForManualRetry() {
    _index = 0;
    _automaticallyRefreshedAssets.clear();
  }

  void _rebuildSources() {
    _sourceAssets.clear();
    _sources = _deduplicate([
      for (final asset in _assets)
        for (final source in asset.sources) source,
    ]);
    for (final asset in _assets) {
      for (final source in asset.sources) {
        _sourceAssets.putIfAbsent(source.url, () => asset);
      }
    }
  }

  static List<MediaSource> _deduplicate(Iterable<MediaSource> sources) {
    final seen = <String>{};
    return [
      for (final source in sources)
        if (source.url.trim().isNotEmpty && seen.add(source.url.trim())) source,
    ];
  }
}

int? mediaHttpStatus(Object error) {
  if (error is NetworkImageLoadException) return error.statusCode;
  if (error is DioException) return error.response?.statusCode;
  return null;
}

MediaFailureKind classifyMediaFailure(
  Object error,
  MediaSource source, {
  DateTime? now,
}) {
  final status = mediaHttpStatus(error);
  if (source.sourceKind == MediaSourceKind.localSigned &&
      (status == 410 || source.isExpiredAt(now ?? DateTime.now().toUtc()))) {
    return MediaFailureKind.signatureExpired;
  }
  if (status == 401 || status == 403) {
    return MediaFailureKind.authorizationDenied;
  }
  if (status == 404 && source.sourceKind == MediaSourceKind.localSigned) {
    return MediaFailureKind.localMissing;
  }
  if (status == 415) return MediaFailureKind.formatUnsupported;
  if ((status == 502 || status == 504) &&
      source.sourceKind != MediaSourceKind.localSigned) {
    return MediaFailureKind.remoteUnavailable;
  }
  return MediaFailureKind.unavailable;
}

String mediaFailureLabel(MediaFailureKind failure, {required bool audioOnly}) {
  return switch (failure) {
    MediaFailureKind.signatureExpired => '媒体授权已过期，刷新失败',
    MediaFailureKind.authorizationDenied => '媒体授权无效',
    MediaFailureKind.localMissing => '归档文件缺失，已标记待修复',
    MediaFailureKind.remoteUnavailable => '远端媒体暂时不可达',
    MediaFailureKind.formatUnsupported =>
      audioOnly ? '当前设备不支持此音频格式' : '当前设备不支持此视频格式',
    MediaFailureKind.unavailable => audioOnly ? '音频加载失败' : '媒体加载失败',
  };
}
