import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:frontend/core/utils/safe_url_launcher.dart';

import '../../../../../theme/design_tokens.dart';
import '../../../models/content.dart';
import '../../../utils/content_parser.dart';
import '../../../../../core/widgets/markdown_reading.dart';
import 'media_gallery_item.dart';
import '../../../../../core/widgets/media_image_hero.dart';

class RichContent extends StatefulWidget {
  final ContentDetail detail;
  final List<String> inlineImageUrls;
  final Map<String, GlobalKey> headerKeys;
  final bool hideMedia;
  final AutoScrollController? scrollController;
  final Map<String, int>? headerIndexes;
  final ValueChanged<int>? onBlockCount;

  const RichContent({
    super.key,
    required this.detail,
    required this.inlineImageUrls,
    required this.headerKeys,
    this.hideMedia = false,
    this.scrollController,
    this.headerIndexes,
    this.onBlockCount,
  });

  @override
  State<RichContent> createState() => _RichContentState();
}

class _RichContentState extends State<RichContent> {
  ContentDetail get detail => widget.detail;
  Map<String, GlobalKey> get headerKeys => widget.headerKeys;
  bool get hideMedia => widget.hideMedia;
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
    final markdown = detail.body ?? '';

    final headingOccurrences = <String, int>{};
    final List<Widget> children = [];

    if (markdown.isNotEmpty) {
      final style = _style;
      // 从 Markdown 文本中提取图片标识，只保留能匹配统一媒体资产的条目。
      final inlineImageUrls = widget.inlineImageUrls
          .map(
            (url) =>
                ContentParser.imageCandidatesForUrl(detail, url).firstOrNull,
          )
          .whereType<String>()
          .toList(growable: false);

      children.add(
        _ContentMarkdown(
          scrollController: widget.scrollController,
          headerIndexes: widget.headerIndexes,
          onBlockCount: widget.onBlockCount,
          headerKeys: headerKeys,
          key: ValueKey(detail.id),
          data: markdown,
          selectable: false,
          // 社交消息的单换行属于原始排版。
          softLineBreak: const [
            'xiaohongshu',
            'telegram',
          ].contains(detail.platform),
          onTapLink: (text, href, title) async {
            await SafeUrlLauncher.openExternal(context, href);
          },
          styleSheet: style,
          inlineSyntaxes: readingInlineSyntaxes(),
          blockSyntaxes: readingBlockSyntaxes(),
          builders: {
            ...readingMarkdownBuilders(context),
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
          },
          // ignore: deprecated_member_use
          imageBuilder: (uri, title, alt) => _buildMarkdownImage(
            context,
            detail,
            uri,
            alt,
            galleryImages: inlineImageUrls,
            fallbackUrlsByImage: mediaFallbacks,
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
              return MediaGalleryItem(
                images: mediaUrls,
                index: index,
                fallbackUrlsByImage: mediaFallbacks,
                mediaAssetsByImage: mediaAssetsByImage,
                contentId: detail.id,
              );
            },
          ),
        );
      }
    }

    if (widget.scrollController != null) {
      return SliverMainAxisGroup(
        slivers: [
          for (final child in children)
            if (child is _ContentMarkdown)
              child
            else
              SliverToBoxAdapter(child: child),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  Widget _buildMarkdownImage(
    BuildContext context,
    ContentDetail detail,
    Uri uri,
    String? alt, {
    List<String>? galleryImages,
    Map<String, List<String>> fallbackUrlsByImage = const {},
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
      if (effectiveIndex == -1) {
        effectiveMediaUrls = [url];
        effectiveIndex = 0;
      }
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
            presentation: MediaPresentation.body,
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

/// 文章段落进入主滚动视口；短消息仍可嵌入媒体说明栏。
class _ContentMarkdown extends MarkdownBody {
  const _ContentMarkdown({
    super.key,
    required super.data,
    super.selectable,
    super.softLineBreak,
    super.onTapLink,
    super.styleSheet,
    super.builders,
    super.inlineSyntaxes,
    super.blockSyntaxes,
    super.imageBuilder,
    required this.scrollController,
    required this.headerIndexes,
    this.onBlockCount,
    required this.headerKeys,
  });

  final AutoScrollController? scrollController;
  final Map<String, int>? headerIndexes;
  final ValueChanged<int>? onBlockCount;
  final Map<String, GlobalKey> headerKeys;

  @override
  Widget build(BuildContext context, List<Widget>? children) {
    final controller = scrollController;
    if (controller == null) return super.build(context, children);
    final blocks = children!;
    onBlockCount?.call(blocks.length);
    final headingsByKey = {
      for (final entry in headerKeys.entries) entry.value: entry.key,
    };
    headerIndexes!.clear();

    void indexHeadings(Widget block, int index) {
      final heading = headingsByKey[block.key];
      if (heading != null) headerIndexes![heading] = index;
      // Markdown nests quoted/list headings inside render-object wrappers.
      // Use the actual top-level list index, including its spacing widgets.
      if (block is SingleChildRenderObjectWidget) {
        final child = block.child;
        if (child != null) indexHeadings(child, index);
      } else if (block is MultiChildRenderObjectWidget) {
        for (final child in block.children) {
          indexHeadings(child, index);
        }
      } else if (block is ProxyWidget) {
        indexHeadings(block.child, index);
      }
    }

    for (var index = 0; index < blocks.length; index++) {
      indexHeadings(blocks[index], index);
    }
    return SliverList.builder(
      itemCount: blocks.length,
      itemBuilder: (context, index) => AutoScrollTag(
        key: ValueKey(index),
        controller: controller,
        index: index,
        child: blocks[index],
      ),
    );
  }
}
