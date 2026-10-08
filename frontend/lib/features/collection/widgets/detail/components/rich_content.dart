import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:frontend/core/utils/safe_url_launcher.dart';

import '../../../../../theme/design_tokens.dart';
import '../../../models/content.dart';
import '../../../utils/content_parser.dart';
import '../../../../../core/widgets/markdown_reading.dart';
import 'media_gallery_item.dart';

class RichContent extends StatefulWidget {
  final ContentDetail detail;
  final Map<String, GlobalKey> headerKeys;
  final bool useHero;
  final bool hideMedia;
  final Color? contentColor;

  const RichContent({
    super.key,
    required this.detail,
    required this.headerKeys,
    this.useHero = true,
    this.hideMedia = false,
    this.contentColor,
  });

  @override
  State<RichContent> createState() => _RichContentState();
}

class _RichContentState extends State<RichContent> {
  ContentDetail get detail => widget.detail;
  Map<String, GlobalKey> get headerKeys => widget.headerKeys;
  bool get useHero => widget.useHero;
  bool get hideMedia => widget.hideMedia;
  Color? get contentColor => widget.contentColor;
  late MarkdownStyleSheet _style;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _style = readingMarkdownStyle(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mediaUrls = ContentParser.extractAllMedia(detail);
    final mediaFallbacks = ContentParser.extractImageFallbacks(detail);
    final mediaAssetsByImage = {
      for (final asset in detail.mediaAssets)
        if (asset.sources.isNotEmpty) asset.sources.first.url: asset,
    };
    final rawMarkdown = _getMarkdownContent(detail);
    final markdown = _preprocessMarkdown(rawMarkdown);

    final headingOccurrences = <String, int>{};
    final Set<String> usedHeroTags = {};
    final List<Widget> children = [];

    if (markdown.isNotEmpty) {
      final style = _style;
      // 从 Markdown 文本中提取图片标识，只保留能匹配统一媒体资产的条目。
      final inlineImageUrls = ContentParser.extractMarkdownImageUrls(markdown)
          .map(
            (url) =>
                ContentParser.imageCandidatesForUrl(detail, url).firstOrNull,
          )
          .whereType<String>()
          .toList(growable: false);

      children.add(
        _ArticleMarkdownBody(
          key: ObjectKey(detail),
          data: markdown,
          selectable: true,
          // 社交消息的单换行属于原始排版。
          softLineBreak: const [
            'xiaohongshu',
            'telegram',
          ].contains(detail.platform),
          onTapLink: (text, href, title) async {
            await SafeUrlLauncher.openExternal(context, href);
          },
          styleSheet: style,
          builders: {
            for (final entry in <String, TextStyle?>{
              'h1': style.h1,
              'h2': style.h2,
              'h3': style.h3,
              'h4': style.h4,
              'h5': style.h5,
              'h6': style.h6,
            }.entries)
              entry.key: HeaderBuilder(
                headerKeys,
                entry.value,
                headingOccurrences,
              ),
            'code': CodeElementBuilder(context),
          },
          // ignore: deprecated_member_use
          imageBuilder: (uri, title, alt) => _buildMarkdownImage(
            context,
            detail,
            uri,
            alt,
            galleryImages: inlineImageUrls,
            fallbackUrlsByImage: mediaFallbacks,
            useHero: useHero,
            usedHeroTags: usedHeroTags,
          ),
        ),
      );
    } else {
      if (detail.body != null && detail.body!.isNotEmpty) {
        children.add(
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              borderRadius: AppShape.paneBorder,
            ),
            child: Text(
              detail.body!,
              style: theme.textTheme.bodyLarge?.copyWith(height: 1.6),
            ),
          ),
        );
        children.add(const SizedBox(height: 24));
      }
    }

    bool showMediaGrid = false;
    // Generic media grid logic
    if (detail.layoutType == 'gallery' || detail.layoutType == 'video') {
      showMediaGrid = mediaUrls.isNotEmpty;
    } else {
      // For articles/questions, show media if no markdown body (fallback) or explicitly handled
      // But typically inline images are in markdown.
      // If explicit media_urls exist and not in markdown, we might want to show them?
      // For now, keep simple: if markdown empty, show grid.
      if (markdown.isEmpty && mediaUrls.isNotEmpty) {
        showMediaGrid = true;
      }
    }

    if (showMediaGrid && !hideMedia) {
      if (children.isNotEmpty) children.add(const SizedBox(height: 24));

      if (mediaUrls.length == 1) {
        children.add(
          MediaGalleryItem(
            images: mediaUrls,
            index: 0,
            fallbackUrlsByImage: mediaFallbacks,
            mediaAssetsByImage: mediaAssetsByImage,
            contentId: detail.id,
            contentColor: contentColor,
            heroTag: 'content-image-${detail.id}',
            fit: BoxFit.contain,
          ),
        );
      } else {
        children.add(
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.0,
            ),
            itemCount: mediaUrls.length,
            itemBuilder: (context, index) {
              final String baseTag = index == 0
                  ? 'content-image-${detail.id}'
                  : 'image-$index-${detail.id}';

              // 确保 Hero Tag 在整个 RichContent 树中唯一
              String finalHeroTag = baseTag;
              int suffix = 1;
              while (usedHeroTags.contains(finalHeroTag)) {
                finalHeroTag = '$baseTag-dup$suffix';
                suffix++;
              }
              usedHeroTags.add(finalHeroTag);

              return MediaGalleryItem(
                images: mediaUrls,
                index: index,
                fallbackUrlsByImage: mediaFallbacks,
                mediaAssetsByImage: mediaAssetsByImage,
                contentId: detail.id,
                contentColor: contentColor,
                heroTag: finalHeroTag,
              );
            },
          ),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  String _getMarkdownContent(ContentDetail detail) {
    // 直接使用 body 字段（后端已经在 archive.markdown 中填充）
    return detail.body ?? '';
  }

  static final Map<String, String> _markdownCache = {};

  String _preprocessMarkdown(String markdown) {
    if (markdown.isEmpty) return markdown;

    final cacheKey = markdown.hashCode.toString();
    if (_markdownCache.containsKey(cacheKey)) {
      return _markdownCache[cacheKey]!;
    }

    // 1. 处理 Latex 块: 将 $$ ... $$ 转换为 ```latex ... ```
    var processed = markdown.replaceAllMapped(
      RegExp(r'(?:\n|^)\$\$\s*([\s\S]+?)\s*\$\$(?:\n|$)'),
      (match) => '\n\n```latex\n${match.group(1)!.trim()}\n```\n\n',
    );

    // 2. 处理行内 LaTeX: 使用特殊占位符标记，后续在 builder 中处理
    // 格式: ‹LATEX:base64content›
    processed = processed.replaceAllMapped(
      RegExp(r'(?<![`\d\w])\$([^\$\n]+?)\$(?![`\d\w])'),
      (match) {
        final content = match.group(1)!;
        if (content.contains('\\') ||
            (content.length > 2 && RegExp(r'[=+\-^_{}]').hasMatch(content))) {
          final encoded = Uri.encodeComponent(content);
          return '`‹LATEX:$encoded›`';
        }
        return '\$$content\$';
      },
    );

    // 3. 处理 Latex 环境: 将 \begin{...} ... \end{...} 转换为 ```latex ... ```
    processed = processed.replaceAllMapped(
      RegExp(
        r'(?<!```\n|```latex\n)\\begin\{([a-z*]+)\}([\s\S]+?)\\end\{\1\}',
        caseSensitive: false,
      ),
      (match) =>
          '\n\n```latex\n\\begin{${match.group(1)}}${match.group(2)}\\end{${match.group(1)}}\n```\n\n',
    );

    if (_markdownCache.length > 50) {
      _markdownCache.clear();
    }
    _markdownCache[cacheKey] = processed;

    return processed;
  }

  Widget _buildMarkdownImage(
    BuildContext context,
    ContentDetail detail,
    Uri uri,
    String? alt, {
    List<String>? galleryImages,
    Map<String, List<String>> fallbackUrlsByImage = const {},
    bool useHero = true,
    Set<String>? usedHeroTags,
  }) {
    final candidates = ContentParser.imageCandidatesForUrl(
      detail,
      uri.toString(),
    );
    if (candidates.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Icon(
              Icons.hide_image_outlined,
              size: 20,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            if (alt?.trim().isNotEmpty == true) ...[
              const SizedBox(width: 8),
              Expanded(child: Text(alt!.trim())),
            ],
          ],
        ),
      );
    }
    final url = candidates.first;
    final effectiveFallbacks = <String, List<String>>{
      ...fallbackUrlsByImage,
      if (candidates.isNotEmpty)
        candidates.first: candidates.skip(1).toList(growable: false),
    };

    // 优先使用从 Markdown 文本预提取的图片列表（URL 来源一致，精确匹配）
    List<String> effectiveMediaUrls;
    int effectiveIndex;

    if (galleryImages != null && galleryImages.isNotEmpty) {
      effectiveMediaUrls = galleryImages;
      effectiveIndex = galleryImages.indexOf(url);
      if (effectiveIndex == -1) effectiveIndex = 0; // 保底：至少显示第一张
    } else {
      // 从统一媒体资产列表中查找；找不到时仅展示当前已匹配资产。
      final mediaUrls = ContentParser.extractAllMedia(detail);
      effectiveIndex = mediaUrls.indexOf(url);
      if (effectiveIndex == -1) {
        final cleanSearch = url.split('?').first;
        effectiveIndex = mediaUrls.indexWhere(
          (m) => m.split('?').first == cleanSearch,
        );
      }
      if (effectiveIndex == -1) {
        // 完全找不到：单张图片 gallery
        effectiveMediaUrls = [url];
        effectiveIndex = 0;
      } else {
        effectiveMediaUrls = mediaUrls;
      }
    }

    // 使用 md- 前缀以避免与底部 GridView 产生 Hero 标签冲突
    final String baseTag = effectiveIndex == 0
        ? 'md-content-image-${detail.id}'
        : 'md-image-$effectiveIndex-${detail.id}';

    String finalHeroTag = baseTag;
    int suffix = 1;
    if (usedHeroTags != null) {
      while (usedHeroTags.contains(finalHeroTag)) {
        finalHeroTag = '$baseTag-dup$suffix';
        suffix++;
      }
      usedHeroTags.add(finalHeroTag);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          MediaGalleryItem(
            images: effectiveMediaUrls,
            index: effectiveIndex,
            fallbackUrlsByImage: effectiveFallbacks,
            mediaAssetsByImage: {
              for (final asset in detail.mediaAssets)
                if (asset.sources.isNotEmpty) asset.sources.first.url: asset,
            },
            contentId: detail.id,
            contentColor: contentColor,
            heroTag: finalHeroTag,
            fit: BoxFit.fitWidth,
            borderRadius: AppShape.paneBorder,
          ),
          if (alt != null && alt.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 16, left: 16, right: 16),
              child: Text(
                alt,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Isolate paragraphs and media instead of caching one article-sized layer.
class _ArticleMarkdownBody extends MarkdownBody {
  const _ArticleMarkdownBody({
    super.key,
    required super.data,
    super.selectable,
    super.softLineBreak,
    super.onTapLink,
    super.styleSheet,
    super.builders,
    super.imageBuilder,
  });

  @override
  Widget build(BuildContext context, List<Widget>? children) => super.build(
    context,
    children
        ?.map((child) => RepaintBoundary(child: child))
        .toList(growable: false),
  );
}
