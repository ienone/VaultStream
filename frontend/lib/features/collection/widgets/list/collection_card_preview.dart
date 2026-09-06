import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/widgets/network_thumbnail.dart';
import '../../../../core/widgets/platform_badge.dart';
import '../../../../theme/design_tokens.dart';
import '../../models/content.dart';
import '../../models/content_template.dart';
import '../../../../core/media/media_asset.dart';

String contentSharedTransitionTag(int contentId) =>
    'collection-content-$contentId';

/// 卡片与详情之间唯一允许使用的共享容器。
///
/// 每个内容 ID 只有一个 tag；详情正文和媒体不会复用该 tag。系统开启
/// “减少动态效果”时直接禁用 Hero，路由仍使用普通不透明页面。
class ContentSharedTransition extends StatelessWidget {
  const ContentSharedTransition({
    super.key,
    required this.contentId,
    required this.child,
    this.immersiveMedia = false,
  });

  final int contentId;
  final Widget child;
  final bool immersiveMedia;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return Hero(
      tag: contentSharedTransitionTag(contentId),
      transitionOnUserGestures: true,
      createRectTween: (begin, end) => RectTween(begin: begin, end: end),
      placeholderBuilder: (context, size, child) =>
          SizedBox.fromSize(size: size),
      flightShuttleBuilder:
          (flightContext, animation, direction, fromContext, toContext) {
            final fromHero = fromContext.widget as Hero;
            final toHero = toContext.widget as Hero;
            return AnimatedBuilder(
              animation: animation,
              builder: (context, _) {
                final progress = direction == HeroFlightDirection.push
                    ? animation.value
                    : 1 - animation.value;
                final destinationOpacity = Interval(
                  immersiveMedia ? 0.5 : 0.32,
                  immersiveMedia ? 0.9 : 0.72,
                  curve: AppMotion.standardCurve,
                ).transform(progress.clamp(0, 1));
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    Opacity(
                      opacity: 1 - destinationOpacity,
                      child: fromHero.child,
                    ),
                    Opacity(opacity: destinationOpacity, child: toHero.child),
                  ],
                );
              },
            );
          },
      child: child,
    );
  }
}

/// 收藏卡片。
///
/// 信息层级固定为三层，所有模板共用同一套来源与状态语义：
/// 1. 来源、类型与时间
/// 2. 标题与实际缩略图（没有封面时不占位）
/// 3. 必要处理状态；语义搜索有原文片段时直接显示片段
///
/// 命中原文片段只在语义搜索结果中出现（`hasSemanticMatch` 仅由
/// `/search/semantic` 的响应填充），普通浏览不会永久占位。
class CollectionCardPreview extends StatelessWidget {
  const CollectionCardPreview({
    super.key,
    required this.content,
    this.onTap,
    this.isHovered = false,
    this.isTinyCardOverride,
    this.isList = false,
  });

  final ShareCard content;
  final VoidCallback? onTap;
  final bool isHovered;
  final bool isList;

  /// 强制紧凑模式。为 null 时由卡片自身可用宽度决定。
  final bool? isTinyCardOverride;

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
    final avatarAsset = content.mediaAssets.firstFor(
      role: MediaRole.avatar,
      type: MediaType.image,
    );
    final avatarUrl = avatarAsset?.sources.firstOrNull?.url ?? '';

    return LayoutBuilder(
      builder: (context, constraints) {
        final tiny =
            isTinyCardOverride ??
            (constraints.hasBoundedWidth && constraints.maxWidth < 200);

        final surface = ContentSharedTransition(
          contentId: content.id,
          immersiveMedia: content.usesImmersiveMediaTransition,
          child: _CardSurface(
            content: content,
            imageUrl: imageUrl,
            imageFallbackUrls: imageFallbackUrls,
            mediaAsset: representativeAsset,
            mediaAssets: representativeAssets,
            avatarUrl: avatarUrl,
            avatarAsset: avatarAsset,
            isTiny: tiny,
            isList: isList,
            isHovered: isHovered,
          ),
        );

        if (onTap == null) return surface;

        return Material(
          color: Colors.transparent,
          borderRadius: AppShape.cardBorder,
          clipBehavior: Clip.antiAlias,
          child: InkWell(onTap: onTap, child: surface),
        );
      },
    );
  }
}

class _CardSurface extends StatelessWidget {
  const _CardSurface({
    required this.content,
    required this.imageUrl,
    required this.imageFallbackUrls,
    required this.mediaAsset,
    required this.mediaAssets,
    required this.avatarUrl,
    required this.avatarAsset,
    required this.isTiny,
    required this.isHovered,
    required this.isList,
  });

  final ShareCard content;
  final String imageUrl;
  final List<String> imageFallbackUrls;
  final MediaAsset? mediaAsset;
  final List<MediaAsset> mediaAssets;
  final String avatarUrl;
  final MediaAsset? avatarAsset;
  final bool isTiny;
  final bool isHovered;
  final bool isList;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final metadata = _CardMeta(
      content: content,
      avatarUrl: avatarUrl,
      avatarAsset: avatarAsset,
    );
    final text = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        metadata,
        const SizedBox(height: AppSpacing.xxs),
        Text(
          _displayTitle,
          maxLines: isList ? 3 : 4,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium,
        ),
        if (_statusLabel != null) ...[
          const SizedBox(height: AppSpacing.xs),
          _StatusChip(label: _statusLabel!, isError: _statusIsError),
        ],
        if (content.hasSemanticMatch &&
            !isTiny &&
            content.semanticSourceText?.trim().isNotEmpty == true) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            content.semanticSourceText!.trim(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
    final media = imageUrl.isEmpty
        ? null
        : ClipRRect(
            borderRadius: AppShape.cardMediaBorder,
            child: NetworkThumbnail(
              imageUrl: imageUrl,
              fallbackUrls: imageFallbackUrls,
              mediaAsset: mediaAsset,
              mediaAssets: mediaAssets,
              purpose: MediaPurpose.card,
              fit: BoxFit.cover,
              maxHeightDiskCache: 800,
              errorIcon: Icons.broken_image_rounded,
            ),
          );
    return AnimatedContainer(
      duration: AppMotion.stateChange,
      curve: AppMotion.standardCurve,
      decoration: BoxDecoration(
        borderRadius: AppShape.cardBorder,
        color: isHovered
            ? scheme.surfaceContainerHigh
            : isList
            ? scheme.surface
            : scheme.surfaceContainerLow,
      ),
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: text),
          if (media != null) ...[
            const SizedBox(width: AppSpacing.sm),
            SizedBox.square(dimension: 88, child: media),
          ],
        ],
      ),
    );
  }

  bool get _hasTitle {
    final title = content.title?.trim() ?? '';
    return title.isNotEmpty && title != '-';
  }

  String get _displayTitle => _hasTitle ? content.title!.trim() : '无标题';

  /// 只暴露对用户有行动价值的状态。
  String? get _statusLabel {
    if (content.status == 'parse_failed') return '解析失败';
    if (content.status == 'processing') return '解析中';
    if (content.status == 'unprocessed') return '待解析';
    if (content.isNsfw) return 'NSFW';
    return null;
  }

  bool get _statusIsError => content.status == 'parse_failed';
}

class _CardMeta extends StatelessWidget {
  const _CardMeta({
    required this.content,
    required this.avatarUrl,
    required this.avatarAsset,
  });

  final ShareCard content;
  final String avatarUrl;
  final MediaAsset? avatarAsset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final date = content.publishedAt ?? content.createdAt;
    final author = content.authorName?.trim() ?? '';

    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xxs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          content.template.label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        if (['http', 'https'].contains(Uri.tryParse(content.url)?.scheme))
          PlatformBadge(platform: content.platform),
        if (avatarUrl.isNotEmpty)
          SizedBox.square(
            dimension: 20,
            child: ClipOval(
              child: NetworkThumbnail(
                imageUrl: avatarUrl,
                mediaAsset: avatarAsset,
                purpose: MediaPurpose.card,
                fit: BoxFit.cover,
                maxHeightDiskCache: 96,
                errorIcon: Icons.person_rounded,
              ),
            ),
          ),
        if (author.isNotEmpty)
          Text(
            author,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        if (date != null)
          Text(
            DateFormat('MM-dd').format(date.toLocal()),
            style: theme.textTheme.labelSmall?.copyWith(color: scheme.outline),
          ),
      ],
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
