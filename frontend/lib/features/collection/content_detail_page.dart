import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';
import 'models/content.dart';
import 'providers/collection_provider.dart';

import '../../core/network/api_client.dart';
import '../../core/network/image_headers.dart';

class ContentDetailPage extends ConsumerStatefulWidget {
  final int contentId;

  const ContentDetailPage({super.key, required this.contentId});

  @override
  ConsumerState<ContentDetailPage> createState() => _ContentDetailPageState();
}

class _ContentDetailPageState extends ConsumerState<ContentDetailPage> {
  String? _selectedImageUrl;
  final ScrollController _contentScrollController = ScrollController();

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(contentDetailProvider(widget.contentId));
    final dio = ref.watch(apiClientProvider);
    final apiBaseUrl = dio.options.baseUrl;
    final apiToken = dio.options.headers['X-API-Token']?.toString();

    return Scaffold(
      appBar: AppBar(
        title: const Text('内容详情'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            onPressed: () {
              // TODO: Implement share
            },
          ),
        ],
      ),
      body: detailAsync.when(
        data: (detail) =>
            _buildResponsiveLayout(context, detail, apiBaseUrl, apiToken),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text('加载失败: $err'),
              ElevatedButton(
                onPressed: () =>
                    ref.invalidate(contentDetailProvider(widget.contentId)),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResponsiveLayout(
    BuildContext context,
    ContentDetail detail,
    String apiBaseUrl,
    String? apiToken,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isLandscape = constraints.maxWidth > 800;
        final bool isTwitter =
            detail.platform.toLowerCase() == 'twitter' ||
            detail.platform.toLowerCase() == 'x';
        final bool hasMarkdown = _hasMarkdown(detail);

        if (isLandscape) {
          if (isTwitter) {
            return _buildTwitterLandscape(
              context,
              detail,
              apiBaseUrl,
              apiToken,
            );
          } else if (hasMarkdown) {
            return _buildMarkdownLandscape(
              context,
              detail,
              apiBaseUrl,
              apiToken,
            );
          } else if (detail.platform.toLowerCase() == 'bilibili') {
            return _buildBilibiliLandscape(
              context,
              detail,
              apiBaseUrl,
              apiToken,
            );
          } else {
            return _buildDefaultLandscape(
              context,
              detail,
              apiBaseUrl,
              apiToken,
            );
          }
        } else {
          // Portrait: normal top-to-bottom
          return _buildPortraitLayout(context, detail, apiBaseUrl, apiToken);
        }
      },
    );
  }

  bool _hasMarkdown(ContentDetail detail) {
    if (detail.rawMetadata != null && detail.rawMetadata!['archive'] != null) {
      final md = detail.rawMetadata!['archive']['markdown'];
      return md != null && md.toString().isNotEmpty;
    }
    return detail.platform.toLowerCase() == 'bilibili' &&
        (detail.description?.contains('![') ?? false);
  }

  // --- Twitter Red-style Layout ---

  Widget _buildTwitterLandscape(
    BuildContext context,
    ContentDetail detail,
    String apiBaseUrl,
    String? apiToken,
  ) {
    final images = _extractAllImages(detail, apiBaseUrl);

    return Row(
      children: [
        // Left: Media Area
        Expanded(
          flex: 6,
          child: Container(
            color: Colors.black.withValues(alpha: 0.03),
            child: images.isEmpty
                ? const Center(
                    child: Icon(
                      Icons.text_fields,
                      size: 64,
                      color: Colors.grey,
                    ),
                  )
                : _buildTwitterMediaArea(detail, images, apiBaseUrl, apiToken),
          ),
        ),
        // Right: Content Info Area
        Expanded(
          flex: 4,
          child: _buildTwitterSideInfo(context, detail, apiBaseUrl, apiToken),
        ),
      ],
    );
  }

  Widget _buildTwitterMediaArea(
    ContentDetail detail,
    List<String> images,
    String apiBaseUrl,
    String? apiToken,
  ) {
    if (_selectedImageUrl == null && images.isNotEmpty) {
      _selectedImageUrl = images.first;
    }

    return Column(
      children: [
        // Main Zoomed Image
        Expanded(
          child: Center(
            child: InteractiveViewer(
              child: Hero(
                tag: 'content-image-${detail.id}',
                child: CachedNetworkImage(
                  imageUrl: _selectedImageUrl!,
                  httpHeaders: buildImageHeaders(
                    imageUrl: _selectedImageUrl!,
                    baseUrl: apiBaseUrl,
                    apiToken: apiToken,
                  ),
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
        ),
        // Thumbnails grid
        if (images.length > 1)
          Container(
            height: 80,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: images.length,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemBuilder: (context, index) {
                final img = images[index];
                final isSelected = img == _selectedImageUrl;
                return GestureDetector(
                  onTap: () => setState(() => _selectedImageUrl = img),
                  child: Container(
                    width: 64,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      border: isSelected
                          ? Border.all(
                              color: Theme.of(context).colorScheme.primary,
                              width: 2,
                            )
                          : null,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: CachedNetworkImage(
                        imageUrl: img,
                        httpHeaders: buildImageHeaders(
                          imageUrl: img,
                          baseUrl: apiBaseUrl,
                          apiToken: apiToken,
                        ),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildTwitterSideInfo(
    BuildContext context,
    ContentDetail detail,
    String apiBaseUrl,
    String? apiToken,
  ) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildAuthorHeader(context, detail),
          const SizedBox(height: 20),
          if (detail.description != null)
            Text(
              detail.description!,
              style: theme.textTheme.bodyLarge?.copyWith(
                height: 1.6,
                fontSize: 17,
              ),
            ),
          const SizedBox(height: 24),
          _buildStats(context, detail),
          const SizedBox(height: 16),
          _buildTags(context, detail),
          const Divider(height: 48),
          _buildActions(context, detail),
        ],
      ),
    );
  }

  // --- Markdown TOC Layout ---

  Widget _buildMarkdownLandscape(
    BuildContext context,
    ContentDetail detail,
    String apiBaseUrl,
    String? apiToken,
  ) {
    final markdown = _getMarkdownContent(detail);
    final headers = _extractHeaders(markdown);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left: Main Content
        Expanded(
          flex: 7,
          child: SingleChildScrollView(
            controller: _contentScrollController,
            padding: const EdgeInsets.all(32),
            child: _buildRichContent(context, detail, apiBaseUrl, apiToken),
          ),
        ),
        // Right: TOC
        if (headers.isNotEmpty)
          Container(
            width: 280,
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
            ),
            child: _buildTOC(context, headers),
          ),
      ],
    );
  }

  Widget _buildTOC(BuildContext context, List<_HeaderLine> headers) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 16, left: 4),
          child: Text(
            '目录',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        ...headers.map(
          (h) => InkWell(
            onTap: () {
              // TODO: Jump to header
            },
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: EdgeInsets.only(
                left: (h.level - 1) * 16.0 + 8.0,
                top: 8,
                bottom: 8,
                right: 8,
              ),
              child: Text(
                h.text,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: h.level == 1
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                  fontWeight: h.level == 1
                      ? FontWeight.bold
                      : FontWeight.normal,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // --- Default & Portrait ---

  Widget _buildPortraitLayout(
    BuildContext context,
    ContentDetail detail,
    String apiBaseUrl,
    String? apiToken,
  ) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildAuthorHeader(context, detail),
            const SizedBox(height: 16),
            Row(
              children: [
                _getPlatformIcon(detail.platform, 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    detail.title ??
                        (detail.platform.toLowerCase() == 'twitter'
                            ? '推文'
                            : '无标题内容'),
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _buildStats(context, detail),
            const SizedBox(height: 16),
            _buildTags(context, detail),
            const Divider(height: 40),
            _buildRichContent(context, detail, apiBaseUrl, apiToken),
            const SizedBox(height: 40),
            _buildActions(context, detail),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildDefaultLandscape(
    BuildContext context,
    ContentDetail detail,
    String apiBaseUrl,
    String? apiToken,
  ) {
    return _buildPortraitLayout(context, detail, apiBaseUrl, apiToken);
  }

  Widget _buildBilibiliLandscape(
    BuildContext context,
    ContentDetail detail,
    String apiBaseUrl,
    String? apiToken,
  ) {
    final images = _extractAllImages(detail, apiBaseUrl);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Left: Media Area (Cover or Image List)
        Expanded(
          flex: 6,
          child: Container(
            color: Colors.black.withValues(alpha: 0.05),
            child: images.isEmpty
                ? const Center(
                    child: Icon(
                      Icons.movie_outlined,
                      size: 64,
                      color: Colors.grey,
                    ),
                  )
                : (images.length == 1
                      ? Center(
                          child: Hero(
                            tag: 'content-image-${detail.id}',
                            child: CachedNetworkImage(
                              imageUrl: images.first,
                              httpHeaders: buildImageHeaders(
                                imageUrl: images.first,
                                baseUrl: apiBaseUrl,
                                apiToken: apiToken,
                              ),
                              fit: BoxFit.contain,
                            ),
                          ),
                        )
                      : ListView.builder(
                          itemCount: images.length,
                          padding: const EdgeInsets.all(24),
                          itemBuilder: (context, index) => Padding(
                            padding: const EdgeInsets.only(bottom: 24),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: index == 0
                                  ? Hero(
                                      tag: 'content-image-${detail.id}',
                                      child: CachedNetworkImage(
                                        imageUrl: images[index],
                                        httpHeaders: buildImageHeaders(
                                          imageUrl: images[index],
                                          baseUrl: apiBaseUrl,
                                          apiToken: apiToken,
                                        ),
                                        fit: BoxFit.contain,
                                      ),
                                    )
                                  : CachedNetworkImage(
                                      imageUrl: images[index],
                                      httpHeaders: buildImageHeaders(
                                        imageUrl: images[index],
                                        baseUrl: apiBaseUrl,
                                        apiToken: apiToken,
                                      ),
                                      fit: BoxFit.contain,
                                    ),
                            ),
                          ),
                        )),
          ),
        ),
        // Right: Info Area
        Expanded(
          flex: 4,
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: colorScheme.outlineVariant),
              ),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildAuthorHeader(context, detail),
                  const SizedBox(height: 32),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _getPlatformIcon(detail.platform, 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          detail.title ?? '无标题内容',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _buildStats(context, detail),
                  const SizedBox(height: 16),
                  _buildTags(context, detail),
                  const Divider(height: 64),
                  if (detail.description != null &&
                      detail.description!.isNotEmpty &&
                      detail.description != '-') ...[
                    Text(
                      '简介',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      detail.description!,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        height: 1.6,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  _buildBilibiliStats(context, detail),
                  const SizedBox(height: 48),
                  _buildActions(context, detail),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // --- Common Components ---

  Widget _buildAuthorHeader(BuildContext context, ContentDetail detail) {
    final theme = Theme.of(context);
    return Row(
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Text(
            (detail.authorName ?? '?').substring(0, 1).toUpperCase(),
            style: TextStyle(color: theme.colorScheme.onPrimaryContainer),
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              detail.authorName ?? '未知作者',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            if (detail.publishedAt != null)
              Text(
                DateFormat(
                  'yyyy-MM-dd HH:mm',
                ).format(detail.publishedAt!.toLocal()),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildStats(BuildContext context, ContentDetail detail) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Row(
      children: [
        Icon(Icons.visibility_outlined, size: 18, color: colorScheme.outline),
        const SizedBox(width: 4),
        Text('${detail.viewCount}', style: theme.textTheme.bodySmall),
        const SizedBox(width: 16),
        Icon(Icons.favorite_border, size: 18, color: colorScheme.outline),
        const SizedBox(width: 4),
        Text('${detail.likeCount}', style: theme.textTheme.bodySmall),
      ],
    );
  }

  Widget _buildTags(BuildContext context, ContentDetail detail) {
    if (detail.tags.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: detail.tags
          .map(
            (tag) => Chip(
              label: Text(tag),
              labelStyle: Theme.of(context).textTheme.labelSmall,
              visualDensity: VisualDensity.compact,
              side: BorderSide.none,
              backgroundColor: Theme.of(
                context,
              ).colorScheme.surfaceContainerHigh,
            ),
          )
          .toList(),
    );
  }

  Widget _buildActions(BuildContext context, ContentDetail detail) {
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: () => launchUrl(
              Uri.parse(detail.url),
              mode: LaunchMode.externalApplication,
            ),
            icon: const Icon(Icons.open_in_new),
            label: const Text('阅读原文'),
          ),
        ),
      ],
    );
  }

  // --- Content Rendering --- (Reused logic from DetailSheet)

  Widget _buildRichContent(
    BuildContext context,
    ContentDetail detail,
    String apiBaseUrl,
    String? apiToken,
  ) {
    final theme = Theme.of(context);
    final storedMap = _getStoredMap(detail);
    final images = _extractAllImages(detail, apiBaseUrl);
    final markdown = _getMarkdownContent(detail);

    if (markdown.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MarkdownBody(
            data: markdown,
            selectable: true,
            onTapLink: (text, href, title) {
              if (href != null)
                launchUrl(
                  Uri.parse(href),
                  mode: LaunchMode.externalApplication,
                );
            },
            styleSheet: _getMarkdownStyle(theme),
            imageBuilder: (uri, title, alt) => _buildMarkdownImage(
              context,
              detail,
              uri,
              alt,
              storedMap,
              apiBaseUrl,
              apiToken,
            ),
          ),
          if (detail.platform.toLowerCase() == 'bilibili')
            _buildBilibiliStats(context, detail),
        ],
      );
    }

    // Default: Description + Grid
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (detail.description != null && detail.description!.isNotEmpty) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              detail.description!,
              style: theme.textTheme.bodyLarge?.copyWith(height: 1.6),
            ),
          ),
          const SizedBox(height: 24),
        ],
        if (images.isNotEmpty)
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: images.length == 1 ? 1 : 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: images.length == 1 ? 16 / 9 : 1.0,
            ),
            itemCount: images.length,
            itemBuilder: (context, index) {
              final url = images[index];
              return ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: index == 0
                    ? Hero(
                        tag: 'content-image-${detail.id}',
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
                      )
                    : CachedNetworkImage(
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
              );
            },
          ),
        if (detail.platform.toLowerCase() == 'bilibili')
          _buildBilibiliStats(context, detail),
      ],
    );
  }

  MarkdownStyleSheet _getMarkdownStyle(ThemeData theme) {
    return MarkdownStyleSheet.fromTheme(theme).copyWith(
      p: theme.textTheme.bodyLarge?.copyWith(
        height: 1.7,
        fontSize: 17,
        color: theme.colorScheme.onSurface.withValues(alpha: 0.9),
      ),
      h1: theme.textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.bold,
        color: theme.colorScheme.primary,
      ),
      h2: theme.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.bold,
        color: theme.colorScheme.secondary,
      ),
      h3: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
      blockSpacing: 24,
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
        horizontal: 20,
        vertical: 16,
      ),
      blockquoteDecoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
        border: Border(
          left: BorderSide(color: theme.colorScheme.secondary, width: 6),
        ),
      ),
      code: theme.textTheme.bodyMedium?.copyWith(
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
        fontFamily: 'monospace',
        color: theme.colorScheme.onSurfaceVariant,
      ),
      codeblockDecoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }

  Widget _buildMarkdownImage(
    BuildContext context,
    ContentDetail detail,
    Uri uri,
    String? alt,
    Map<String, String> storedMap,
    String apiBaseUrl,
    String? apiToken,
  ) {
    final theme = Theme.of(context);
    String url = uri.toString();
    if (storedMap.containsKey(url)) {
      url = _mapUrl(storedMap[url]!, apiBaseUrl);
    } else {
      final cleanUrl = url.split('?').first;
      final match = storedMap.entries.firstWhere(
        (e) => e.key.split('?').first == cleanUrl,
        orElse: () => const MapEntry('', ''),
      );
      url = match.key.isNotEmpty
          ? _mapUrl(match.value, apiBaseUrl)
          : _mapUrl(url, apiBaseUrl);
    }

    final bool isMainImage =
        detail.mediaUrls.isNotEmpty &&
        url == _mapUrl(detail.mediaUrls.first, apiBaseUrl);

    final imageWidget = CachedNetworkImage(
      imageUrl: url,
      httpHeaders: buildImageHeaders(
        imageUrl: url,
        baseUrl: apiBaseUrl,
        apiToken: apiToken,
      ),
      fit: BoxFit.fitWidth,
      placeholder: (c, u) => Container(
        height: 240,
        width: double.infinity,
        color: theme.colorScheme.surfaceContainerHighest,
        child: const Center(child: CircularProgressIndicator()),
      ),
      errorWidget: (c, u, e) => Container(
        height: 160,
        width: double.infinity,
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.3),
        child: const Center(child: Icon(Icons.error_outline)),
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16.0),
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: theme.colorScheme.shadow.withValues(alpha: 0.08),
                  blurRadius: 15,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: isMainImage
                  ? Hero(tag: 'content-image-${detail.id}', child: imageWidget)
                  : imageWidget,
            ),
          ),
          if (alt != null && alt.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                alt,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBilibiliStats(BuildContext context, ContentDetail detail) {
    final stats = detail.extraStats;
    if (stats.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Wrap(
        spacing: 24,
        runSpacing: 12,
        children: [
          if (stats['coin'] != null)
            _LabelStat(label: '投币', value: stats['coin']),
          if (stats['danmaku'] != null)
            _LabelStat(label: '弹幕', value: stats['danmaku']),
          if (stats['favorite'] != null)
            _LabelStat(label: '收藏', value: stats['favorite']),
          if (stats['reply'] != null)
            _LabelStat(label: '评论', value: stats['reply']),
        ],
      ),
    );
  }

  // --- Helper Methods ---

  String _getMarkdownContent(ContentDetail detail) {
    if (detail.rawMetadata != null && detail.rawMetadata!['archive'] != null) {
      return detail.rawMetadata!['archive']['markdown']?.toString() ?? '';
    }
    if (detail.platform.toLowerCase() == 'bilibili' &&
        (detail.description?.contains('![') ?? false)) {
      return detail.description ?? '';
    }
    return '';
  }

  List<_HeaderLine> _extractHeaders(String markdown) {
    final lines = markdown.split('\n');
    final List<_HeaderLine> headers = [];
    final headerRegExp = RegExp(r'^(#{1,6})\s+(.*)$');
    for (var line in lines) {
      final match = headerRegExp.firstMatch(line.trim());
      if (match != null) {
        headers.add(
          _HeaderLine(level: match.group(1)!.length, text: match.group(2)!),
        );
      }
    }
    return headers;
  }

  List<String> _extractAllImages(ContentDetail detail, String apiBaseUrl) {
    // Identical to ContentDetailSheet logic
    final list = <String>{};
    final storedMap = _getStoredMap(detail);
    if (detail.mediaUrls.isNotEmpty) {
      for (var url in detail.mediaUrls) {
        if (url.isEmpty) continue;
        if (storedMap.containsKey(url)) {
          list.add(_mapUrl(storedMap[url]!, apiBaseUrl));
        } else {
          final cleanUrl = url.split('?').first;
          final match = storedMap.entries.firstWhere(
            (e) => e.key.split('?').first == cleanUrl,
            orElse: () => const MapEntry('', ''),
          );
          list.add(
            match.key.isNotEmpty
                ? _mapUrl(match.value, apiBaseUrl)
                : _mapUrl(url, apiBaseUrl),
          );
        }
      }
    }
    return list.toList();
  }

  Map<String, String> _getStoredMap(ContentDetail detail) {
    Map<String, String> storedMap = {};
    try {
      if (detail.rawMetadata != null &&
          detail.rawMetadata!['archive'] != null) {
        final archive = detail.rawMetadata!['archive'];
        final storedImages = archive['stored_images'];
        if (storedImages is List) {
          for (var img in storedImages) {
            if (img is Map && img['orig_url'] != null) {
              String? localPath = img['url'];
              final String? key = img['key'];
              if (key != null) {
                if (key.startsWith('sha256:')) {
                  final hashVal = key.split(':')[1];
                  localPath =
                      'vaultstream/blobs/sha256/${hashVal.substring(0, 2)}/${hashVal.substring(2, 4)}/$hashVal.webp';
                } else {
                  localPath = key;
                }
              }
              if (localPath != null) storedMap[img['orig_url']] = localPath;
            }
          }
        }
      }
    } catch (_) {}
    return storedMap;
  }

  String _mapUrl(String url, String apiBaseUrl) {
    if (url.isEmpty) return url;

    // 0. 处理协议相对路径
    if (url.startsWith('//')) {
      url = 'https:$url';
    }

    // 1. 处理需要代理的外部域名 (针对 B 站、Twitter 图片反盗链)
    if (url.contains('pbs.twimg.com') ||
        url.contains('hdslb.com') ||
        url.contains('bilibili.com')) {
      if (url.contains('/proxy/image?url=')) return url;
      return '$apiBaseUrl/proxy/image?url=${Uri.encodeComponent(url)}';
    }

    // 2. 核心修复：防止重复添加 /media/ 前缀
    // 如果 URL 已经包含 /api/v1/media/，直接返回
    if (url.contains('/api/v1/media/')) return url;

    // 3. 处理包含本地存储路径的情况 (归档的 blobs)
    if (url.contains('blobs/sha256/')) {
      // 3.1 如果已经包含了 /media/ 但没有 /api/v1/
      if (url.startsWith('/media/') || url.contains('/media/')) {
        final path = url.contains('http')
            ? url.substring(url.indexOf('/media/'))
            : url;
        final cleanPath = path.startsWith('/') ? path : '/$path';
        return '$apiBaseUrl$cleanPath';
      }

      // 3.2 如果包含了 /api/v1/ 但没有 /media/
      if (url.contains('/api/v1/')) {
        return url.replaceFirst('/api/v1/', '/api/v1/media/');
      }

      // 3.3 纯相对路径的情况
      final cleanKey = url.startsWith('/') ? url.substring(1) : url;
      return '$apiBaseUrl/media/$cleanKey';
    }

    // 4. 处理其他原本就在 /media 下的普通路径
    if (url.startsWith('/media') || url.contains('/media/')) {
      final path = url.contains('http')
          ? url.substring(url.indexOf('/media/'))
          : url;
      final cleanPath = path.startsWith('/') ? path : '/$path';
      return '$apiBaseUrl$cleanPath';
    }

    return url;
  }

  Widget _getPlatformIcon(String platform, double size) {
    switch (platform.toLowerCase()) {
      case 'twitter':
      case 'x':
        return FaIcon(FontAwesomeIcons.xTwitter, size: size);
      case 'bilibili':
        return FaIcon(
          FontAwesomeIcons.bilibili,
          size: size,
          color: const Color(0xFFFB7299),
        );
      default:
        return Icon(Icons.link, size: size);
    }
  }
}

class _HeaderLine {
  final int level;
  final String text;
  _HeaderLine({required this.level, required this.text});
}

class _LabelStat extends StatelessWidget {
  final String label;
  final dynamic value;
  const _LabelStat({required this.label, required this.value});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.labelSmall),
        Text(
          value.toString(),
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
