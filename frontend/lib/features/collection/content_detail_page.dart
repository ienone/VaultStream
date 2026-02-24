// ignore_for_file: use_build_context_synchronously
import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/constants/platform_constants.dart';
import '../../core/network/sse_service.dart';
import 'models/content.dart';
import 'providers/collection_provider.dart';
import 'utils/content_parser.dart';
import 'widgets/detail/gallery/full_screen_gallery.dart';
import 'widgets/detail/layout/article_landscape_layout.dart';
import 'widgets/detail/layout/gallery_landscape_layout.dart';
import 'widgets/detail/layout/portrait_layout.dart';
import 'widgets/detail/layout/video_landscape_layout.dart';
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
  bool _isGeneratingSummary = false;
  StreamSubscription<SseEvent>? _sseSub;

  @override
  void initState() {
    super.initState();
    _imagePageController = PageController();
    _contentScrollController.addListener(_onScroll);
    _bindRealtimeEvents();
  }

  void _bindRealtimeEvents() {
    ref.read(sseServiceProvider.notifier);
    _sseSub?.cancel();
    _sseSub = SseEventBus().eventStream.listen((event) {
      if (!mounted) return;

      if (event.type == 'content_updated') {
        final data = event.data;
        if (data['id'] == widget.contentId) {
          ref.invalidate(contentDetailProvider(widget.contentId));
          // 如果正在生成摘要，收到更新事件说明生成已完成
          if (_isGeneratingSummary) {
            setState(() => _isGeneratingSummary = false);
          }
        }
      }
    });
  }

  DateTime _lastScrollCheck = DateTime.now();

  void _onScroll() {
    if (!mounted) return;
    final now = DateTime.now();
    if (now.difference(_lastScrollCheck).inMilliseconds < 100) return;
    _lastScrollCheck = now;

    String? currentVisible;
    final List<MapEntry<String, GlobalKey>> entries = _headerKeys.entries
        .toList();

    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final context = entry.value.currentContext;
      if (context != null) {
        final box = context.findRenderObject() as RenderBox?;
        if (box == null || !box.attached) continue;
        try {
          final offset = box.localToGlobal(Offset.zero).dy;
          if (offset < 200) {
            currentVisible = entry.key;
          } else {
            break;
          }
        } catch (_) {}
      }
    }

    if (currentVisible != null && currentVisible != _activeHeader) {
      setState(() => _activeHeader = currentVisible);
    }
  }

  @override
  void dispose() {
    _sseSub?.cancel();
    _contentScrollController.removeListener(_onScroll);
    _imagePageController.dispose();
    _contentScrollController.dispose();
    super.dispose();
  }

  ThemeData _getCustomTheme(ContentDetail? detail, Brightness brightness) {
    final theme = Theme.of(context);
    Color? baseColor;
    if (detail?.coverColor != null && detail!.coverColor!.isNotEmpty) {
      baseColor = DynamicColorHelper.getContentColor(
        detail.coverColor,
        context,
      );
    } else if (widget.initialColor != null) {
      baseColor = DynamicColorHelper.getContentColor(
        widget.initialColor,
        context,
      );
    }
    final systemPrimary = theme.colorScheme.primary;
    if (baseColor == null || baseColor == systemPrimary) {
      _contentColor = null;
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
          child: Stack(
            children: [
              Positioned.fill(
                child: Hero(
                  tag: 'card-bg-${widget.contentId}',
                  child: Material(
                    color: colorScheme.surface,
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
              Scaffold(
                backgroundColor: Colors.transparent,
                appBar: AppBar(
                  title: Text(
                    detail.platform.isTwitter ? '推文详情' : '内容详情',
                    style: customTheme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  backgroundColor: colorScheme.surface.withValues(alpha: 0.8),
                  elevation: 0,
                  scrolledUnderElevation: 0,
                  flexibleSpace: ClipRect(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                      child: Container(color: Colors.transparent),
                    ),
                  ),
                  leading: Center(
                    child: IconButton.filledTonal(
                      icon: const Icon(Icons.arrow_back_rounded),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                  actions: [
                    _buildActionButtons(detail, colorScheme),
                    const SizedBox(width: 16),
                  ],
                ),
                body: Material(
                  color: Colors.transparent,
                  child: SelectionArea(
                    child: _buildResponsiveLayout(
                      context,
                      detail,
                      apiBaseUrl,
                      apiToken,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ).animate().fadeIn(duration: 300.ms);
      },
      loading: () => _buildLoadingState(theme),
      error: (err, stack) => _buildErrorState(err),
    );
  }

  Widget _buildActionButtons(ContentDetail detail, ColorScheme colorScheme) {
    return Row(
      children: [
        IconButton.filledTonal(
          tooltip: detail.summary == null || detail.summary!.isEmpty
              ? '生成摘要'
              : '更新摘要',
          icon: _isGeneratingSummary
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.auto_awesome_rounded, size: 20),
          onPressed: _isGeneratingSummary
              ? null
              : () => _generateSummary(detail.id),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          tooltip: '重新解析',
          icon: const Icon(Icons.refresh_rounded, size: 20),
          onPressed: () => _reParseContent(detail.id),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          tooltip: '编辑',
          icon: const Icon(Icons.edit_outlined, size: 20),
          onPressed: () => _showEditDialog(detail),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          tooltip: '删除',
          icon: const Icon(Icons.delete_outline_rounded, size: 20),
          color: colorScheme.error,
          onPressed: () => _confirmDelete(detail, colorScheme),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          tooltip: '阅读原文',
          icon: const Icon(Icons.open_in_new_rounded, size: 20),
          onPressed: () => launchUrl(
            Uri.parse(detail.url),
            mode: LaunchMode.externalApplication,
          ),
        ),
      ],
    );
  }

  Widget _buildLoadingState(ThemeData theme) {
    final customTheme = _getCustomTheme(null, theme.brightness);
    final colorScheme = customTheme.colorScheme;
    return Theme(
      data: customTheme,
      child: Scaffold(
        backgroundColor: colorScheme.surface,
        appBar: AppBar(
          title: const Text('加载中...'),
          backgroundColor: colorScheme.surface.withValues(alpha: 0.8),
          elevation: 0,
        ),
        body: const Center(child: CircularProgressIndicator()),
      ),
    );
  }

  Widget _buildErrorState(Object err) {
    return Scaffold(
      appBar: AppBar(title: const Text('加载失败')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 48,
              color: Colors.red,
            ),
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

        // 竖屏统一使用 PortraitLayout
        if (!isLandscape) {
          return PortraitLayout(
            detail: detail,
            apiBaseUrl: apiBaseUrl,
            apiToken: apiToken,
            headerKeys: _headerKeys,
            contentColor: _contentColor,
          );
        }

        // 特殊类型：用户主页
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

        // 基于 layoutType 分发（内容驱动）
        final layoutType = detail.layoutType;

        switch (layoutType) {
          case 'article':
            // 长文布局 - 适用于文章、回答等
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

          case 'gallery':
            // 画廊布局 - 适用于微博、推文、小红书等
            return GalleryLandscapeLayout(
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
                if (!mounted) return;
                setState(() => _currentImageIndex = idx);
                if (_imagePageController.hasClients &&
                    _imagePageController.page?.round() != idx) {
                  _imagePageController.jumpToPage(idx);
                }
              },
              headerKeys: _headerKeys,
              contentColor: _contentColor,
            );

          case 'video':
            // 视频布局 - 使用VideoLandscapeLayout（仅封面）
            if (detail.platform.isBilibili) {
              return VideoLandscapeLayout(
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
            // 其他平台视频暂时用Gallery布局
            return GalleryLandscapeLayout(
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
                if (!mounted) return;
                setState(() => _currentImageIndex = idx);
                if (_imagePageController.hasClients &&
                    _imagePageController.page?.round() != idx) {
                  _imagePageController.jumpToPage(idx);
                }
              },
              headerKeys: _headerKeys,
              contentColor: _contentColor,
            );

          default:
            // 默认使用Article布局
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
    // Sync background immediately
    setState(() => _currentImageIndex = initialIndex);
    if (_imagePageController.hasClients) {
      _imagePageController.jumpToPage(initialIndex);
    }

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
                setState(() => _currentImageIndex = index);
                if (_imagePageController.hasClients) {
                  _imagePageController.animateToPage(
                    index,
                    duration: const Duration(milliseconds: 100),
                    curve: Curves.easeInOut,
                  );
                }
              },
            ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  Future<void> _reParseContent(int contentId) async {
    try {
      await ref.read(apiClientProvider).post('/contents/$contentId/re-parse');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已触发重新解析')));
      ref.invalidate(contentDetailProvider(contentId));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('请求失败: $e')));
    }
  }

  Future<void> _generateSummary(int contentId) async {
    setState(() => _isGeneratingSummary = true);
    try {
      await ref
          .read(apiClientProvider)
          .post(
            '/contents/$contentId/generate-summary',
            queryParameters: {'force': true},
          );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('摘要已更新')));
      }
      ref.invalidate(contentDetailProvider(contentId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('摘要生成失败: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isGeneratingSummary = false);
      }
    }
  }

  void _showEditDialog(ContentDetail detail) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => EditContentDialog(content: detail),
    );
    if (result == true) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('内容已更新')));
      ref.invalidate(contentDetailProvider(detail.id));
    }
  }

  void _confirmDelete(ContentDetail detail, ColorScheme colorScheme) async {
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
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: colorScheme.error),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await ref.read(apiClientProvider).delete('/contents/${detail.id}');
        ref.invalidate(collectionProvider);
        Navigator.of(context).pop();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已删除内容')));
      } catch (e) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('删除失败: $e')));
      }
    }
  }
}
