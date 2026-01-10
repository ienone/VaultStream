// ignore_for_file: use_build_context_synchronously
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:intl/intl.dart';
import 'models/content.dart';
import 'providers/collection_provider.dart';
import 'widgets/edit_content_dialog.dart';
import '../../theme/app_theme.dart';

import '../../core/network/api_client.dart';
import '../../core/network/image_headers.dart';

class ContentDetailPage extends ConsumerStatefulWidget {
  final int contentId;
  final String? initialColor;

  const ContentDetailPage({
    super.key,
    required this.contentId,
    this.initialColor,
  });

  @override
  ConsumerState<ContentDetailPage> createState() => _ContentDetailPageState();
}

class _ContentDetailPageState extends ConsumerState<ContentDetailPage> {
  String? _selectedImageUrl;
  final ScrollController _contentScrollController = ScrollController();
  late PageController _imagePageController;
  int _currentImageIndex = 0;
  final Map<String, GlobalKey> _headerKeys = {};
  String? _activeHeader;
  Color? _contentColor;

  @override
  void initState() {
    super.initState();
    _imagePageController = PageController();
    _contentScrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (!mounted) return;
    String? currentVisible;
    for (var entry in _headerKeys.entries) {
      final context = entry.value.currentContext;
      if (context != null) {
        final box = context.findRenderObject() as RenderBox?;
        if (box == null || !box.attached) continue;

        try {
          final offset = box.localToGlobal(Offset.zero).dy;
          // 这里的阈值可以根据 AppBar 高度调整
          if (offset < 200) {
            currentVisible = entry.key;
          }
        } catch (_) {
          // 防止坐标转换计算在某些过渡状态下报错导致卡死
        }
      }
    }
    if (currentVisible != null && currentVisible != _activeHeader) {
      setState(() => _activeHeader = currentVisible);
    }
  }

  Future<void> _reParseContent(int contentId) async {
    try {
      final dio = ref.read(apiClientProvider);
      await dio.post('/contents/$contentId/re-parse');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已触发重新解析')),
      );
      // Wait a bit or just invalidate. Worker is async.
      ref.invalidate(contentDetailProvider(contentId));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('重新解析请求失败: $e')),
      );
    }
  }

  @override
  void dispose() {
    _contentScrollController.removeListener(_onScroll);
    _imagePageController.dispose();
    _contentScrollController.dispose();
    super.dispose();
  }

  ThemeData _getCustomTheme(String? hexColor, Brightness brightness) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final baseColor = hexColor != null && hexColor.startsWith('#')
        ? AppTheme.parseHexColor(hexColor)
        : null;

    _contentColor = baseColor;

    final customColorScheme = baseColor != null
        ? ColorScheme.fromSeed(seedColor: baseColor, brightness: brightness)
        : colorScheme;

    return AppTheme.fromColorScheme(customColorScheme, brightness);
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(contentDetailProvider(widget.contentId));
    final dio = ref.watch(apiClientProvider);
    final apiBaseUrl = dio.options.baseUrl;
    final apiToken = dio.options.headers['X-API-Token']?.toString();
    final theme = Theme.of(context);

    return detailAsync.when(
      data: (detail) {
        final customTheme = _getCustomTheme(
          detail.coverColor ?? widget.initialColor,
          theme.brightness,
        );
        final colorScheme = customTheme.colorScheme;

        return Theme(
          data: customTheme,
          child: Scaffold(
            backgroundColor: colorScheme.surface,
            appBar: AppBar(
              title: Text(
                detail.isTwitter ? '推文详情' : '内容详情',
                style: customTheme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              backgroundColor: colorScheme.surfaceContainer.withValues(
                alpha: 0.8,
              ),
              elevation: 0,
              surfaceTintColor: Colors.transparent,
              flexibleSpace: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Container(color: Colors.transparent),
                ),
              ),
              leading: Center(
                child: IconButton.filledTonal(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              actions: [
                IconButton.filledTonal(
                  tooltip: '重新解析',
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                  onPressed: () => _reParseContent(detail.id),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: '编辑',
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  onPressed: () async {
                    final result = await showDialog<bool>(
                      context: context,
                      builder: (context) => EditContentDialog(content: detail),
                    );
                    if (result == true) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('已更新内容')),
                      );
                    }
                  },
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: '删除',
                  icon: const Icon(Icons.delete_outline, size: 20),
                  color: colorScheme.error,
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('确认删除'),
                        content: const Text('确定要删除这条内容吗？此操作不可撤销。'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('取消'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            style: TextButton.styleFrom(
                              foregroundColor: colorScheme.error,
                            ),
                            child: const Text('删除'),
                          ),
                        ],
                      ),
                    );

                    if (confirm == true) {
                      if (!context.mounted) return;
                      try {
                        final dio = ref.read(apiClientProvider);
                        await dio.delete('/contents/${detail.id}');
                        if (!context.mounted) return;
                        ref.invalidate(collectionProvider);
                        Navigator.of(context).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('已删除内容')),
                        );
                      } catch (e) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('删除失败: $e')),
                        );
                      }
                    }
                  },
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: '阅读原文',
                  icon: const Icon(Icons.open_in_new, size: 20),
                  onPressed: () => launchUrl(
                    Uri.parse(detail.url),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
                const SizedBox(width: 16),
              ],
            ),
            body: _buildResponsiveLayout(context, detail, apiBaseUrl, apiToken),
          ),
        );
      },
      loading: () {
        final customTheme = _getCustomTheme(
          widget.initialColor,
          theme.brightness,
        );
        final colorScheme = customTheme.colorScheme;

        return Theme(
          data: customTheme,
          child: Scaffold(
            backgroundColor: colorScheme.surface,
            appBar: AppBar(
              title: const Text('加载中...'),
              backgroundColor: colorScheme.surface.withValues(alpha: 0.8),
              elevation: 0,
              surfaceTintColor: Colors.transparent,
              flexibleSpace: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(color: Colors.transparent),
                ),
              ),
            ),
            body: const Center(child: CircularProgressIndicator()),
          ),
        );
      },
      error: (err, stack) => Scaffold(
        appBar: AppBar(
          title: const Text('加载失败'),
          backgroundColor: theme.colorScheme.surface.withValues(alpha: 0.8),
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          flexibleSpace: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(color: Colors.transparent),
            ),
          ),
        ),
        body: Center(
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
        final bool hasMarkdown = _hasMarkdown(detail);

        if (!isLandscape) {
          return _buildPortraitLayout(context, detail, apiBaseUrl, apiToken);
        }

        if (detail.isTwitter) {
          return _buildTwitterLandscape(context, detail, apiBaseUrl, apiToken);
        }

        if (hasMarkdown) {
          return _buildMarkdownLandscape(context, detail, apiBaseUrl, apiToken);
        }

        if (detail.isBilibili) {
          return _buildBilibiliLandscape(context, detail, apiBaseUrl, apiToken);
        }

        return _buildDefaultLandscape(context, detail, apiBaseUrl, apiToken);
      },
    );
  }

  bool _hasMarkdown(ContentDetail detail) {
    final archive = detail.rawMetadata?['archive'];
    if (archive != null) {
      final md = archive['markdown'];
      if (md != null && md.toString().isNotEmpty) return true;
    }
    return detail.isBilibili && (detail.description?.contains('![') ?? false);
  }

  // --- Twitter Red-style Layout ---

  Widget _buildTwitterLandscape(
    BuildContext context,
    ContentDetail detail,
    String apiBaseUrl,
    String? apiToken,
  ) {
    final images = _extractAllImages(detail, apiBaseUrl);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      children: [
        // Left: Media Area (Main Content)
        Expanded(
          flex: 6,
          child: Container(
            color: colorScheme.surface,
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
        // Right: Content Info Area (Supporting Pane)
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
      _currentImageIndex = 0;
    }

    return Column(
      children: [
        // Main Media View (Task 4)
        Expanded(
          child: Stack(
            children: [
              PageView.builder(
                controller: _imagePageController,
                itemCount: images.length,
                onPageChanged: (index) {
                  setState(() {
                    _currentImageIndex = index;
                    _selectedImageUrl = images[index];
                  });
                },
                itemBuilder: (context, index) {
                  final img = images[index];
                  return Center(
                    child: GestureDetector(
                      onTap: () => _showFullScreenImage(
                        context,
                        images,
                        index,
                        apiBaseUrl,
                        apiToken,
                        detail.id,
                      ),
                      child: InteractiveViewer(
                        minScale: 1.0,
                        maxScale: 3.0,
                        child: Hero(
                          tag: index == 0
                              ? 'content-image-${detail.id}'
                              : 'image-$index-${detail.id}',
                          child: CachedNetworkImage(
                            imageUrl: img,
                            httpHeaders: buildImageHeaders(
                              imageUrl: img,
                              baseUrl: apiBaseUrl,
                              apiToken: apiToken,
                            ),
                            fit: BoxFit.contain,
                            placeholder: (c, u) => const Center(
                              child: CircularProgressIndicator(),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              // Navigation Buttons
              if (images.length > 1) ...[
                if (_currentImageIndex > 0)
                  Positioned(
                    left: 16,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: IconButton.filledTonal(
                        icon: const Icon(Icons.chevron_left),
                        onPressed: () {
                          _imagePageController.previousPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          );
                        },
                      ),
                    ),
                  ),
                if (_currentImageIndex < images.length - 1)
                  Positioned(
                    right: 16,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: IconButton.filledTonal(
                        icon: const Icon(Icons.chevron_right),
                        onPressed: () {
                          _imagePageController.nextPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          );
                        },
                      ),
                    ),
                  ),
              ],
              // Counter overlay
              if (images.length > 1)
                Positioned(
                  top: 16,
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${_currentImageIndex + 1} / ${images.length}',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ),
            ],
          ),
        ),
        // Thumbnails grid
        if (images.length > 1)
          Container(
            height: 90,
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: images.length,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              itemBuilder: (context, index) {
                final img = images[index];
                final isSelected = index == _currentImageIndex;
                return GestureDetector(
                  onTap: () {
                    _imagePageController.animateToPage(
                      index,
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.fastOutSlowIn,
                    );
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: isSelected ? 120 : 64, // M3E: Expanding effect
                    height: 64,
                    margin: const EdgeInsets.only(right: 12),
                    decoration: BoxDecoration(
                      border: isSelected
                          ? Border.all(
                              color: Theme.of(context).colorScheme.primary,
                              width: 3,
                            )
                          : Border.all(
                              color: Theme.of(context)
                                  .colorScheme
                                  .outlineVariant
                                  .withValues(alpha: 0.5),
                              width: 1,
                            ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: Theme.of(
                                  context,
                                ).colorScheme.primary.withValues(alpha: 0.2),
                                blurRadius: 8,
                                spreadRadius: 2,
                              ),
                            ]
                          : null,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(13),
                      child: CachedNetworkImage(
                        imageUrl: img,
                        httpHeaders: buildImageHeaders(
                          imageUrl: img,
                          baseUrl: apiBaseUrl,
                          apiToken: apiToken,
                        ),
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHighest,
                        ),
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
            _FullScreenGallery(
              images: images,
              initialIndex: initialIndex,
              apiBaseUrl: apiBaseUrl,
              apiToken: apiToken,
              contentId: contentId,
              contentColor: _contentColor,
              onPageChanged: (index) {
                if (!mounted) return;
                setState(() {
                  _currentImageIndex = index;
                  if (images.isNotEmpty) {
                    _selectedImageUrl = images[index];
                  }
                });
                if (_imagePageController.hasClients) {
                  _imagePageController.jumpToPage(index);
                }
              },
            ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  Widget _buildTwitterSideInfo(
    BuildContext context,
    ContentDetail detail,
    String apiBaseUrl,
    String? apiToken,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          left: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Container(
          decoration: BoxDecoration(
            color: isDark
                ? colorScheme.surfaceContainer
                : colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(28),
            border: isDark
                ? Border.all(
                    color: Colors.white.withValues(alpha: 0.05),
                    width: 1,
                  )
                : null,
            boxShadow: isDark
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ]
                : null,
          ),
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildAuthorHeader(context, detail),
              const SizedBox(height: 32),
              if (detail.description != null)
                SelectableText(
                  detail.description!,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    height: 1.5,
                    letterSpacing: 0.1,
                  ),
                ),
              const SizedBox(height: 32),
              if (detail.publishedAt != null)
                Text(
                  DateFormat(
                    'a hh:mm · yyyy年MM月dd日',
                  ).format(detail.publishedAt!.toLocal()),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.outline,
                  ),
                ),
              const SizedBox(height: 48),
              _buildUnifiedStats(context, detail),
              const SizedBox(height: 48),
              Text(
                '关联标签',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.primary,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 16),
              _buildTags(context, detail),
            ],
          ),
        ),
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left: Main Content
        Expanded(
          flex: 7,
          child: Container(
            color: colorScheme.surface,
            child: SingleChildScrollView(
              controller: _contentScrollController,
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 40),
              child: _buildRichContent(context, detail, apiBaseUrl, apiToken),
            ),
          ),
        ),
        // Right: TOC (Supporting Pane)
        if (headers.isNotEmpty)
          Container(
            width: 320,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              border: Border(
                left: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.3),
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
    final colorScheme = theme.colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 40, 24, 16),
          child: Row(
            children: [
              Icon(Icons.toc_rounded, size: 24, color: colorScheme.primary),
              const SizedBox(width: 12),
              Text(
                '目录',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.0,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: headers.length,
            itemBuilder: (context, index) {
              final h = headers[index];
              final isSelected = _activeHeader == h.uniqueId;
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: InkWell(
                  onTap: () {
                    final key = _headerKeys[h.uniqueId];
                    if (key != null && key.currentContext != null) {
                      Scrollable.ensureVisible(
                        key.currentContext!,
                        duration: const Duration(milliseconds: 600),
                        curve: Curves.fastOutSlowIn,
                      );
                    }
                  },
                  borderRadius: BorderRadius.circular(20),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    padding: EdgeInsets.fromLTRB(
                      (h.level - 1) * 16.0 + 16.0,
                      14,
                      16,
                      14,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected ? colorScheme.primaryContainer : null,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      h.text,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: isSelected
                            ? colorScheme.onPrimaryContainer
                            : (h.level == 1
                                  ? colorScheme.onSurface
                                  : colorScheme.onSurfaceVariant),
                        fontWeight: isSelected || h.level == 1
                            ? FontWeight.bold
                            : FontWeight.normal,
                        height: 1.4,
                      ),
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

  // --- Default & Portrait ---

  Widget _buildPortraitLayout(
    BuildContext context,
    ContentDetail detail,
    String apiBaseUrl,
    String? apiToken,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(
              color: isDark
                  ? colorScheme.surfaceContainer
                  : colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(28),
              border: isDark
                  ? Border.all(
                      color: Colors.white.withValues(alpha: 0.05),
                      width: 1,
                    )
                  : null,
              boxShadow: isDark
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildAuthorHeader(context, detail),
                const SizedBox(height: 24),
                if (!detail.isTwitter && (detail.title != null && detail.title!.isNotEmpty))
                  Text(
                    detail.title ?? '无标题内容',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      height: 1.2,
                      letterSpacing: -0.5,
                      color: colorScheme.onSurface,
                    ),
                  ),
                const SizedBox(height: 24),
                _buildUnifiedStats(context, detail),
                const SizedBox(height: 16),
                if (detail.isBilibili && detail.platformId != null)
                  _buildBvidCard(context, detail),
                const SizedBox(height: 16),
                _buildTags(context, detail),
              ],
            ),
          ),
          const SizedBox(height: 32),
          _buildRichContent(context, detail, apiBaseUrl, apiToken),
          const SizedBox(height: 48),
        ],
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
        // Left: Media Area (Main Content)
        Expanded(
          flex: 6,
          child: Container(
            color: colorScheme.surface,
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
                          child: GestureDetector(
                            onTap: () => _showFullScreenImage(
                              context,
                              images,
                              0,
                              apiBaseUrl,
                              apiToken,
                              detail.id,
                            ),
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
                          ),
                        )
                      : ListView.builder(
                          itemCount: images.length,
                          padding: const EdgeInsets.all(24),
                          itemBuilder: (context, index) => Padding(
                            padding: const EdgeInsets.only(bottom: 24),
                            child: GestureDetector(
                              onTap: () => _showFullScreenImage(
                                context,
                                images,
                                index,
                                apiBaseUrl,
                                apiToken,
                                detail.id,
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(
                                  24,
                                ), // M3E: Larger rounded corners
                                child: Hero(
                                  tag: index == 0
                                      ? 'content-image-${detail.id}'
                                      : 'image-$index-${detail.id}',
                                  child: CachedNetworkImage(
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
                            ),
                          ),
                        )),
          ),
        ),
        // Right: Info Area (Supporting Pane)
        Expanded(
          flex: 4,
          child: Container(
            decoration: BoxDecoration(
              color: colorScheme.surface,
              border: Border(
                left: BorderSide(color: colorScheme.outlineVariant),
              ),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Container(
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(28),
                ),
                padding: const EdgeInsets.all(28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildAuthorHeader(context, detail),
                    const SizedBox(height: 32),
                    Text(
                      detail.title ?? '无标题内容',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 24),
                    _buildUnifiedStats(context, detail),
                    const SizedBox(height: 16),
                    if (detail.platformId != null)
                      _buildBvidCard(context, detail),
                    const SizedBox(height: 24),
                    _buildTags(context, detail),
                    const SizedBox(height: 40),
                    if (detail.description != null &&
                        detail.description!.isNotEmpty &&
                        detail.description != '-') ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: colorScheme.primary.withValues(alpha: 0.1),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.notes_rounded,
                                  size: 18,
                                  color: colorScheme.primary,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '简介',
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    color: colorScheme.primary,
                                    letterSpacing: 1.0,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              detail.description!,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                height: 1.8,
                                fontSize: 15,
                                color: colorScheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
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
    final colorScheme = theme.colorScheme;
    final bool isBilibili = detail.isBilibili;

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: isBilibili
                  ? [const Color(0xFFFB7299), const Color(0xFFFF9DB5)]
                  : [colorScheme.primary, colorScheme.tertiary],
            ),
          ),
          child: CircleAvatar(
            radius: 20,
            backgroundColor: colorScheme.surface,
            child: Text(
              (detail.authorName ?? '?').substring(0, 1).toUpperCase(),
              style: TextStyle(
                color: isBilibili
                    ? const Color(0xFFFB7299)
                    : colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  detail.authorName ?? '未知作者',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(width: 8),
                _getPlatformIcon(detail.platform, 14),
              ],
            ),
            const SizedBox(height: 2),
            if (detail.publishedAt != null)
              Text(
                DateFormat(
                  'yyyy-MM-dd HH:mm',
                ).format(detail.publishedAt!.toLocal()),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.outline,
                  letterSpacing: 0.5,
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildUnifiedStats(BuildContext context, ContentDetail detail) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final stats = detail.extraStats;
    final bool isBilibili = detail.isBilibili;

    final List<Widget> items = [];

    // Views
    items.add(
      _buildUnifiedStatItem(
        context,
        Icons.visibility_outlined,
        '查看',
        detail.viewCount.toString(),
      ),
    );

    // Likes
    items.add(
      _buildUnifiedStatItem(
        context,
        Icons.favorite_border,
        '点赞',
        detail.likeCount.toString(),
      ),
    );

    // Collects
    if (detail.collectCount > 0 || isBilibili) {
      items.add(
        _buildUnifiedStatItem(
          context,
          Icons.star_border,
          '收藏',
          (detail.collectCount > 0
                  ? detail.collectCount
                  : (stats['favorite'] ?? 0))
              .toString(),
        ),
      );
    }

    // Comments / Replies
    if (detail.commentCount > 0 || isBilibili) {
      items.add(
        _buildUnifiedStatItem(
          context,
          Icons.chat_bubble_outline,
          '评论',
          (detail.commentCount > 0
                  ? detail.commentCount
                  : (stats['reply'] ?? 0))
              .toString(),
        ),
      );
    }

    // Bilibili specific
    if (isBilibili) {
      if (stats['coin'] != null) {
        items.add(
          _buildUnifiedStatItem(
            context,
            Icons.monetization_on_rounded,
            '投币',
            stats['coin'].toString(),
          ),
        );
      }
      if (stats['danmaku'] != null) {
        items.add(
          _buildUnifiedStatItem(
            context,
            Icons.subtitles_rounded,
            '弹幕',
            stats['danmaku'].toString(),
          ),
        );
      }
    }

    if (items.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(32), // M3E Expressive: Large radius
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Target 3 columns for 6 items (2x3), but responsive fallback to 2
          final int crossAxisCount = constraints.maxWidth > 360 ? 3 : 2;
          const double horizontalSpacing = 20.0;
          final double itemWidth =
              (constraints.maxWidth -
                  (horizontalSpacing * (crossAxisCount - 1))) /
              crossAxisCount;

          return Wrap(
            spacing: horizontalSpacing,
            runSpacing: 24,
            children: items
                .map((item) => SizedBox(width: itemWidth, child: item))
                .toList(),
          );
        },
      ),
    );
  }

  Widget _buildUnifiedStatItem(
    BuildContext context,
    IconData icon,
    String label,
    String value,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 18, color: colorScheme.onPrimaryContainer),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                  color: colorScheme.onSurface,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.outline,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBvidCard(BuildContext context, ContentDetail detail) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    if (detail.platformId == null || !detail.isBilibili) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colorScheme.secondary.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.video_library_outlined,
            size: 20,
            color: colorScheme.secondary,
          ),
          const SizedBox(width: 12),
          Text(
            'BV号: ${detail.platformId}',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: colorScheme.onSecondaryContainer,
            ),
          ),
          const SizedBox(width: 16),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                Clipboard.setData(ClipboardData(text: detail.platformId!));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('已复制 BV 号'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Icon(Icons.copy, size: 16, color: colorScheme.primary),
              ),
            ),
          ),
        ],
      ),
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

  // --- Content Rendering --- (Reused logic from DetailSheet)

  Widget _buildRichContent(
    BuildContext context,
    ContentDetail detail,
    String apiBaseUrl,
    String? apiToken, {
    bool useHero = true,
  }) {
    final theme = Theme.of(context);
    final storedMap = _getStoredMap(detail);
    final images = _extractAllImages(detail, apiBaseUrl);
    final markdown = _getMarkdownContent(detail);

    // 用于跟踪 Hero 标签是否已被使用，防止重复导致卡死
    final Set<String> usedHeroTags = {};

    if (markdown.isNotEmpty) {
      final style = _getMarkdownStyle(theme);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MarkdownBody(
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
              'h1': _HeaderBuilder(_headerKeys, style.h1),
              'h2': _HeaderBuilder(_headerKeys, style.h2),
              'h3': _HeaderBuilder(_headerKeys, style.h3),
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
              borderRadius: BorderRadius.circular(24),
            ),
            child: Text(
              detail.description!,
              style: theme.textTheme.bodyLarge?.copyWith(height: 1.6),
            ),
          ),
          const SizedBox(height: 24),
        ],
        if (images.isNotEmpty)
          if (images.length == 1)
            GestureDetector(
              onTap: () => _showFullScreenImage(
                context,
                images,
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
                    imageUrl: images.first,
                    httpHeaders: buildImageHeaders(
                      imageUrl: images.first,
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
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.0,
              ),
              itemCount: images.length,
              itemBuilder: (context, index) {
                final url = images[index];
                return GestureDetector(
                  onTap: () => _showFullScreenImage(
                    context,
                    images,
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
        if (detail.platform.toLowerCase() == 'bilibili')
          _buildBilibiliStats(context, detail),
      ],
    );
  }

  MarkdownStyleSheet _getMarkdownStyle(ThemeData theme) {
    return MarkdownStyleSheet.fromTheme(theme).copyWith(
      p: theme.textTheme.bodyLarge?.copyWith(
        height: 1.8, // Increased line height for better reading
        fontSize: 18,
        letterSpacing: 0.1,
        color: theme.colorScheme.onSurface.withValues(alpha: 0.95),
      ),
      h1: theme.textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w900,
        letterSpacing: -0.5,
        color: theme.colorScheme.primary,
        height: 1.4,
      ),
      h2: theme.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w900,
        color: theme.colorScheme.secondary,
        height: 1.4,
      ),
      h3: theme.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w900,
        height: 1.4,
      ),
      blockSpacing: 28,
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
        color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.25),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(32),
          topRight: Radius.circular(32),
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(8), // M3E: Asymmetric
        ),
        border: Border(
          left: BorderSide(color: theme.colorScheme.secondary, width: 8),
        ),
      ),
      code: theme.textTheme.bodyMedium?.copyWith(
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
        fontFamily: 'monospace',
        color: theme.colorScheme.onSurfaceVariant,
      ),
      codeblockDecoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(20),
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
    String? apiToken, {
    bool useHero = true,
    Set<String>? usedHeroTags,
  }) {
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

    final String heroTag = 'content-image-${detail.id}';
    final bool isMainImage =
        useHero &&
        detail.mediaUrls.isNotEmpty &&
        url == _mapUrl(detail.mediaUrls.first, apiBaseUrl) &&
        (usedHeroTags == null || !usedHeroTags.contains(heroTag));

    if (isMainImage && usedHeroTags != null) {
      usedHeroTags.add(heroTag);
    }

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
      padding: const EdgeInsets.symmetric(vertical: 24.0),
      child: Column(
        children: [
          GestureDetector(
            onTap: () {
              final images = _extractAllImages(detail, apiBaseUrl);
              final initialIndex = images.indexOf(url);
              _showFullScreenImage(
                context,
                images.isNotEmpty ? images : [url],
                initialIndex >= 0 ? initialIndex : 0,
                apiBaseUrl,
                apiToken,
                detail.id,
              );
            },
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: theme.colorScheme.shadow.withValues(alpha: 0.08),
                    blurRadius: 15,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: isMainImage
                    ? Hero(
                        tag: 'content-image-${detail.id}',
                        child: imageWidget,
                      )
                    : imageWidget,
              ),
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
    return const SizedBox.shrink(); // Integrated into _buildUnifiedStats
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
    final Map<String, int> counts = {};

    for (var line in lines) {
      final match = headerRegExp.firstMatch(line.trim());
      if (match != null) {
        final text = match.group(2)!;
        final count = counts[text] ?? 0;
        counts[text] = count + 1;
        final uniqueId = count == 0 ? text : '$text-$count';

        headers.add(
          _HeaderLine(
            level: match.group(1)!.length,
            text: text,
            uniqueId: uniqueId,
          ),
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
  final String uniqueId;
  _HeaderLine({
    required this.level,
    required this.text,
    required this.uniqueId,
  });
}

class _HeaderBuilder extends MarkdownElementBuilder {
  final Map<String, GlobalKey> keys;
  final TextStyle? style;
  final Map<String, int> _occurrenceCount = {};

  _HeaderBuilder(this.keys, this.style);

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final text = element.textContent;
    // 为重复的标题生成唯一标识符，防止 GlobalKey 冲突
    final count = _occurrenceCount[text] ?? 0;
    _occurrenceCount[text] = count + 1;
    final uniqueKey = count == 0 ? text : '$text-$count';

    final key = keys.putIfAbsent(uniqueKey, () => GlobalKey());
    return Container(
      key: key,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(text, style: style ?? preferredStyle),
    );
  }
}

class _FullScreenGallery extends StatefulWidget {
  final List<String> images;
  final int initialIndex;
  final String apiBaseUrl;
  final String? apiToken;
  final int contentId;
  final Color? contentColor;
  final Function(int)? onPageChanged;

  const _FullScreenGallery({
    required this.images,
    required this.initialIndex,
    required this.apiBaseUrl,
    this.apiToken,
    required this.contentId,
    this.contentColor,
    this.onPageChanged,
  });

  @override
  State<_FullScreenGallery> createState() => _FullScreenGalleryState();
}

class _FullScreenGalleryState extends State<_FullScreenGallery> {
  late int _currentIndex;
  late PageController _controller;
  double _dragOffset = 0;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _controller = PageController(initialPage: widget.initialIndex);
  }

  String _getHeroTag(int index) {
    return index == 0
        ? 'content-image-${widget.contentId}'
        : 'image-$index-${widget.contentId}';
  }

  @override
  Widget build(BuildContext context) {
    final opacity = (1 - (_dragOffset.abs() / 300)).clamp(0.0, 1.0);
    final theme = Theme.of(context);
    final colorScheme = widget.contentColor != null
        ? ColorScheme.fromSeed(
            seedColor: widget.contentColor!,
            brightness: theme.brightness,
          )
        : theme.colorScheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Glass Background
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(
                  color: Colors.black.withValues(alpha: 0.6 * opacity),
                ),
              ),
            ),
          ),
          // Images
          GestureDetector(
            onVerticalDragUpdate: (details) {
              setState(() {
                _dragOffset += details.primaryDelta!;
              });
            },
            onVerticalDragEnd: (details) {
              if (_dragOffset.abs() > 100) {
                Navigator.pop(context);
              } else {
                setState(() {
                  _dragOffset = 0;
                });
              }
            },
            child: Transform.translate(
              offset: Offset(0, _dragOffset),
              child: PageView.builder(
                controller: _controller,
                itemCount: widget.images.length,
                onPageChanged: (i) {
                  setState(() => _currentIndex = i);
                  widget.onPageChanged?.call(i);
                },
                itemBuilder: (context, index) {
                  return GestureDetector(
                    onTap: () => Navigator.pop(context),
                    behavior: HitTestBehavior.opaque,
                    child: InteractiveViewer(
                      minScale: 1.0,
                      maxScale: 4.0,
                      child: Center(
                        child: GestureDetector(
                          onTap: () {
                            // Consume tap on image to prevent closing
                          },
                          child: Hero(
                            tag: _getHeroTag(index),
                            child: CachedNetworkImage(
                              imageUrl: widget.images[index],
                              httpHeaders: buildImageHeaders(
                                imageUrl: widget.images[index],
                                baseUrl: widget.apiBaseUrl,
                                apiToken: widget.apiToken,
                              ),
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

          // Capsule Toolbar
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            left: 0,
            right: 0,
            child: Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(32),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer.withValues(
                        alpha: 0.4,
                      ),
                      borderRadius: BorderRadius.circular(32),
                      border: Border.all(
                        color: colorScheme.onPrimaryContainer.withValues(
                          alpha: 0.2,
                        ),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${_currentIndex + 1} / ${widget.images.length}',
                          style: TextStyle(
                            color: colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.1,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          width: 1,
                          height: 16,
                          color: colorScheme.onPrimaryContainer.withValues(
                            alpha: 0.2,
                          ),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          constraints: const BoxConstraints(),
                          padding: const EdgeInsets.all(4),
                          icon: Icon(
                            Icons.download_rounded,
                            color: colorScheme.onPrimaryContainer,
                            size: 20,
                          ),
                          onPressed: () {
                            // TODO: Implement download
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('下载功能正在开发中...'),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Navigation buttons (for desktop/large screen)
          if (widget.images.length > 1) ...[
            if (_currentIndex > 0)
              Positioned(
                left: 20,
                top: 0,
                bottom: 0,
                child: Center(
                  child: IconButton.filledTonal(
                    style: IconButton.styleFrom(
                      backgroundColor: colorScheme.primaryContainer.withValues(
                        alpha: 0.4,
                      ),
                      foregroundColor: colorScheme.onPrimaryContainer,
                    ),
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () {
                      _controller.previousPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );
                    },
                  ),
                ),
              ),
            if (_currentIndex < widget.images.length - 1)
              Positioned(
                right: 20,
                top: 0,
                bottom: 0,
                child: Center(
                  child: IconButton.filledTonal(
                    style: IconButton.styleFrom(
                      backgroundColor: colorScheme.primaryContainer.withValues(
                        alpha: 0.4,
                      ),
                      foregroundColor: colorScheme.onPrimaryContainer,
                    ),
                    icon: const Icon(Icons.chevron_right),
                    onPressed: () {
                      _controller.nextPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );
                    },
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
