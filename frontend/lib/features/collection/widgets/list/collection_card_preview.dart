import '../../../../core/layout/workspace_geometry.dart';

import 'package:material_ui/material_ui.dart';

import 'collection_card_text.dart';

import 'package:intl/intl.dart';

import '../../../../core/widgets/network_thumbnail.dart';
import '../../../../theme/design_tokens.dart';
import '../../models/content.dart';
import '../../../../core/media/media_asset.dart';

/// 收藏卡片。
///
/// 信息层级固定为三层，所有模板共用同一套来源与状态语义：
/// 来源身份与时间、原始标题和正文摘录、实际媒体与必要处理状态。
class CollectionCardPreview extends StatelessWidget {
  const CollectionCardPreview({
    super.key,
    required this.content,
    this.onTap,
    this.isHovered = false,
    this.isEmphasized = false,
    this.trailingSpace = 0,
    this.transparentSurface = false,
    this.isList = false,
  });

  final ShareCard content;
  final VoidCallback? onTap;
  final bool isHovered;
  final bool isEmphasized;
  final double trailingSpace;
  final bool transparentSurface;
  final bool isList;

  @override
  Widget build(BuildContext context) {
    final representativeAssets = content.mediaAssets
        .where(
          (asset) =>
              asset.mediaType == MediaType.image &&
              asset.role != MediaRole.avatar &&
              asset.sources.isNotEmpty,
        )
        .toList();
    final representativeAsset = representativeAssets.firstOrNull;
    final contractImageUrls = representativeAssets
        .expand((asset) => asset.sources)
        .map((source) => source.url)
        .where((url) => url.trim().isNotEmpty)
        .toSet()
        .toList(growable: false);
    final imageUrl = contractImageUrls.firstOrNull ?? '';
    final imageFallbackUrls = contractImageUrls.skip(1).toList(growable: false);
    final surface = _CardSurface(
      content: content,
      onTap: onTap,
      imageUrl: imageUrl,
      imageFallbackUrls: imageFallbackUrls,
      mediaAsset: representativeAsset,
      mediaAssets: representativeAssets,
      isList: isList,
      isHovered: isHovered,
      isEmphasized: isEmphasized,
      trailingSpace: trailingSpace,
      transparentSurface: transparentSurface,
    );

    return surface;
  }
}

class _CardSurface extends StatefulWidget {
  const _CardSurface({
    required this.content,
    required this.onTap,
    required this.imageUrl,
    required this.imageFallbackUrls,
    required this.mediaAsset,
    required this.mediaAssets,
    required this.isHovered,
    required this.isEmphasized,
    required this.trailingSpace,
    required this.transparentSurface,
    required this.isList,
  });

  final ShareCard content;
  final VoidCallback? onTap;
  final String imageUrl;
  final List<String> imageFallbackUrls;
  final MediaAsset? mediaAsset;
  final List<MediaAsset> mediaAssets;
  final bool isHovered;
  final bool isEmphasized;
  final double trailingSpace;
  final bool transparentSurface;
  final bool isList;

  @override
  State<_CardSurface> createState() => _CardSurfaceState();
}

class _CardSurfaceState extends State<_CardSurface> {
  bool _imageFailed = false;
  int _imageRevision = 0;
  VoidCallback? _retryImage;

  @override
  void didUpdateWidget(_CardSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.content.id != widget.content.id ||
        oldWidget.imageUrl != widget.imageUrl ||
        oldWidget.mediaAsset != widget.mediaAsset) {
      _imageRevision++;
      _imageFailed = false;
      _retryImage = null;
    }
  }

  Widget _failedMedia(BuildContext context, VoidCallback? retry) {
    if (!_imageFailed) {
      final revision = _imageRevision;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || revision != _imageRevision || _imageFailed) return;
        setState(() {
          _imageFailed = true;
          _retryImage = retry;
        });
      });
    }
    return const SizedBox.shrink();
  }

  void _retryFailedImage() {
    final retry = _retryImage;
    if (retry == null) return;
    setState(() {
      _imageRevision++;
      _imageFailed = false;
      _retryImage = null;
    });
    retry();
  }

  @override
  Widget build(BuildContext context) {
    final content = widget.content;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final copy = CollectionCardText(content);

    final metadata = _CardMeta(content: content);
    final text = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (copy.primary.isNotEmpty)
          Text(
            copy.primary,
            maxLines: copy.maxLines,
            overflow: TextOverflow.ellipsis,
            style: copy.hasTitle
                ? theme.textTheme.titleMedium
                : theme.textTheme.bodyMedium,
          ),
        if (copy.supporting.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            copy.supporting,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
        if (_statusLabel != null) ...[
          const SizedBox(height: AppSpacing.xs),
          _StatusChip(label: _statusLabel!, isError: _statusIsError),
        ],
      ],
    );
    final media = widget.imageUrl.isEmpty
        ? null
        : ClipRRect(
            borderRadius: AppShape.cardMediaBorder,
            child: NetworkThumbnail(
              imageUrl: widget.imageUrl,
              fallbackUrls: widget.imageFallbackUrls,
              mediaAsset: widget.mediaAsset,
              mediaAssets: widget.mediaAssets,
              purpose: MediaPurpose.card,
              fit: BoxFit.cover,
              maxWidthDiskCache: (600 * MediaQuery.devicePixelRatioOf(context))
                  .ceil(),
              maxHeightDiskCache: (160 * MediaQuery.devicePixelRatioOf(context))
                  .ceil(),
              errorIcon: Icons.broken_image_rounded,
              failureBuilder: _failedMedia,
            ),
          );
    return AnimatedContainer(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : AppMotion.stateChange,
      curve: AppMotion.standardCurve,
      decoration: BoxDecoration(
        borderRadius: AppShape.cardBorder,
        color: widget.transparentSurface
            ? Colors.transparent
            : widget.isEmphasized
            ? scheme.secondaryContainer
            : widget.isHovered
            ? scheme.surfaceContainerHighest
            : scheme.surfaceContainerLowest,
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: EdgeInsets.only(right: widget.trailingSpace),
                  child: metadata,
                ),
                const SizedBox(height: AppSpacing.sm),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      if (media == null) {
                        // 文字按自然行高排版；分栏动画的中间高度由卡片外框裁切。
                        return OverflowBox(
                          alignment: Alignment.topLeft,
                          minHeight: 0,
                          maxHeight: double.infinity,
                          child: text,
                        );
                      }
                      final textScale =
                          MediaQuery.textScalerOf(context).scale(16) / 16;
                      if (constraints.maxWidth / textScale < 200) return text;
                      final pane = WorkspaceGeometry.maybeOf(context);
                      final compact =
                          (pane?.overviewWidth ??
                              MediaQuery.sizeOf(context).width) <
                          600;
                      final progress = compact
                          ? 1.0
                          : (pane?.progress ?? (widget.isList ? 1.0 : 0.0));
                      final gridWidth = pane == null
                          ? constraints.maxWidth
                          : (pane.overviewWidth -
                                        24 -
                                        8 *
                                            ((pane.overviewWidth /
                                                        (300 * textScale))
                                                    .floor()
                                                    .clamp(1, 4) -
                                                1)) /
                                    (pane.overviewWidth / (300 * textScale))
                                        .floor()
                                        .clamp(1, 4) -
                                24;
                      final gridImageHeight = (gridWidth / 2.4).clamp(
                        80.0,
                        160.0,
                      );
                      final mediaWidth =
                          constraints.maxWidth +
                          (88 - constraints.maxWidth) * progress;
                      final mediaHeight =
                          gridImageHeight + (64 - gridImageHeight) * progress;
                      final textTop =
                          (gridImageHeight + AppSpacing.sm) * (1 - progress);
                      return SizedBox(
                        height: constraints.hasBoundedHeight
                            ? constraints.maxHeight
                            : textTop + 120 * textScale,
                        child: Stack(
                          children: [
                            Positioned(
                              top: 0,
                              right: 0,
                              width: mediaWidth,
                              height: mediaHeight,
                              child: IgnorePointer(
                                child: Opacity(
                                  opacity: _imageFailed ? 0 : 1,
                                  child: media,
                                ),
                              ),
                            ),
                            Positioned(
                              top: _imageFailed ? 0 : textTop,
                              left: 0,
                              right: (88 + AppSpacing.sm) * progress,
                              child: text,
                            ),
                            if (_imageFailed && _retryImage != null)
                              Positioned(
                                right: 0,
                                bottom: 0,
                                width: 112 + (88 - 112) * progress,
                                height: 48,
                                child: progress >= .5 || textScale > 1.4
                                    ? Align(
                                        alignment: Alignment.bottomRight,
                                        child: IconButton(
                                          onPressed: _retryFailedImage,
                                          tooltip: '重试图片',
                                          icon: const Icon(
                                            Icons.refresh_rounded,
                                          ),
                                        ),
                                      )
                                    : TextButton.icon(
                                        onPressed: _retryFailedImage,
                                        icon: const Icon(
                                          Icons.refresh_rounded,
                                          size: 16,
                                        ),
                                        label: const Text('重试图片'),
                                        style: TextButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                          ),
                                          textStyle: theme.textTheme.labelSmall,
                                        ),
                                      ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 只暴露对用户有行动价值的状态。
  String? get _statusLabel {
    if (widget.content.status == 'parse_failed') return '解析失败';
    if (widget.content.status == 'processing') return '解析中';
    if (widget.content.status == 'unprocessed') return '待解析';
    if (widget.content.isNsfw) return 'NSFW';
    return null;
  }

  bool get _statusIsError => widget.content.status == 'parse_failed';
}

class _CardMeta extends StatelessWidget {
  const _CardMeta({required this.content});
  final ShareCard content;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final date = content.publishedAt ?? content.createdAt;
    final author = content.authorName?.trim() ?? '';
    final hasWebSource = [
      'http',
      'https',
    ].contains(Uri.tryParse(content.url)?.scheme);
    final source = switch (content.platform.toLowerCase()) {
      'universal' => '网页',
      'bilibili' => 'Bilibili',
      'zhihu' => '知乎',
      'xiaohongshu' => '小红书',
      'weibo' => '微博',
      'telegram' => 'Telegram',
      _ => content.platform,
    };
    final platform = hasWebSource || content.platform == 'telegram'
        ? source
        : '';
    final avatarAsset = content.mediaAssets.firstFor(
      role: MediaRole.avatar,
      type: MediaType.image,
    );
    final avatarSources = avatarAsset?.sources ?? const <MediaSource>[];
    final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
    return SizedBox(
      height: 32 * scale,
      child: Row(
        children: [
          if (avatarSources.isNotEmpty) ...[
            ExcludeSemantics(
              child: ClipOval(
                child: NetworkThumbnail(
                  imageUrl: avatarSources.first.url,
                  fallbackUrls: avatarSources
                      .skip(1)
                      .map((s) => s.url)
                      .toList(),
                  mediaAsset: avatarAsset,
                  purpose: MediaPurpose.card,
                  width: 28,
                  height: 28,
                  maxWidthDiskCache: 96,
                  maxHeightDiskCache: 96,
                  errorIcon: Icons.person_outline_rounded,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
          ],
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  author.isNotEmpty ? author : platform,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.2,
                  ),
                ),
                if (author.isNotEmpty && platform.isNotEmpty)
                  Text(
                    platform,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.2,
                    ),
                  ),
              ],
            ),
          ),
          if (date != null) ...[
            const SizedBox(width: AppSpacing.xs),
            Text(
              DateFormat('MM-dd').format(date.toLocal()),
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.isError});

  final String label;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final background = isError
        ? scheme.errorContainer
        : scheme.surfaceContainerHighest;
    final foreground = isError
        ? scheme.onErrorContainer
        : scheme.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppShape.pill),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(color: foreground),
      ),
    );
  }
}
