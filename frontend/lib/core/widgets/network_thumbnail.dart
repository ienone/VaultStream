import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../media/media_asset.dart';
import '../media/media_manifest_client.dart';
import '../media/media_source_session.dart';
import '../network/api_client.dart';

class NetworkThumbnail extends ConsumerStatefulWidget {
  const NetworkThumbnail({
    super.key,
    this.imageUrl = '',
    this.fallbackUrls = const [],
    this.mediaAsset,
    this.mediaAssets = const [],
    this.purpose = MediaPurpose.detail,
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
  final MediaAsset? mediaAsset;
  final List<MediaAsset> mediaAssets;
  final MediaPurpose purpose;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final int? maxHeightDiskCache;
  final int? maxWidthDiskCache;
  final IconData errorIcon;

  @override
  ConsumerState<NetworkThumbnail> createState() => _NetworkThumbnailState();
}

class _NetworkThumbnailState extends ConsumerState<NetworkThumbnail> {
  late MediaSourceSession _session;
  bool _advanceScheduled = false;
  bool _refreshing = false;
  MediaFailureKind? _failure;

  @override
  void initState() {
    super.initState();
    _resetResolver();
  }

  @override
  void didUpdateWidget(covariant NetworkThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl ||
        oldWidget.fallbackUrls != widget.fallbackUrls ||
        oldWidget.mediaAsset != widget.mediaAsset ||
        oldWidget.mediaAssets != widget.mediaAssets ||
        oldWidget.purpose != widget.purpose) {
      _resetResolver();
    }
  }

  void _resetResolver() {
    final assets = widget.mediaAssets.isNotEmpty
        ? widget.mediaAssets
        : [if (widget.mediaAsset != null) widget.mediaAsset!];
    _session = assets.isEmpty
        ? MediaSourceSession.fromUrls([widget.imageUrl, ...widget.fallbackUrls])
        : MediaSourceSession.fromAssets(assets);
    _advanceScheduled = false;
    _refreshing = false;
    _failure = null;
  }

  Future<void> _refreshManifest() async {
    final asset = _session.asset;
    if (asset == null || _refreshing || _session.automaticRefreshAttempted) {
      return;
    }
    _session.markAutomaticRefreshAttempted();
    setState(() => _refreshing = true);
    try {
      final refreshed = await refreshMediaManifest(
        ref.read(apiClientProvider),
        assetId: asset.id,
        purpose: widget.purpose,
      );
      if (!mounted || !_session.assets.any((item) => item.id == asset.id)) {
        return;
      }
      setState(() {
        _session.replaceManifest(refreshed);
        _refreshing = false;
        _failure = null;
      });
    } catch (_) {
      if (!mounted || !_session.assets.any((item) => item.id == asset.id)) {
        return;
      }
      setState(() {
        _refreshing = false;
        if (!_session.moveNext()) {
          _failure = MediaFailureKind.signatureExpired;
        }
      });
    }
  }

  void _reportMissing(MediaSource source) {
    final asset = _session.asset;
    final variantId = source.variantId;
    if (asset == null || variantId == null) return;
    unawaited(
      reportLocalMediaFailure(
        ref.read(apiClientProvider),
        assetId: asset.id,
        variantId: variantId,
        errorCode: 'media_blob_missing',
      ).catchError((_) {}),
    );
  }

  Widget _onError(ColorScheme colorScheme, Object error) {
    final source = _session.current;
    if (source == null) {
      return _ErrorThumbnail(
        colorScheme: colorScheme,
        errorIcon: widget.errorIcon,
        failure: MediaFailureKind.unavailable,
        onRetry: _retry,
      );
    }
    final failure = classifyMediaFailure(error, source);
    if (failure == MediaFailureKind.signatureExpired &&
        !_session.automaticRefreshAttempted) {
      if (!_advanceScheduled) {
        _advanceScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _session.current?.url != source.url) return;
          _advanceScheduled = false;
          unawaited(_refreshManifest());
        });
      }
      return _LoadingThumbnail(colorScheme: colorScheme);
    }
    if (failure == MediaFailureKind.localMissing) {
      _reportMissing(source);
    }
    if (_session.hasNext && !_advanceScheduled) {
      _advanceScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _session.current?.url != source.url) return;
        setState(() {
          _session.moveNext();
          _advanceScheduled = false;
          _failure = failure;
        });
      });
      return _LoadingThumbnail(colorScheme: colorScheme);
    }
    return _ErrorThumbnail(
      colorScheme: colorScheme,
      errorIcon: widget.errorIcon,
      failure: failure,
      onRetry: _retry,
    );
  }

  void _retry() {
    setState(() {
      _session.resetForManualRetry();
      _failure = null;
    });
    if (_session.asset != null) unawaited(_refreshManifest());
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final source = _session.current;
    if (source == null) {
      return _ErrorThumbnail(
        colorScheme: colorScheme,
        errorIcon: widget.errorIcon,
        failure: _failure ?? MediaFailureKind.unavailable,
        onRetry: _retry,
      );
    }
    if (_session.currentSignatureExpired() &&
        !_session.automaticRefreshAttempted) {
      if (!_refreshing) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_refreshManifest());
        });
      }
      return _LoadingThumbnail(colorScheme: colorScheme);
    }
    final imageUrl = source.url;
    final useFlutterNetworkImage = _session.assets.isNotEmpty;
    final image = useFlutterNetworkImage
        // 资产来源需要捕获 HTTP 失败并刷新 manifest，因此使用 Flutter
        // 字节解码路径；裸 URL 只用于非资产化的普通公开图片。
        ? Image.network(
            imageUrl,
            key: ValueKey(imageUrl),
            width: widget.width,
            height: widget.height,
            fit: widget.fit,
            cacheHeight: widget.maxHeightDiskCache,
            cacheWidth: widget.maxWidthDiskCache,
            loadingBuilder: (context, child, progress) => progress == null
                ? child
                : _LoadingThumbnail(colorScheme: colorScheme),
            errorBuilder: (context, error, stackTrace) =>
                _onError(colorScheme, error),
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
            errorWidget: (context, url, error) => _onError(colorScheme, error),
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
  const _ErrorThumbnail({
    required this.colorScheme,
    required this.errorIcon,
    required this.failure,
    required this.onRetry,
  });

  final ColorScheme colorScheme;
  final IconData errorIcon;
  final MediaFailureKind failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final label = mediaFailureLabel(failure, audioOnly: false);
    return Semantics(
      label: label,
      button: true,
      child: Tooltip(
        message: '$label，点击重试',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onRetry,
          child: ColoredBox(
            color: colorScheme.errorContainer,
            child: Center(
              child: Icon(
                errorIcon,
                color: colorScheme.onErrorContainer,
                size: 20,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
