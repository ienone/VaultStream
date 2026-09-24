import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../media/media_asset.dart';
import '../media/asset_image_provider.dart';
import '../media/media_manifest_client.dart';
import '../media/media_source_session.dart';
import '../network/api_client.dart';
import '../../theme/design_tokens.dart';

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
  int _requestRevision = 0;

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
    final session = _session;
    final client = ref.read(apiClientProvider);
    final scope = ref.read(mediaImageCacheScopeProvider);
    _session.markAutomaticRefreshAttempted();
    setState(() => _refreshing = true);
    try {
      final refreshed = await refreshMediaManifest(
        client,
        assetId: asset.id,
        purpose: widget.purpose,
      );
      if (!mounted ||
          !identical(_session, session) ||
          !identical(ref.read(mediaImageCacheScopeProvider), scope)) {
        return;
      }
      setState(() {
        _session.replaceManifest(refreshed);
        _refreshing = false;
        _failure = null;
      });
    } catch (_) {
      if (!mounted ||
          !identical(_session, session) ||
          !identical(ref.read(mediaImageCacheScopeProvider), scope)) {
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
      _requestRevision++;
      _session.resetForManualRetry();
      _failure = null;
    });
    if (_session.asset != null) unawaited(_refreshManifest());
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(mediaImageCacheScopeProvider, (_, _) {
      setState(_resetResolver);
    });
    final image = _buildImage(context);
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: widget.borderRadius == null
          ? image
          : ClipRRect(borderRadius: widget.borderRadius!, child: image),
    );
  }

  Widget _buildImage(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final source = _session.current;
    if (source == null) {
      return _ErrorThumbnail(
        colorScheme: colorScheme,
        errorIcon: widget.errorIcon,
        failure: _failure ?? MediaFailureKind.unavailable,
        onRetry: _session.assets.isNotEmpty || _session.sources.isNotEmpty
            ? _retry
            : null,
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
    final cacheScope = ref.watch(mediaImageCacheScopeProvider);
    final image = useFlutterNetworkImage
        // 资产来源需要捕获 HTTP 失败并刷新 manifest，因此使用 Flutter
        // 字节解码路径；裸 URL 只用于非资产化的普通公开图片。
        ? Image(
            image: ResizeImage.resizeIfNeeded(
              widget.maxWidthDiskCache,
              widget.maxHeightDiskCache,
              AssetImageProvider(
                imageUrl,
                cacheKey: source.cacheKey ?? imageUrl,
                scope: cacheScope,
              ),
            ),
            key: ValueKey((imageUrl, _requestRevision)),
            width: widget.width,
            height: widget.height,
            fit: widget.fit,
            loadingBuilder: (context, child, progress) => progress == null
                ? child
                : _LoadingThumbnail(colorScheme: colorScheme),
            errorBuilder: (context, error, stackTrace) =>
                _onError(colorScheme, error),
          )
        : CachedNetworkImage(
            key: ValueKey((imageUrl, _requestRevision)),
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

    return image;
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
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final label = onRetry == null
        ? '暂无图片'
        : failure == MediaFailureKind.formatUnsupported
        ? '当前设备不支持此图片格式'
        : mediaFailureLabel(failure, audioOnly: false);
    final description = onRetry == null ? label : '$label，重试加载';
    return Semantics(
      label: description,
      button: onRetry != null,
      onTap: onRetry,
      excludeSemantics: true,
      child: Material(
        color: colorScheme.surfaceContainerHighest,
        child: InkWell(
          onTap: onRetry,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final detailed =
                  constraints.maxWidth >= 240 &&
                  constraints.maxHeight >=
                      160 * MediaQuery.textScalerOf(context).scale(14) / 14;
              final content = Center(
                child: Padding(
                  padding: EdgeInsets.all(
                    detailed ? AppSpacing.xl : AppSpacing.xxs,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        errorIcon,
                        color: colorScheme.onSurfaceVariant,
                        size: detailed
                            ? 32
                            : (constraints.biggest.shortestSide - 8).clamp(
                                0.0,
                                20.0,
                              ),
                      ),
                      if (detailed) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          label,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                        if (onRetry != null) ...[
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            '重试加载',
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(color: colorScheme.primary),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              );
              return detailed
                  ? content
                  : Tooltip(
                      message: description,
                      excludeFromSemantics: true,
                      child: content,
                    );
            },
          ),
        ),
      ),
    );
  }
}
