import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:frontend/core/utils/safe_url_launcher.dart';

import '../../../../../theme/design_tokens.dart';
import '../../../models/content.dart';
import '../../../utils/content_parser.dart';
import '../markdown/markdown_config.dart';
import 'media_gallery_item.dart';

class RichContent extends StatelessWidget {
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

    final Set<String> usedHeroTags = {};
    final List<Widget> children = [];

    if (markdown.isNotEmpty) {
      final style = _getMarkdownStyle(theme);
      // 从 Markdown 文本中提取图片标识，只保留能匹配统一媒体资产的条目。
      final inlineImageUrls = _extractInlineImageUrls(markdown)
          .map(
            (url) =>
                ContentParser.imageCandidatesForUrl(detail, url).firstOrNull,
          )
          .whereType<String>()
          .toList(growable: false);

      children.add(
        RepaintBoundary(
          child: MarkdownBody(
            data: markdown,
            selectable: true,
            onTapLink: (text, href, title) async {
              await SafeUrlLauncher.openExternal(context, href);
            },
            styleSheet: style,
            builders: {
              'h1': HeaderBuilder(headerKeys, style.h1),
              'h2': HeaderBuilder(headerKeys, style.h2),
              'h3': HeaderBuilder(headerKeys, style.h3),
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

  MarkdownStyleSheet _getMarkdownStyle(ThemeData theme) {
    return MarkdownStyleSheet.fromTheme(theme).copyWith(
      p: theme.textTheme.bodyLarge?.copyWith(
        height: 1.7,
        color: theme.colorScheme.onSurface,
      ),
      h1: theme.textTheme.headlineMedium?.copyWith(
        fontWeight: FontWeight.w700,
        color: theme.colorScheme.onSurface,
      ),
      h2: theme.textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w700,
        color: theme.colorScheme.onSurface,
      ),
      h3: theme.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.bold,
        color: theme.colorScheme.onSurface,
      ),
      blockSpacing: AppSpacing.md,
      listBullet: theme.textTheme.bodyLarge?.copyWith(
        color: theme.colorScheme.primary,
        fontWeight: FontWeight.bold,
      ),
      blockquote: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        height: 1.65,
        fontStyle: FontStyle.italic,
      ),
      blockquotePadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 14,
      ),
      blockquoteDecoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: AppShape.cardMediaBorder,
      ),
      code: theme.textTheme.bodyMedium?.copyWith(
        backgroundColor: Colors.transparent,
        fontFamily: 'monospace',
      ),
      codeblockPadding: EdgeInsets.zero,
      codeblockDecoration: const BoxDecoration(),
    );
  }

  /// 从 Markdown 文本中按顺序提取 inline 图片标识。
  /// 这里只用于匹配已经归档的媒体资产，不直接请求正文里的原始 URL。
  List<String> _extractInlineImageUrls(String markdown) {
    if (markdown.isEmpty) return const [];
    final regex = RegExp(r'!\[.*?\]\(([^)]+)\)');
    return regex.allMatches(markdown).map((m) => m.group(1)!.trim()).toList();
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
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Semantics(
          label: alt?.trim().isNotEmpty == true ? alt!.trim() : '媒体资产不可用',
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: AppShape.paneBorder,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.hide_image_outlined,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 8),
                Text(
                  '图片尚未归档',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                if (alt != null && alt.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    alt.trim(),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ],
              ],
            ),
          ),
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
