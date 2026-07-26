import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/image_headers.dart';
import '../../../../core/utils/media_utils.dart' as media_utils;
import '../../../../core/widgets/network_thumbnail.dart';
import '../../../../core/widgets/platform_badge.dart';
import '../../../../theme/design_tokens.dart';
import '../../models/content.dart';
import '../../models/content_template.dart';
import '../../utils/content_parser.dart';

/// 卡片渲染模式。
///
/// - [grid]：收藏库网格中的可选择对象。
/// - [detailLoading]：详情页加载态占位，保持卡片到详情的视觉连续性。
///   这是静态渲染，不响应 hover，但作为唯一共享容器目标。
enum CollectionCardPreviewMode { grid, detailLoading }

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
  });

  final int contentId;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return Hero(
      tag: contentSharedTransitionTag(contentId),
      transitionOnUserGestures: true,
      createRectTween: (begin, end) =>
          MaterialRectArcTween(begin: begin, end: end),
      child: child,
    );
  }
}

/// 收藏卡片。
///
/// 信息层级固定为三层，所有模板共用同一套来源与状态语义：
/// 1. 代表媒体 / 内容类型 + 标题
/// 2. 来源平台、作者、时间
/// 3. 至多一条状态（解析失败、解析中、NSFW）
///
/// 语义命中原因只在语义搜索结果中出现（`hasSemanticMatch` 仅由
/// `/search/semantic` 的响应填充），普通浏览不会永久占位。
class CollectionCardPreview extends ConsumerWidget {
  const CollectionCardPreview({
    super.key,
    required this.content,
    this.onTap,
    this.isHovered = false,
    this.isTinyCardOverride,
    this.mode = CollectionCardPreviewMode.grid,
  });

  final ShareCard content;
  final VoidCallback? onTap;
  final bool isHovered;

  /// 强制紧凑模式。为 null 时由卡片自身可用宽度决定。
  final bool? isTinyCardOverride;
  final CollectionCardPreviewMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dio = ref.watch(apiClientProvider);
    final apiBaseUrl = dio.options.baseUrl;
    final apiToken = dio.options.headers['X-API-Token']?.toString();
    final rawThumbnailUrl = content.thumbnailUrl?.trim() ?? '';
    final imageUrl = rawThumbnailUrl.isNotEmpty
        ? media_utils.mapUrl(rawThumbnailUrl, apiBaseUrl)
        : ContentParser.getDisplayImageUrl(content, apiBaseUrl);
    final rawAvatarUrl = content.authorAvatarUrl?.trim() ?? '';
    final avatarUrl = rawAvatarUrl.isEmpty
        ? ''
        : media_utils.mapUrl(rawAvatarUrl, apiBaseUrl);

    return LayoutBuilder(
      builder: (context, constraints) {
        final tiny =
            isTinyCardOverride ??
            (constraints.hasBoundedWidth && constraints.maxWidth < 200);

        final surface = ContentSharedTransition(
          contentId: content.id,
          child: _CardSurface(
            content: content,
            imageUrl: imageUrl,
            imageHeaders:
                buildImageHeaders(
                  imageUrl: imageUrl,
                  baseUrl: apiBaseUrl,
                  apiToken: apiToken,
                ) ??
                const <String, String>{},
            avatarUrl: avatarUrl,
            avatarHeaders:
                buildImageHeaders(
                  imageUrl: avatarUrl,
                  baseUrl: apiBaseUrl,
                  apiToken: apiToken,
                ) ??
                const <String, String>{},
            isTiny: tiny,
            isHovered: isHovered && mode == CollectionCardPreviewMode.grid,
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
    required this.imageHeaders,
    required this.avatarUrl,
    required this.avatarHeaders,
    required this.isTiny,
    required this.isHovered,
  });

  final ShareCard content;
  final String imageUrl;
  final Map<String, String> imageHeaders;
  final String avatarUrl;
  final Map<String, String> avatarHeaders;
  final bool isTiny;
  final bool isHovered;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    // hover 只改变 tonal surface，不做缩放、不加阴影、不做周期动画。
    return AnimatedContainer(
      duration: AppMotion.stateChange,
      curve: AppMotion.standardCurve,
      decoration: BoxDecoration(
        borderRadius: AppShape.cardBorder,
        color: isHovered
            ? scheme.surfaceContainerHigh
            : scheme.surfaceContainerLow,
        border: Border.all(
          color: isHovered ? scheme.outline : scheme.outlineVariant,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Hero 飞行过程中宽度可能先于高度增长。媒体区若只按宽度维持
          // 宽高比，会在这种中间尺寸下把下方信息挤出容器；Flexible 让
          // 它在高度受限时先收缩，同时保持普通网格中的自然比例。
          Flexible(
            flex: 2,
            child: _CardMedia(
              content: content,
              imageUrl: imageUrl,
              imageHeaders: imageHeaders,
              avatarUrl: avatarUrl,
              avatarHeaders: avatarHeaders,
            ),
          ),
          // 文本区吸收剩余高度，标题在空间不足时省略，
          // 这样文本缩放和长标题都不会撑破网格节奏。
          Expanded(
            flex: 2,
            child: Padding(
              padding: EdgeInsets.all(isTiny ? AppSpacing.xs : AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 第一层：标题
                  Expanded(
                    child: Text(
                      _displayTitle,
                      maxLines: isTiny ? 2 : 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                        color: _hasTitle
                            ? scheme.onSurface
                            : scheme.onSurfaceVariant,
                        fontStyle: _hasTitle ? null : FontStyle.italic,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  // 第二层：来源、作者、时间
                  _CardMeta(content: content, isTiny: isTiny),
                  if (!isTiny &&
                      _statusLabel == null &&
                      (content.viewCount > 0 || content.likeCount > 0)) ...[
                    const SizedBox(height: AppSpacing.xxs),
                    _OptionalStats(content: content),
                  ],
                  // 第三层：至多一条状态
                  if (_statusLabel != null) ...[
                    const SizedBox(height: AppSpacing.xxs),
                    _StatusChip(label: _statusLabel!, isError: _statusIsError),
                  ],
                  if (content.hasSemanticMatch && !isTiny) ...[
                    const SizedBox(height: AppSpacing.xxs),
                    _SemanticMatchLine(content: content),
                  ],
                ],
              ),
            ),
          ),
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

/// 卡片媒体区。没有封面时用内容类型图标占位，而不是留空。
class _CardMedia extends StatelessWidget {
  const _CardMedia({
    required this.content,
    required this.imageUrl,
    required this.imageHeaders,
    required this.avatarUrl,
    required this.avatarHeaders,
  });

  final ShareCard content;
  final String imageUrl;
  final Map<String, String> imageHeaders;
  final String avatarUrl;
  final Map<String, String> avatarHeaders;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final template = content.template;

    if (template == ContentTemplate.profile ||
        template == ContentTemplate.shortPost) {
      return _IdentityMedia(
        template: template,
        avatarUrl: avatarUrl,
        avatarHeaders: avatarHeaders,
      );
    }

    if (template == ContentTemplate.audio) {
      return _AudioMedia(imageUrl: imageUrl, imageHeaders: imageHeaders);
    }

    if (imageUrl.isEmpty) {
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: ColoredBox(
          key: ValueKey('collection-card-template-${template.name}'),
          color: scheme.surfaceContainerHighest,
          child: Stack(
            children: [
              Center(
                child: Icon(
                  _templateIcon(template),
                  size: 28,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              Positioned(
                left: AppSpacing.xs,
                bottom: AppSpacing.xs,
                child: _TypeBadge(template: template),
              ),
            ],
          ),
        ),
      );
    }

    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Stack(
        key: ValueKey('collection-card-template-${template.name}'),
        fit: StackFit.expand,
        children: [
          NetworkThumbnail(
            imageUrl: imageUrl,
            httpHeaders: imageHeaders,
            fit: BoxFit.cover,
            maxHeightDiskCache: 800,
            errorIcon: Icons.broken_image_rounded,
          ),
          Positioned(
            left: AppSpacing.xs,
            bottom: AppSpacing.xs,
            child: _TypeBadge(template: template),
          ),
        ],
      ),
    );
  }
}

class _IdentityMedia extends StatelessWidget {
  const _IdentityMedia({
    required this.template,
    required this.avatarUrl,
    required this.avatarHeaders,
  });

  final ContentTemplate template;
  final String avatarUrl;
  final Map<String, String> avatarHeaders;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ColoredBox(
      key: ValueKey('collection-card-template-${template.name}'),
      color: scheme.secondaryContainer,
      child: Stack(
        children: [
          Center(
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.surfaceContainerHighest,
                border: Border.all(color: scheme.outlineVariant),
              ),
              clipBehavior: Clip.antiAlias,
              child: avatarUrl.isEmpty
                  ? Icon(
                      Icons.person_rounded,
                      key: const ValueKey('collection-card-avatar-placeholder'),
                      size: 34,
                      color: scheme.onSurfaceVariant,
                    )
                  : NetworkThumbnail(
                      imageUrl: avatarUrl,
                      httpHeaders: avatarHeaders,
                      fit: BoxFit.cover,
                      maxHeightDiskCache: 256,
                      errorIcon: Icons.person_rounded,
                    ),
            ),
          ),
          Positioned(
            left: AppSpacing.xs,
            bottom: AppSpacing.xs,
            child: _TypeBadge(template: template),
          ),
        ],
      ),
    );
  }
}

class _AudioMedia extends StatelessWidget {
  const _AudioMedia({required this.imageUrl, required this.imageHeaders});

  final String imageUrl;
  final Map<String, String> imageHeaders;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ColoredBox(
      key: const ValueKey('collection-card-template-audio'),
      color: scheme.tertiaryContainer,
      child: Stack(
        children: [
          Center(
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: AppShape.cardMediaBorder,
              ),
              clipBehavior: Clip.antiAlias,
              child: imageUrl.isEmpty
                  ? Icon(
                      Icons.podcasts_rounded,
                      size: 36,
                      color: scheme.onTertiaryContainer,
                    )
                  : NetworkThumbnail(
                      imageUrl: imageUrl,
                      httpHeaders: imageHeaders,
                      fit: BoxFit.cover,
                      maxHeightDiskCache: 256,
                      errorIcon: Icons.podcasts_rounded,
                    ),
            ),
          ),
          const Positioned(
            left: AppSpacing.xs,
            bottom: AppSpacing.xs,
            child: _TypeBadge(template: ContentTemplate.audio),
          ),
        ],
      ),
    );
  }
}

IconData _templateIcon(ContentTemplate template) => switch (template) {
  ContentTemplate.article => Icons.article_outlined,
  ContentTemplate.imageNote => Icons.auto_stories_outlined,
  ContentTemplate.shortPost => Icons.chat_bubble_outline_rounded,
  ContentTemplate.gallery => Icons.photo_library_outlined,
  ContentTemplate.video => Icons.smart_display_outlined,
  ContentTemplate.audio => Icons.podcasts_rounded,
  ContentTemplate.collectionIndex => Icons.list_alt_rounded,
  ContentTemplate.profile => Icons.person_outline_rounded,
  ContentTemplate.bookmark => Icons.bookmark_border_rounded,
};

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.template});

  final ContentTemplate template;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.scrim.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(AppShape.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_templateIcon(template), size: 12, color: Colors.white),
          const SizedBox(width: AppSpacing.xxs),
          Text(
            template.label,
            style: theme.textTheme.labelSmall?.copyWith(color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _CardMeta extends StatelessWidget {
  const _CardMeta({required this.content, required this.isTiny});

  final ShareCard content;
  final bool isTiny;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final date = content.publishedAt ?? content.createdAt;
    final author = content.authorName?.trim() ?? '';

    return Row(
      children: [
        PlatformBadge(platform: content.platform),
        const SizedBox(width: AppSpacing.xs),
        if (author.isNotEmpty) ...[
          Expanded(
            child: Text(
              author,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ] else
          const Spacer(),
        if (!isTiny && date != null) ...[
          const SizedBox(width: AppSpacing.xxs),
          Text(
            DateFormat('MM-dd').format(date.toLocal()),
            style: theme.textTheme.labelSmall?.copyWith(color: scheme.outline),
          ),
        ],
      ],
    );
  }
}

class _OptionalStats extends StatelessWidget {
  const _OptionalStats({required this.content});

  final ShareCard content;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final stats = <({IconData icon, String value})>[
      if (content.viewCount > 0)
        (
          icon: Icons.visibility_outlined,
          value: ContentParser.formatCount(content.viewCount),
        ),
      if (content.likeCount > 0)
        (
          icon: Icons.favorite_border_rounded,
          value: ContentParser.formatCount(content.likeCount),
        ),
    ];

    return Row(
      key: const ValueKey('collection-card-optional-stats'),
      children: [
        for (var index = 0; index < stats.length; index++) ...[
          if (index > 0) const SizedBox(width: AppSpacing.sm),
          Icon(stats[index].icon, size: 13, color: scheme.outline),
          const SizedBox(width: AppSpacing.xxs),
          Text(
            stats[index].value,
            style: theme.textTheme.labelSmall?.copyWith(color: scheme.outline),
          ),
        ],
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

/// 语义命中说明。只在语义搜索结果中出现。
class _SemanticMatchLine extends StatelessWidget {
  const _SemanticMatchLine({required this.content});

  final ShareCard content;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final source = switch (content.semanticMatchSource) {
      'hybrid' => '混合命中',
      'vector' => '语义命中',
      'fts' => '关键词命中',
      _ => '检索命中',
    };
    final chunk = content.semanticChunkTitle?.trim();
    final score = content.semanticScore;

    return Tooltip(
      message: [
        if (chunk != null && chunk.isNotEmpty) chunk,
        if (content.semanticSourceText?.trim().isNotEmpty == true)
          content.semanticSourceText!.trim(),
      ].join('\n\n'),
      child: Row(
        children: [
          Icon(Icons.search_rounded, size: 12, color: scheme.tertiary),
          const SizedBox(width: AppSpacing.xxs),
          Expanded(
            child: Text(
              score == null ? source : '$source ${score.toStringAsFixed(2)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.tertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
