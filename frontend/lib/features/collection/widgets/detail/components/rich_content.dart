import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../../core/network/image_headers.dart';
import '../../../models/content.dart';
import '../../../utils/content_parser.dart';

import '../markdown/markdown_config.dart';
import '../gallery/full_screen_gallery.dart';
import 'author_header.dart';
import 'unified_stats.dart';
import 'zhihu_question_stats.dart';
import 'zhihu_top_answers.dart';
import '../../video_player_widget.dart';

class RichContent extends StatelessWidget {
  final ContentDetail detail;
  final String apiBaseUrl;
  final String? apiToken;
  final Map<String, GlobalKey> headerKeys;
  final bool useHero;
  final bool hideZhihuHeader;
  final bool hideTopAnswers;
  final Color? contentColor;

  const RichContent({
    super.key,
    required this.detail,
    required this.apiBaseUrl,
    this.apiToken,
    required this.headerKeys,
    this.useHero = true,
    this.hideZhihuHeader = false,
    this.hideTopAnswers = false,
    this.contentColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final storedMap = ContentParser.getStoredMap(detail);
    final mediaUrls = ContentParser.extractAllMedia(detail, apiBaseUrl);
    final rawMarkdown = _getMarkdownContent(detail);
    final markdown = _preprocessMarkdown(rawMarkdown);

    final Set<String> usedHeroTags = {};
    final List<Widget> children = [];

    if (markdown.isNotEmpty) {
      final style = _getMarkdownStyle(theme);
      // ... 其余逻辑保持一致

      final questionInfo = detail.isZhihuAnswer
          ? (detail.rawMetadata?['associated_question'])
          : null;

      if (!hideZhihuHeader && detail.isZhihuAnswer && questionInfo != null) {
        children.addAll([
          GestureDetector(
            onTap: () {
              if (questionInfo['url'] != null) {
                launchUrl(
                  Uri.parse(questionInfo['url']),
                  mode: LaunchMode.externalApplication,
                );
              }
            },
            child: Text(
              questionInfo['title'] ?? '未知问题',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
                color: theme.colorScheme.primary,
                height: 1.3,
              ),
            ),
          ),
          const SizedBox(height: 16),
          ZhihuQuestionStats(stats: questionInfo),
          const SizedBox(height: 24),
          AuthorHeader(detail: detail),
          const SizedBox(height: 12),
          UnifiedStats(detail: detail),
          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 32),
        ]);
      }

      children.add(
        RepaintBoundary(
          child: MarkdownBody(
            data: markdown,
            selectable: true,
            onTapLink: (text, href, title) {
              if (href != null) {
                launchUrl(
                  Uri.parse(href),
                  mode: LaunchMode.externalApplication,
                );
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
              storedMap,
              apiBaseUrl,
              apiToken,
              useHero: useHero,
              usedHeroTags: usedHeroTags,
            ),
          ),
        ),
      );

      if (!hideTopAnswers &&
          detail.isZhihuQuestion &&
          detail.rawMetadata != null &&
          detail.rawMetadata!['top_answers'] != null) {
        children.add(
          ZhihuTopAnswers(
            topAnswers: detail.rawMetadata!['top_answers'] as List<dynamic>,
          ),
        );
      }
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

        if (!hideTopAnswers &&
            detail.isZhihuQuestion &&
            detail.rawMetadata != null &&
            detail.rawMetadata!['top_answers'] != null) {
          children.add(
            ZhihuTopAnswers(
              topAnswers: detail.rawMetadata!['top_answers'] as List<dynamic>,
            ),
          );
        }

        children.add(const SizedBox(height: 24));
      } else {
        if (!hideTopAnswers &&
            detail.isZhihuQuestion &&
            detail.rawMetadata != null &&
            detail.rawMetadata!['top_answers'] != null) {
          children.add(
            ZhihuTopAnswers(
              topAnswers: detail.rawMetadata!['top_answers'] as List<dynamic>,
            ),
          );
        }
      }
    }

    bool showMediaGrid = false;
    if (detail.isZhihuPin || detail.isTwitter || detail.isWeibo) {
      showMediaGrid = mediaUrls.isNotEmpty;
    } else {
      if (markdown.isEmpty && mediaUrls.isNotEmpty) {
        showMediaGrid = true;
      }
    }

    if (showMediaGrid) {
      if (children.isNotEmpty) children.add(const SizedBox(height: 24));

      if (mediaUrls.length == 1) {
        children.add(
          Builder(
            builder: (context) {
              final url = mediaUrls.first;
              if (ContentParser.isVideo(url)) {
                return ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: VideoPlayerWidget(
                    videoUrl: url,
                    headers: buildImageHeaders(
                      imageUrl: url,
                      baseUrl: apiBaseUrl,
                      apiToken: apiToken,
                    ),
                  ),
                );
              }
              return GestureDetector(
                onTap: () => _showFullScreenImage(
                  context,
                  mediaUrls,
                  0,
                  apiBaseUrl,
                  apiToken,
                  detail.id,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: Hero(
                    tag: 'content-image-${detail.id}',
                    child: CachedNetworkImage(
                      imageUrl: url,
                      httpHeaders: buildImageHeaders(
                        imageUrl: url,
                        baseUrl: apiBaseUrl,
                        apiToken: apiToken,
                      ),
                      fit: BoxFit.contain,
                      placeholder: (c, u) => Container(
                        height: 240,
                        width: double.infinity,
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: const Center(child: CircularProgressIndicator()),
                      ),
                    ),
                  ),
                ),
              );
            },
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
              final url = mediaUrls[index];
              if (ContentParser.isVideo(url)) {
                return ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: Stack(
                    children: [
                      Container(color: Colors.black),
                      const Center(
                        child: Icon(
                          Icons.play_circle_outline,
                          color: Colors.white,
                          size: 48,
                        ),
                      ),
                      Positioned.fill(
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () {
                              // TODO: Open video player dialog
                            },
                            child: const Center(
                              child: Text(
                                "VIDEO",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }
              return GestureDetector(
                onTap: () => _showFullScreenImage(
                  context,
                  mediaUrls,
                  index,
                  apiBaseUrl,
                  apiToken,
                  detail.id,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: Hero(
                    tag: index == 0
                        ? 'content-image-${detail.id}'
                        : 'image-$index-${detail.id}',
                    child: CachedNetworkImage(
                      imageUrl: url,
                      httpHeaders: buildImageHeaders(
                        imageUrl: url,
                        baseUrl: apiBaseUrl,
                        apiToken: apiToken,
                      ),
                      fit: BoxFit.cover,
                      placeholder: (c, u) => Container(
                        color: theme.colorScheme.surfaceContainerHighest,
                      ),
                    ),
                  ),
                ),
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

  void _showFullScreenImage(
    BuildContext context,
    List<String> images,
    int initialIndex,
    String apiBaseUrl,
    String? apiToken,
    int contentId,
  ) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.transparent,
        pageBuilder: (context, animation, secondaryAnimation) =>
            FullScreenGallery(
              images: images,
              initialIndex: initialIndex,
              apiBaseUrl: apiBaseUrl,
              apiToken: apiToken,
              contentId: contentId,
              contentColor: contentColor,
            ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  String _getMarkdownContent(ContentDetail detail) {
    if (detail.rawMetadata != null && detail.rawMetadata!['archive'] != null) {
      return detail.rawMetadata!['archive']['markdown']?.toString() ?? '';
    }
    if (detail.isBilibili && (detail.description?.contains('![') ?? false)) {
      return detail.description ?? '';
    }
    if ((detail.isZhihuArticle || detail.isZhihuAnswer) &&
        detail.description != null) {
      return detail.description!;
    }
    return '';
  }

  String _preprocessMarkdown(String markdown) {
    if (markdown.isEmpty) return markdown;

    // 1. 处理 Latex 块: 将 $$ ... $$ 转换为 ```latex ... ```
    var processed = markdown.replaceAllMapped(
      RegExp(r'(?:\n|^)\$\$\s*([\s\S]+?)\s*\$\$(?:\n|$)'),
      (match) => '\n\n```latex\n${match.group(1)!.trim()}\n```\n\n',
    );

    // 2. 处理 Latex 行内: 将 $ ... $ 转换为 ```latex-inline ... ```
    processed = processed.replaceAllMapped(
      RegExp(r'(?<![\d\w])\$([^\$\n]+?)\$(?![\d\w])'),
      (match) {
        final content = match.group(1)!;
        // 只有包含 LaTeX 关键字（反斜杠）或者明显的数学结构时才渲染为 LaTeX
        // 这样可以避免误伤类似 $100$ 这种表示价格或强调的文字
        if (content.contains('\\') ||
            (content.length > 3 && RegExp(r'[=+\-^_{}]').hasMatch(content))) {
          return '```latex-inline\n$content```';
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
      codeblockDecoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
      ),
    );

    _styleCache[theme.brightness] = style;
    return style;
  }

  Widget _buildMarkdownImage(
    BuildContext context,
    ContentDetail detail,
    Uri uri,
    String? alt,
    Map<String, String> storedMap,
    String apiBaseUrl,
    String? apiToken, {
    bool useHero = true,
    Set<String>? usedHeroTags,
  }) {
    String url = uri.toString();
    if (storedMap.containsKey(url)) {
      url = ContentParser.mapUrl(storedMap[url]!, apiBaseUrl);
    } else {
      final cleanUrl = url.split('?').first;
      final match = storedMap.entries.firstWhere(
        (e) => e.key.split('?').first == cleanUrl,
        orElse: () => const MapEntry('', ''),
      );
      url = match.key.isNotEmpty
          ? ContentParser.mapUrl(match.value, apiBaseUrl)
          : ContentParser.mapUrl(url, apiBaseUrl);
    }

    final String heroTag = 'markdown-image-$url-${detail.id}';
    final bool canUseHero =
        useHero && usedHeroTags != null && !usedHeroTags.contains(heroTag);
    if (canUseHero) usedHeroTags.add(heroTag);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: () => _showFullScreenImage(
              context,
              [url],
              0,
              apiBaseUrl,
              apiToken,
              detail.id,
            ),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Theme.of(
                      context,
                    ).colorScheme.shadow.withValues(alpha: 0.1),
                    blurRadius: 30,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: CachedNetworkImage(
                  imageUrl: url,
                  httpHeaders: buildImageHeaders(
                    imageUrl: url,
                    baseUrl: apiBaseUrl,
                    apiToken: apiToken,
                  ),
                  fit: BoxFit.fitWidth,
                  placeholder: (c, u) => Container(
                    height: 200,
                    width: double.infinity,
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    child: const Center(child: CircularProgressIndicator()),
                  ),
                ),
              ),
            ),
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
