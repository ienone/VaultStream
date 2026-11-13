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
  MediaSourceSession.fromAsset(MediaAsset asset, {this.preferThumbnail = false})
    : _asset = asset,
      _sources = [] {
    _setSources(asset);
  }

  MediaSourceSession.fromUrls(Iterable<String> urls)
    : preferThumbnail = false,
      _sources = _deduplicate(
        urls.map(
          (url) =>
              MediaSource(url: url, sourceKind: MediaSourceKind.remoteDirect),
        ),
      );

  final bool preferThumbnail;
  MediaAsset? _asset;
  List<MediaSource> _sources;
  int _index = 0;
  bool automaticRefreshAttempted = false;
  MediaAsset? get asset => _asset;
  List<MediaSource> get sources => _sources;
  MediaSource? get current => _sources.isEmpty ? null : _sources[_index];
  int get index => _index;
  bool get hasNext => _index + 1 < _sources.length;
  bool currentSignatureExpired([DateTime? now]) {
    final source = current;
    return source?.isExpiredAt(now ?? DateTime.now().toUtc()) ?? false;
  }

  bool moveNext() {
    if (!hasNext) return false;
    _index += 1;
    return true;
  }

  void markAutomaticRefreshAttempted() {
    automaticRefreshAttempted = true;
  }

  void replaceManifest(MediaAsset asset) {
    _asset = asset;
    _setSources(asset);
    _index = 0;
  }

  void resetForManualRetry() {
    _index = 0;
    automaticRefreshAttempted = false;
  }

  void _setSources(MediaAsset asset) {
    _sources = preferThumbnail
        ? _deduplicate([
            ...asset.sources.where((s) => s.variantKind == 'thumbnail'),
            ...asset.sources,
          ])
        : _deduplicate(asset.sources);
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
  if (source.expiresAt != null &&
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
