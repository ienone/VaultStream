// ignore_for_file: use_build_context_synchronously
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'models/content.dart';
import 'providers/collection_provider.dart';
import 'utils/content_parser.dart';
import 'widgets/detail/gallery/full_screen_gallery.dart';
import 'widgets/detail/layout/article_landscape_layout.dart';
import 'widgets/detail/layout/bilibili_landscape_layout.dart';
import 'widgets/detail/layout/portrait_layout.dart';
import 'widgets/detail/layout/twitter_landscape_layout.dart';
import 'widgets/detail/layout/user_profile_layout.dart';
import 'widgets/dialogs/edit_content_dialog.dart';
import '../../theme/app_theme.dart';
import '../../core/network/api_client.dart';
import '../../core/utils/dynamic_color_helper.dart';

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

  DateTime _lastScrollCheck = DateTime.now();

  void _onScroll() {
    if (!mounted) return;

    // Throttle checks to every 100ms to reduce CPU load from localToGlobal
    final now = DateTime.now();
    if (now.difference(_lastScrollCheck).inMilliseconds < 100) return;
    _lastScrollCheck = now;

    String? currentVisible;
    final List<MapEntry<String, GlobalKey>> entries = _headerKeys.entries
        .toList();

    // Reverse search often finds the currently active header faster for top-down scrolling
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final context = entry.value.currentContext;
      if (context != null) {
        final box = context.findRenderObject() as RenderBox?;
        if (box == null || !box.attached) continue;

        try {
          final offset = box.localToGlobal(Offset.zero).dy;
          // Consider a header "active" when it's near the top of the viewport
          if (offset < 200) {
            currentVisible = entry.key;
          } else {
            // Since headers are sequential, once we find one that's below 200,
            // we don't need to check further ones if we were searching top-down.
            // But wait, the loop is top-down, so we keep updating currentVisible
            // until we hit one that is > 200.
            break;
          }
        } catch (_) {}
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已触发重新解析')));
      ref.invalidate(contentDetailProvider(contentId));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('重新解析请求失败: $e')));
    }
  }

  @override
  void dispose() {
    _contentScrollController.removeListener(_onScroll);
    _imagePageController.dispose();
    _contentScrollController.dispose();
    super.dispose();
  }

  ThemeData _getCustomTheme(ContentDetail? detail, Brightness brightness) {
    final theme = Theme.of(context);

    // 使用 DynamicColorHelper 获取动态颜色
    Color? baseColor;

    // 先尝试从 detail.coverColor 获取
    if (detail?.coverColor != null && detail!.coverColor!.isNotEmpty) {
      baseColor = DynamicColorHelper.getContentColor(
        detail.coverColor,
        context,
      );
    } else if (widget.initialColor != null) {
      // 回退到 initialColor
      baseColor = DynamicColorHelper.getContentColor(
        widget.initialColor,
        context,
      );
    }

    // 如果 baseColor 仍然是 null 或等于系统 primary，表示没有有效的封面色
    final systemPrimary = theme.colorScheme.primary;
    if (baseColor == null || baseColor == systemPrimary) {
      _contentColor = null; // 使用系统主题
      return AppTheme.fromColorScheme(theme.colorScheme, brightness);
    }

    _contentColor = baseColor;

    final customColorScheme = ColorScheme.fromSeed(
      seedColor: baseColor,
      brightness: brightness,
    );

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
        final customTheme = _getCustomTheme(detail, theme.brightness);
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
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(const SnackBar(content: Text('已更新内容')));
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
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(const SnackBar(content: Text('已删除内容')));
                      } catch (e) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(content: Text('删除失败: $e')));
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
            body: SelectionArea(
              child: Builder(
                builder: (context) => _buildResponsiveLayout(
                  context,
                  detail,
                  apiBaseUrl,
                  apiToken,
                ),
              ),
            ),
          ),
        );
      },
      loading: () {
        final customTheme = _getCustomTheme(
          null, // 加载时没有 detail
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
        appBar: AppBar(title: const Text('加载失败')),
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

        if (!isLandscape) {
          return PortraitLayout(
            detail: detail,
            apiBaseUrl: apiBaseUrl,
            apiToken: apiToken,
            headerKeys: _headerKeys,
            contentColor: _contentColor,
          );
        }

        if (detail.contentType == 'user_profile') {
          return UserProfileLayout(
            detail: detail,
            apiBaseUrl: apiBaseUrl,
            apiToken: apiToken,
            onImageTap: (imgs, idx) => _showFullScreenImage(
              context,
              imgs,
              idx,
              apiBaseUrl,
              apiToken,
              detail.id,
            ),
          );
        }

        // 统一文章布局：知乎回答、知乎文章、B站文章/动态
        if (detail.isZhihuAnswer ||
            detail.isZhihuArticle ||
            (detail.isBilibili &&
                (detail.contentType == 'article' ||
                    detail.contentType == 'dynamic'))) {
          final markdown = ContentParser.getMarkdownContent(detail);
          return ArticleLandscapeLayout(
            detail: detail,
            apiBaseUrl: apiBaseUrl,
            apiToken: apiToken,
            contentScrollController: _contentScrollController,
            headerKeys: _headerKeys,
            headers: ContentParser.extractHeaders(markdown),
            activeHeader: _activeHeader,
            contentColor: _contentColor,
          );
        }

        if (detail.isTwitter ||
            detail.isWeibo ||
            detail.isZhihuPin ||
            detail.isZhihuQuestion ||
            detail.isXiaohongshu) {
          return TwitterLandscapeLayout(
            detail: detail,
            apiBaseUrl: apiBaseUrl,
            apiToken: apiToken,
            images: ContentParser.extractAllImages(detail, apiBaseUrl),
            imagePageController: _imagePageController,
            currentImageIndex: _currentImageIndex,
            onImageTap: (idx) => _showFullScreenImage(
              context,
              ContentParser.extractAllImages(detail, apiBaseUrl),
              idx,
              apiBaseUrl,
              apiToken,
              detail.id,
            ),
            onPageChanged: (idx) {
              setState(() {
                _currentImageIndex = idx;
              });
            },
            headerKeys: _headerKeys,
            contentColor: _contentColor,
          );
        }

        // B站视频保持原布局
        if (detail.isBilibili && detail.contentType == 'video') {
          return BilibiliLandscapeLayout(
            detail: detail,
            apiBaseUrl: apiBaseUrl,
            apiToken: apiToken,
            onImageTap: (imgs, idx) => _showFullScreenImage(
              context,
              imgs,
              idx,
              apiBaseUrl,
              apiToken,
              detail.id,
            ),
          );
        }

        return PortraitLayout(
          detail: detail,
          apiBaseUrl: apiBaseUrl,
          apiToken: apiToken,
          headerKeys: _headerKeys,
          contentColor: _contentColor,
        );
      },
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
              contentColor: _contentColor,
              onPageChanged: (index) {
                if (!mounted) return;
                setState(() {
                  _currentImageIndex = index;
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
}
