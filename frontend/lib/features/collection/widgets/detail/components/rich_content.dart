import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:frontend/core/utils/media_utils.dart';
import '../../../models/content.dart';
import '../../../utils/content_parser.dart';

import '../markdown/markdown_config.dart';
import 'media_gallery_item.dart';

class RichContent extends StatelessWidget {
  final ContentDetail detail;
  final String apiBaseUrl;
  final String? apiToken;
  final Map<String, GlobalKey> headerKeys;
  final bool useHero;
  final bool hideMedia;
  final Color? contentColor;

  const RichContent({
    super.key,
    required this.detail,
    required this.apiBaseUrl,
    this.apiToken,
    required this.headerKeys,
    this.useHero = true,
    this.hideMedia = false,
    this.contentColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mediaUrls = ContentParser.extractAllMedia(detail, apiBaseUrl);
    final rawMarkdown = _getMarkdownContent(detail);
    final markdown = _preprocessMarkdown(rawMarkdown);

    final Set<String> usedHeroTags = {};
    final List<Widget> children = [];

    if (markdown.isNotEmpty) {
      final style = _getMarkdownStyle(theme);
      
      children.add(
        RepaintBoundary(
          child: MarkdownBody(
            data: markdown,
            selectable: true,
            onTapLink: (text, href, title) async {
              if (href == null) return;
              try {
                final uri = Uri.parse(href);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(
                    uri,
                    mode: LaunchMode.externalApplication,
                  );
                }
              } catch (_) {
                // Ignore malformed/unsupported links to avoid crashing markdown taps.
              }
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
              apiBaseUrl,
              apiToken,
              useHero: useHero,
              usedHeroTags: usedHeroTags,
            ),
          ),
        ),
      );
    } else {
      if (detail.description != null && detail.description!.isNotEmpty) {
        children.add(
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Text(
              detail.description!,
              style: theme.textTheme.bodyLarge?.copyWith(height: 1.6),
            ),
          ),
        );
        children.add(const SizedBox(height: 24));
      }
    }

    bool showMediaGrid = false;
    // Generic media grid logic
    if (detail.resolvedLayoutType == 'gallery' || detail.resolvedLayoutType == 'video') {
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
            apiBaseUrl: apiBaseUrl,
            apiToken: apiToken,
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
                apiBaseUrl: apiBaseUrl,
                apiToken: apiToken,
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
    // 直接使用 description 字段（后端已经在 archive.markdown 中填充）
    return detail.description ?? '';
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

  static final Map<Brightness, MarkdownStyleSheet> _styleCache = {};

  MarkdownStyleSheet _getMarkdownStyle(ThemeData theme) {
    if (_styleCache.containsKey(theme.brightness)) {
      return _styleCache[theme.brightness]!;
    }

    final style = MarkdownStyleSheet.fromTheme(theme).copyWith(
      p: theme.textTheme.bodyLarge?.copyWith(
        height: 1.8,
        fontSize: 18,
        color: theme.colorScheme.onSurface.withValues(alpha: 0.9),
      ),
      h1: theme.textTheme.headlineMedium?.copyWith(
        fontWeight: FontWeight.w900,
        color: theme.colorScheme.primary,
        letterSpacing: -0.5,
      ),
      h2: theme.textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w900,
        color: theme.colorScheme.secondary,
        letterSpacing: -0.3,
      ),
      h3: theme.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.bold,
        color: theme.colorScheme.tertiary,
      ),
      blockSpacing: 32,
      listBullet: theme.textTheme.bodyLarge?.copyWith(
        color: theme.colorScheme.primary,
        fontWeight: FontWeight.bold,
      ),
      blockquote: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSecondaryContainer,
        height: 1.6,
        fontStyle: FontStyle.italic,
      ),
      blockquotePadding: const EdgeInsets.symmetric(
        horizontal: 24,
        vertical: 20,
      ),
      blockquoteDecoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(24),
        border: Border(
          left: BorderSide(color: theme.colorScheme.secondary, width: 8),
        ),
      ),
      code: theme.textTheme.bodyMedium?.copyWith(
        backgroundColor: Colors.transparent,
        fontFamily: 'monospace',
      ),
      codeblockPadding: EdgeInsets.zero,
      codeblockDecoration: const BoxDecoration(),
    );

    _styleCache[theme.brightness] = style;
    return style;
  }

  Widget _buildMarkdownImage(
    BuildContext context,
    ContentDetail detail,
    Uri uri,
    String? alt,
    String apiBaseUrl,
    String? apiToken, {
    bool useHero = true,
    Set<String>? usedHeroTags,
  }) {
    String url = mapUrl(uri.toString(), apiBaseUrl);

    // 在全局媒体列表中查找此图片的索引
    final mediaUrls = ContentParser.extractAllMedia(detail, apiBaseUrl);
    int index = mediaUrls.indexOf(url);
    if (index == -1) {
      final cleanSearch = url.split('?').first;
      index = mediaUrls.indexWhere((m) => m.split('?').first == cleanSearch);
    }

    // 如果仍未找到，将此图片添加到列表末尾以确保完整的图片列表
    List<String> effectiveMediaUrls = mediaUrls;
    int effectiveIndex = index;
    if (index == -1) {
      effectiveMediaUrls = [...mediaUrls, url];
      effectiveIndex = effectiveMediaUrls.length - 1;
    }

    // 使用 md- 前缀以避免与底部 GridView 产生 Hero 标签冲突
    final String baseTag = effectiveIndex != -1
        ? (effectiveIndex == 0
              ? 'md-content-image-${detail.id}'
              : 'md-image-$effectiveIndex-${detail.id}')
        : 'markdown-image-$url-${detail.id}';

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
            apiBaseUrl: apiBaseUrl,
            apiToken: apiToken,
            contentId: detail.id,
            contentColor: contentColor,
            heroTag: finalHeroTag,
            fit: BoxFit.fitWidth,
            borderRadius: BorderRadius.circular(24),
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
                  letterSpacing: 0.5,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
