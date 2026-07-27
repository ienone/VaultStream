import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/layout/responsive_layout.dart';
import '../../../../core/network/image_headers.dart';
import '../../../../core/utils/media_utils.dart' as media_utils;
import '../../../../core/utils/safe_url_launcher.dart';
import '../../../../core/widgets/network_thumbnail.dart';
import '../../../../theme/design_tokens.dart';
import '../../models/content.dart';
import '../../models/content_template.dart';
import '../../models/media_asset.dart';
import '../../utils/content_parser.dart';
import '../common/video_player_widget.dart';
import '../renderers/context_card_renderer.dart';
import '../renderers/payload_block_renderer.dart';
import 'components/media_grid.dart';
import 'components/rich_content.dart';
import 'components/tags_section.dart';
import 'components/unified_stats.dart';
import 'detail_sections.dart';

/// 模板渲染所需的上下文。
class TemplateContext {
  const TemplateContext({
    required this.detail,
    required this.metrics,
    required this.apiBaseUrl,
    required this.apiToken,
    required this.headerKeys,
    required this.images,
    required this.imageFallbacks,
    required this.onImageTap,
    required this.onReParse,
  });

  final ContentDetail detail;
  final WindowMetrics metrics;
  final String apiBaseUrl;
  final String? apiToken;
  final Map<String, GlobalKey> headerKeys;

  /// 已解析并映射为可访问 URL 的图片列表。
  final List<String> images;
  final Map<String, List<String>> imageFallbacks;
  final void Function(int index) onImageTap;
  final VoidCallback onReParse;

  bool get isCompact => metrics.isCompact;
}

/// 模板主体分发。
///
/// 详情页只有这一个模板入口，不存在第二套并行详情实现。
class ContentTemplateBody extends StatelessWidget {
  const ContentTemplateBody({super.key, required this.context_});

  final TemplateContext context_;

  @override
  Widget build(BuildContext context) {
    return switch (context_.detail.template) {
      ContentTemplate.article => _ArticleBody(ctx: context_),
      ContentTemplate.imageNote => _ImageNoteBody(ctx: context_),
      ContentTemplate.shortPost => _ShortPostBody(ctx: context_),
      ContentTemplate.gallery => _GalleryBody(ctx: context_),
      ContentTemplate.video => _VideoBody(ctx: context_),
      ContentTemplate.audio => _AudioBody(ctx: context_),
      ContentTemplate.collectionIndex => _CollectionIndexBody(ctx: context_),
      ContentTemplate.profile => _ProfileBody(ctx: context_),
      ContentTemplate.bookmark => _BookmarkBody(ctx: context_),
    };
  }
}

// --- 共享片段 ---

/// 正文。缺失时给出与模板相符的空状态，不用摘要顶替原文。
class _BodyText extends StatelessWidget {
  const _BodyText({
    required this.ctx,
    this.emptyMessage,
    this.hideMedia = true,
  });

  final TemplateContext ctx;
  final String? emptyMessage;
  final bool hideMedia;

  @override
  Widget build(BuildContext context) {
    final detail = ctx.detail;
    if (!detail.hasBody) {
      if (detail.isParseFailed || detail.isParsePending) {
        // 解析横幅已经解释了原因，这里不重复报错。
        return const SizedBox.shrink();
      }
      return ContentEmptyState(
        icon: Icons.notes_rounded,
        message: emptyMessage ?? '这条内容没有正文',
        hint: detail.hasSummary ? '下方的 AI 摘要是生成结果，不是原文。' : null,
      );
    }

    return RichContent(
      detail: detail,
      apiBaseUrl: ctx.apiBaseUrl,
      apiToken: ctx.apiToken,
      headerKeys: ctx.headerKeys,
      useHero: false,
      hideMedia: hideMedia,
    );
  }
}

/// 媒体网格。空态说明"没有媒体"而不是留白。
class _MediaBlock extends StatelessWidget {
  const _MediaBlock({required this.ctx, this.emptyMessage});

  final TemplateContext ctx;
  final String? emptyMessage;

  @override
  Widget build(BuildContext context) {
    if (ctx.images.isEmpty) {
      return ContentEmptyState(
        icon: Icons.image_not_supported_outlined,
        message: emptyMessage ?? '没有归档的图片',
        hint: '媒体可能未被抓取，或按归档策略被跳过。',
      );
    }

    return MediaGrid(
      images: ctx.images,
      fallbackUrlsByImage: ctx.imageFallbacks,
      apiBaseUrl: ctx.apiBaseUrl,
      apiToken: ctx.apiToken,
      contentId: ctx.detail.id,
      onImageTap: ctx.onImageTap,
      isLandscape: false,
    );
  }
}

/// 封面。用于视频与音频模板——多数平台只归档了封面。
class _CoverBlock extends StatelessWidget {
  const _CoverBlock({required this.ctx, this.aspectRatio = 16 / 9});

  final TemplateContext ctx;
  final double aspectRatio;

  @override
  Widget build(BuildContext context) {
    final coverAsset =
        ctx.detail.mediaAssets.firstFor(
          role: MediaRole.cover,
          type: MediaType.image,
        ) ??
        ctx.detail.mediaAssets.firstFor(
          role: MediaRole.poster,
          type: MediaType.image,
        );
    final candidates = coverAsset?.sources
        .map((source) => source.url)
        .toList(growable: false);
    final legacyCover = ctx.detail.coverUrl;
    final cover =
        candidates?.firstOrNull ??
        (legacyCover == null || legacyCover.isEmpty
            ? null
            : media_utils.mapUrl(legacyCover, ctx.apiBaseUrl));
    if (cover == null) {
      return ContentEmptyState(
        icon: Icons.hide_image_outlined,
        message: '没有封面',
      );
    }
    return ClipRRect(
      borderRadius: AppShape.paneBorder,
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: NetworkThumbnail(
          imageUrl: cover,
          fallbackUrls: candidates?.skip(1).toList(growable: false) ?? const [],
          httpHeaders: candidates == null
              ? buildImageHeaders(
                  imageUrl: cover,
                  baseUrl: ctx.apiBaseUrl,
                  apiToken: ctx.apiToken,
                )
              : null,
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}

/// 从 media_urls 中挑出可播放的媒体。没有则返回 null。
List<String> _playableMedia(TemplateContext ctx, {required bool audio}) {
  final type = audio ? MediaType.audio : MediaType.video;
  for (final asset in ctx.detail.mediaAssets) {
    if (asset.mediaType == type && asset.sources.isNotEmpty) {
      return asset.sources.map((source) => source.url).toList(growable: false);
    }
  }
  for (final url in ctx.detail.mediaUrls) {
    final matches = audio ? media_utils.isAudio(url) : media_utils.isVideo(url);
    if (matches) {
      return [media_utils.mapPlayableUrl(url, ctx.apiBaseUrl)];
    }
  }
  return const [];
}

// --- 模板主体 ---

/// 文章：连续阅读为主，正文限宽。
class _ArticleBody extends StatelessWidget {
  const _ArticleBody({required this.ctx});

  final TemplateContext ctx;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ContextCardRenderer(content: ctx.detail),
        _BodyText(ctx: ctx, hideMedia: false),
        if (ctx.images.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xl),
          const DetailSectionHeader(title: '文内媒体'),
          _MediaBlock(ctx: ctx),
        ],
      ],
    );
  }
}

/// 图文笔记：文字与图片交错，两者的对应关系是主体。
class _ImageNoteBody extends StatelessWidget {
  const _ImageNoteBody({required this.ctx});

  final TemplateContext ctx;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ContextCardRenderer(content: ctx.detail),
        _MediaBlock(ctx: ctx, emptyMessage: '这条笔记没有归档图片'),
        const SizedBox(height: AppSpacing.lg),
        _BodyText(ctx: ctx, emptyMessage: '这条笔记没有文字说明'),
      ],
    );
  }
}

/// 短帖子：紧凑，作者与来源是重点，不套用长文排版。
class _ShortPostBody extends StatelessWidget {
  const _ShortPostBody({required this.ctx});

  final TemplateContext ctx;

  @override
  Widget build(BuildContext context) {
    final quoted = ctx.detail.richPayload?['quoted_content'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ContextCardRenderer(content: ctx.detail),
        _BodyText(ctx: ctx, emptyMessage: '这条帖子没有文字内容'),
        if (quoted != null) ...[
          const SizedBox(height: AppSpacing.md),
          _QuotedContent(raw: quoted),
        ],
        if (ctx.images.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          _MediaBlock(ctx: ctx),
        ],
      ],
    );
  }
}

/// 引用/转发内容。保留转发者与原内容的边界。
class _QuotedContent extends StatelessWidget {
  const _QuotedContent({required this.raw});

  final Object raw;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = _formatQuotedContent(raw);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: AppShape.paneBorder,
        border: Border(left: BorderSide(color: scheme.outline, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '引用内容',
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          SelectableText(text, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }

  String _formatQuotedContent(Object? value) {
    if (value is String) return value;
    if (value is Map) {
      final author =
          value['author_name'] ?? value['author'] ?? value['username'];
      final body =
          value['text'] ?? value['body'] ?? value['content'] ?? value['title'];
      final url = value['url'];
      final parts = <String>[
        if (author != null && author.toString().trim().isNotEmpty)
          author.toString().trim(),
        if (body != null && body.toString().trim().isNotEmpty)
          body.toString().trim(),
        if (url != null && url.toString().trim().isNotEmpty)
          url.toString().trim(),
      ];
      if (parts.isNotEmpty) return parts.join('\n\n');
      return const JsonEncoder.withIndent('  ').convert(value);
    }
    if (value is List) {
      return value.map((item) => _formatQuotedContent(item)).join('\n\n');
    }
    return value?.toString() ?? '';
  }
}

/// 图集：媒体本身是主体，文字是补充。
class _GalleryBody extends StatelessWidget {
  const _GalleryBody({required this.ctx});

  final TemplateContext ctx;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _MediaBlock(ctx: ctx, emptyMessage: '这个图集没有可显示的图片'),
        if (ctx.detail.hasBody) ...[
          const SizedBox(height: AppSpacing.lg),
          const DetailSectionHeader(title: '说明'),
          _BodyText(ctx: ctx),
        ],
      ],
    );
  }
}

/// 视频。
///
/// 当前多数平台适配器只归档封面和元数据，不保存原视频，
/// 因此必须显式表达"没有本地视频"，并提供回到来源的入口。
class _VideoBody extends StatelessWidget {
  const _VideoBody({required this.ctx});

  final TemplateContext ctx;

  @override
  Widget build(BuildContext context) {
    final playable = _playableMedia(ctx, audio: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (playable.isNotEmpty)
          ClipRRect(
            borderRadius: AppShape.paneBorder,
            child: VideoPlayerWidget(
              videoUrl: playable.first,
              fallbackUrls: playable.skip(1).toList(growable: false),
              headers: buildImageHeaders(
                imageUrl: playable.first,
                baseUrl: ctx.apiBaseUrl,
                apiToken: ctx.apiToken,
              ),
            ),
          )
        else ...[
          _CoverBlock(ctx: ctx),
          const SizedBox(height: AppSpacing.sm),
          ContentEmptyState(
            icon: Icons.smart_display_outlined,
            message: '没有归档视频文件',
            hint: '该来源只保存了封面与元数据。',
            action: FilledButton.tonalIcon(
              onPressed: () =>
                  SafeUrlLauncher.openExternal(context, ctx.detail.url),
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: const Text('到来源观看'),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        const DetailSectionHeader(title: '简介'),
        _BodyText(ctx: ctx, emptyMessage: '这个视频没有简介'),
      ],
    );
  }
}

/// 音频与播客。
///
/// 全局播放会话不在本切片范围内，这里只提供详情内播放与来源入口。
class _AudioBody extends StatelessWidget {
  const _AudioBody({required this.ctx});

  final TemplateContext ctx;

  @override
  Widget build(BuildContext context) {
    final playable = _playableMedia(ctx, audio: true);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: ctx.isCompact ? 120 : 160,
              child: _CoverBlock(ctx: ctx, aspectRatio: 1),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ContentTitleBlock(
                    detail: ctx.detail,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  ContentSourceLine(detail: ctx.detail, compact: true),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        if (playable.isNotEmpty)
          VideoPlayerWidget(
            videoUrl: playable.first,
            fallbackUrls: playable.skip(1).toList(growable: false),
            audioOnly: true,
            headers: buildImageHeaders(
              imageUrl: playable.first,
              baseUrl: ctx.apiBaseUrl,
              apiToken: ctx.apiToken,
            ),
          )
        else
          ContentEmptyState(
            icon: Icons.music_off_outlined,
            message: '没有归档音频文件',
            hint: '该来源只保存了封面与元数据。',
            action: FilledButton.tonalIcon(
              onPressed: () =>
                  SafeUrlLauncher.openExternal(context, ctx.detail.url),
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: const Text('到来源收听'),
            ),
          ),
        const SizedBox(height: AppSpacing.lg),
        const DetailSectionHeader(title: 'Show Notes'),
        _BodyText(ctx: ctx, emptyMessage: '这条音频没有文字说明'),
      ],
    );
  }
}

/// 聚合页：知乎问题、收藏夹等，成员条目是主体。
class _CollectionIndexBody extends StatelessWidget {
  const _CollectionIndexBody({required this.ctx});

  final TemplateContext ctx;

  @override
  Widget build(BuildContext context) {
    final blocks = ctx.detail.richPayload?['blocks'];
    final hasMembers = blocks is List && blocks.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ContextCardRenderer(content: ctx.detail),
        if (ctx.detail.hasBody) ...[
          _BodyText(ctx: ctx),
          const SizedBox(height: AppSpacing.lg),
        ],
        DetailSectionHeader(
          title: '收录条目',
          trailing: hasMembers
              ? Text(
                  '${(blocks).length} 条',
                  style: Theme.of(context).textTheme.labelMedium,
                )
              : null,
        ),
        if (hasMembers)
          PayloadBlockRenderer(content: ctx.detail)
        else
          const ContentEmptyState(
            icon: Icons.list_alt_rounded,
            message: '没有归档的成员条目',
            hint: '来源页可能需要登录，或成员在解析时不可见。',
          ),
      ],
    );
  }
}

/// 平台账号主页。
class _ProfileBody extends StatelessWidget {
  const _ProfileBody({required this.ctx});

  final TemplateContext ctx;

  @override
  Widget build(BuildContext context) {
    final detail = ctx.detail;
    final avatarAsset = detail.mediaAssets.firstFor(
      role: MediaRole.avatar,
      type: MediaType.image,
    );
    final avatarCandidates = avatarAsset?.sources
        .map((source) => source.url)
        .toList(growable: false);
    final legacyAvatar = detail.authorAvatarUrl;
    final avatar =
        avatarCandidates?.firstOrNull ??
        (legacyAvatar == null || legacyAvatar.isEmpty
            ? null
            : media_utils.mapUrl(legacyAvatar, ctx.apiBaseUrl));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (avatar != null && avatar.isNotEmpty)
              ClipOval(
                child: NetworkThumbnail(
                  imageUrl: avatar,
                  fallbackUrls:
                      avatarCandidates?.skip(1).toList(growable: false) ??
                      const [],
                  httpHeaders: avatarCandidates == null
                      ? buildImageHeaders(
                          imageUrl: avatar,
                          baseUrl: ctx.apiBaseUrl,
                          apiToken: ctx.apiToken,
                        )
                      : null,
                  width: 72,
                  height: 72,
                ),
              )
            else
              CircleAvatar(
                radius: 36,
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest,
                child: const Icon(Icons.person_outline_rounded),
              ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ContentTitleBlock(
                    detail: detail,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  UnifiedStats(detail: detail, useContainer: false),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        const DetailSectionHeader(title: '简介'),
        _BodyText(ctx: ctx, emptyMessage: '这个主页没有简介'),
        if (ctx.images.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          const DetailSectionHeader(title: '主页媒体'),
          _MediaBlock(ctx: ctx),
        ],
      ],
    );
  }
}

/// 书签：只记录链接和"为什么保存"，并提供升级解析入口。
class _BookmarkBody extends ConsumerWidget {
  const _BookmarkBody({required this.ctx});

  final TemplateContext ctx;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final detail = ctx.detail;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            borderRadius: AppShape.paneBorder,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '链接',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              SelectableText(
                detail.cleanUrl ?? detail.url,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.xs,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: () =>
                        SafeUrlLauncher.openExternal(context, detail.url),
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: const Text('打开链接'),
                  ),
                  OutlinedButton.icon(
                    onPressed: ctx.onReParse,
                    icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
                    label: const Text('尝试解析正文'),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (detail.hasBody) ...[
          const SizedBox(height: AppSpacing.lg),
          const DetailSectionHeader(title: '保存时的记录'),
          _BodyText(ctx: ctx),
        ],
      ],
    );
  }
}

/// 侧栏 / 底部的次要信息。所有模板共用同一组，顺序稳定。
class ContentSupportingSections extends StatelessWidget {
  const ContentSupportingSections({
    super.key,
    required this.detail,
    required this.processingPanel,
    this.showStats = true,
  });

  final ContentDetail detail;
  final Widget processingPanel;
  final bool showStats;

  @override
  Widget build(BuildContext context) {
    final hasTags = detail.tags.isNotEmpty || detail.sourceTags.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (detail.hasSummary) ...[
          ContentSummaryBlock(detail: detail),
          const SizedBox(height: AppSpacing.md),
        ],
        processingPanel,
        if (showStats) ...[
          const SizedBox(height: AppSpacing.md),
          UnifiedStats(detail: detail, useContainer: false),
        ],
        if (hasTags) ...[
          const SizedBox(height: AppSpacing.md),
          TagsSection(detail: detail),
        ],
      ],
    );
  }
}

/// 目录。仅文章模板在宽屏使用。
class ContentOutline extends StatelessWidget {
  const ContentOutline({
    super.key,
    required this.detail,
    required this.activeHeader,
    required this.headerKeys,
  });

  final ContentDetail detail;
  final String? activeHeader;
  final Map<String, GlobalKey> headerKeys;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final headers = ContentParser.extractHeaders(
      ContentParser.getMarkdownContent(detail),
    );
    if (headers.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const DetailSectionHeader(title: '目录'),
        for (final header in headers)
          InkWell(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            onTap: () {
              final key = headerKeys[header.uniqueId];
              final target = key?.currentContext;
              if (target != null) {
                Scrollable.ensureVisible(
                  target,
                  duration: AppMotion.contentSwap,
                  curve: AppMotion.standardCurve,
                );
              }
            },
            child: Padding(
              padding: EdgeInsets.only(
                left: (header.level - 1) * AppSpacing.sm,
                top: AppSpacing.xxs,
                bottom: AppSpacing.xxs,
              ),
              child: Text(
                header.text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: activeHeader == header.uniqueId
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                  fontWeight: activeHeader == header.uniqueId
                      ? FontWeight.w700
                      : null,
                ),
              ),
            ),
          ),
        const SizedBox(height: AppSpacing.md),
      ],
    );
  }
}
