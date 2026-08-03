import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/responsive_layout.dart';
import '../../core/network/api_client.dart';
import '../../core/network/sse_service.dart';
import '../../core/utils/safe_url_launcher.dart';
import '../../core/utils/toast.dart';
import '../../core/widgets/platform_badge.dart';
import '../../theme/design_tokens.dart';
import 'models/content.dart';
import 'models/content_template.dart';
import 'providers/collection_provider.dart';
import 'providers/content_actions_controller.dart';
import 'utils/content_parser.dart';
import 'widgets/detail/content_templates.dart';
import 'widgets/detail/detail_sections.dart';
import 'widgets/detail/gallery/gallery_navigation.dart';
import 'widgets/dialogs/edit_content_dialog.dart';
import 'widgets/list/collection_card_preview.dart';

/// 内容详情页。
///
/// 这是所有内容模板的唯一宿主。页面负责：来源证据、标题、动作层级、
/// 断点布局和阅读上下文；模板只负责主体结构（见 [ContentTemplateBody]）。
///
/// 所有写操作经由 [ContentActions] 控制层，页面不直接调用 API。
class ContentDetailPage extends ConsumerStatefulWidget {
  const ContentDetailPage({
    super.key,
    required this.contentId,
    this.initialColor,
    this.preview,
  });

  final int contentId;

  /// 卡片传入的封面主色，仅用于加载态占位，不重新生成整页主题。
  final String? initialColor;

  /// 来源卡片快照，用于加载态立即显示已知信息。
  final ShareCard? preview;

  @override
  ConsumerState<ContentDetailPage> createState() => _ContentDetailPageState();
}

class _ContentDetailPageState extends ConsumerState<ContentDetailPage> {
  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _headerKeys = {};
  String? _activeHeader;
  StreamSubscription<SseEvent>? _sseSub;
  DateTime _lastScrollCheck = DateTime.now();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _bindRealtimeEvents();
  }

  void _bindRealtimeEvents() {
    ref.read(sseServiceProvider.notifier);
    _sseSub?.cancel();
    _sseSub = SseEventBus().eventStream.listen((event) {
      if (!mounted) return;
      if (event.type != 'content_updated') return;
      if (event.data['id'] != widget.contentId) return;
      // 只刷新受影响的对象，不触发整页重新入场。
      ref.invalidate(contentDetailProvider(widget.contentId));
    });
  }

  void _onScroll() {
    if (!mounted) return;

    final now = DateTime.now();
    if (now.difference(_lastScrollCheck).inMilliseconds < 100) return;
    _lastScrollCheck = now;

    if (_headerKeys.isEmpty) return;

    String? visible;
    for (final entry in _headerKeys.entries) {
      final ctx = entry.value.currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) continue;
      final offset = box.localToGlobal(Offset.zero).dy;
      if (offset < 200) {
        visible = entry.key;
      } else {
        break;
      }
    }

    if (visible != null && visible != _activeHeader) {
      setState(() => _activeHeader = visible);
    }
  }

  @override
  void dispose() {
    _sseSub?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(contentDetailProvider(widget.contentId));

    return detailAsync.when(
      data: _buildLoaded,
      loading: _buildLoading,
      error: _buildError,
    );
  }

  // --- 状态分支 ---

  Widget _buildLoading() {
    final preview = widget.preview;
    return LayoutBuilder(
      builder: (context, constraints) {
        final metrics = WindowMetrics.fromSize(
          Size(constraints.maxWidth, constraints.maxHeight),
        );
        return Scaffold(
          appBar: AppBar(
            title: Text(
              (preview?.title ?? '').trim().isEmpty
                  ? '正在打开内容'
                  : preview!.title!.trim(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          body: metrics.supportsSupportingPane
              ? _previewUsesImmersiveMedia(preview)
                    ? _buildLoadingImmersive(preview!)
                    : _buildLoadingTwoPane(preview)
              : _buildLoadingSinglePane(preview, metrics),
        );
      },
    );
  }

  Widget _buildLoadingSinglePane(ShareCard? preview, WindowMetrics metrics) {
    return ListView(
      key: const ValueKey('content-detail-loading-skeleton'),
      padding: EdgeInsets.all(
        metrics.isCompact ? AppSpacing.md : AppSpacing.lg,
      ),
      children: [
        _LoadingSharedHeader(contentId: widget.contentId, preview: preview),
        const SizedBox(height: AppSpacing.lg),
        const _DetailBodySkeleton(),
      ],
    );
  }

  Widget _buildLoadingTwoPane(ShareCard? preview) {
    return Row(
      key: const ValueKey('content-detail-loading-skeleton'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            children: [
              _LoadingSharedHeader(
                contentId: widget.contentId,
                preview: preview,
              ),
              const SizedBox(height: AppSpacing.lg),
              const _DetailBodySkeleton(),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        const SizedBox(
          width: AppPane.supportingWidth,
          child: Padding(
            padding: EdgeInsets.all(AppSpacing.md),
            child: _DetailSideSkeleton(),
          ),
        ),
      ],
    );
  }

  bool _previewUsesImmersiveMedia(ShareCard? preview) {
    return preview?.usesImmersiveMediaTransition ?? false;
  }

  Widget _buildLoadingImmersive(ShareCard preview) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      key: const ValueKey('content-detail-immersive-loading-skeleton'),
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Material(
        color: scheme.surfaceContainerLowest,
        shape: RoundedRectangleBorder(borderRadius: AppShape.paneBorder),
        clipBehavior: Clip.antiAlias,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Expanded(flex: 13, child: _ImmersiveMediaSkeleton()),
            VerticalDivider(width: 1, color: scheme.outlineVariant),
            Expanded(
              flex: 8,
              child: ColoredBox(
                color: scheme.surface,
                child: ListView(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  children: [
                    _LoadingSharedHeader(
                      contentId: widget.contentId,
                      preview: preview,
                      immersiveMedia: true,
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    const _DetailSideSkeleton(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError(Object error, StackTrace _) {
    return Scaffold(
      appBar: AppBar(title: const Text('内容详情')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: ContentEmptyState(
            icon: Icons.cloud_off_rounded,
            message: '无法加载这条内容',
            hint: formatApiErrorMessage(error, fallbackMessage: '请检查连接后重试'),
            action: FilledButton.tonal(
              onPressed: () =>
                  ref.invalidate(contentDetailProvider(widget.contentId)),
              child: const Text('重试'),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoaded(ContentDetail detail) {
    final dio = ref.watch(apiClientProvider);
    final apiBaseUrl = dio.options.baseUrl;
    final apiToken = dio.options.headers['X-API-Token']?.toString();

    return LayoutBuilder(
      builder: (context, constraints) {
        final metrics = WindowMetrics.fromSize(
          Size(constraints.maxWidth, constraints.maxHeight),
        );
        final images = ContentParser.extractAllImages(
          detail,
          apiBaseUrl,
          includeAvatarFallback: detail.template == ContentTemplate.profile,
        );
        final imageFallbacks = ContentParser.extractImageFallbacks(detail);

        final templateContext = TemplateContext(
          detail: detail,
          metrics: metrics,
          apiBaseUrl: apiBaseUrl,
          apiToken: apiToken,
          headerKeys: _headerKeys,
          images: images,
          imageFallbacks: imageFallbacks,
          onImageTap: (index) =>
              _openGallery(images, imageFallbacks, index, detail.id),
          onReParse: () => _reParse(detail.id),
        );

        return Scaffold(
          appBar: _buildAppBar(detail, metrics),
          body: SelectionArea(
            child: metrics.supportsSupportingPane
                ? templateContext.usesImmersiveMediaLayout
                      ? _buildImmersiveMediaPane(templateContext)
                      : _buildTwoPane(templateContext)
                : _buildSinglePane(templateContext),
          ),
        );
      },
    );
  }

  // --- 顶栏与动作层级 ---

  /// 顶栏只保留返回、标题和一个主动作，其余动作进入"更多"菜单。
  PreferredSizeWidget _buildAppBar(
    ContentDetail detail,
    WindowMetrics metrics,
  ) {
    return AppBar(
      // 手机横屏高度不足时压缩顶栏。
      toolbarHeight: metrics.isShortLandscape ? 48 : null,
      title: const Text('内容详情'),
      actions: [
        TextButton.icon(
          onPressed: () => SafeUrlLauncher.openExternal(context, detail.url),
          icon: const Icon(Icons.open_in_new_rounded, size: 18),
          label: const Text('原文'),
        ),
        _MoreMenu(
          detail: detail,
          onEdit: () => _edit(detail),
          onReParse: () => _reParse(detail.id),
          onDelete: () => _confirmDelete(detail),
          onChangeTemplate: () => _changeTemplate(detail),
        ),
        const SizedBox(width: AppSpacing.xs),
      ],
    );
  }

  // --- 布局 ---

  Widget _buildSinglePane(TemplateContext ctx) {
    return ListView(
      key: const ValueKey('content-detail-primary-scroll'),
      controller: _scrollController,
      padding: EdgeInsets.all(
        ctx.metrics.isCompact ? AppSpacing.md : AppSpacing.lg,
      ),
      children: [
        _SharedDetailHeader(
          detail: ctx.detail,
          apiBaseUrl: ctx.apiBaseUrl,
          apiToken: ctx.apiToken,
          showSourceLine: true,
        ),
        _DetailContentReveal(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: AppSpacing.md),
              ParseStatusBanner(
                detail: ctx.detail,
                onReParse: () => _reParse(ctx.detail.id),
              ),
              if (ctx.detail.isParseFailed || ctx.detail.isParsePending)
                const SizedBox(height: AppSpacing.md),
              _ConstrainBody(
                template: ctx.detail.template,
                child: ContentTemplateBody(context_: ctx),
              ),
              const SizedBox(height: AppSpacing.xl),
              const Divider(height: 1),
              const SizedBox(height: AppSpacing.lg),
              ContentSupportingSections(detail: ctx.detail),
              const SizedBox(height: AppSpacing.xxl),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTwoPane(TemplateContext ctx) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: ListView(
            key: const ValueKey('content-detail-primary-scroll'),
            controller: _scrollController,
            padding: const EdgeInsets.all(AppSpacing.xl),
            children: [
              _SharedDetailHeader(
                detail: ctx.detail,
                apiBaseUrl: ctx.apiBaseUrl,
                apiToken: ctx.apiToken,
                showSourceLine: false,
              ),
              _DetailContentReveal(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: AppSpacing.md),
                    ParseStatusBanner(
                      detail: ctx.detail,
                      onReParse: () => _reParse(ctx.detail.id),
                    ),
                    if (ctx.detail.isParseFailed || ctx.detail.isParsePending)
                      const SizedBox(height: AppSpacing.md),
                    _ConstrainBody(
                      template: ctx.detail.template,
                      child: ContentTemplateBody(context_: ctx),
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                  ],
                ),
              ),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        SizedBox(
          width: AppPane.supportingWidth,
          child: Column(
            children: [
              if (ctx.detail.template == ContentTemplate.article)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.md,
                    AppSpacing.md,
                    0,
                  ),
                  child: AnimatedBuilder(
                    animation: _scrollController,
                    builder: (context, _) {
                      final visible =
                          _scrollController.hasClients &&
                          _scrollController.offset >= 136;
                      return _DockedArticleTitle(
                        key: ValueKey(
                          visible
                              ? 'content-detail-docked-title-visible'
                              : 'content-detail-docked-title-hidden',
                        ),
                        detail: ctx.detail,
                        visible: visible,
                      );
                    },
                  ),
                ),
              Expanded(
                child: _DetailContentReveal(
                  child: ListView(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    children: [
                      ContentIdentityPanel(
                        detail: ctx.detail,
                        apiBaseUrl: ctx.apiBaseUrl,
                        apiToken: ctx.apiToken,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      if (ctx.detail.template == ContentTemplate.article)
                        ContentOutline(
                          detail: ctx.detail,
                          activeHeader: _activeHeader,
                          headerKeys: _headerKeys,
                        ),
                      ContentSupportingSections(detail: ctx.detail),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildImmersiveMediaPane(TemplateContext ctx) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        shape: RoundedRectangleBorder(borderRadius: AppShape.paneBorder),
        clipBehavior: Clip.antiAlias,
        child: ImmersiveMediaDetail(
          context_: ctx,
          sharedHeaderBuilder: (child) => ContentSharedTransition(
            contentId: ctx.detail.id,
            immersiveMedia: true,
            child: child,
          ),
        ),
      ),
    );
  }

  // --- 动作。全部经由控制层。---

  Future<void> _reParse(int contentId) async {
    final result = await ref
        .read(contentActionsProvider.notifier)
        .reParse(contentId);
    _report(result);
  }

  Future<void> _edit(ContentDetail detail) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => EditContentDialog(content: detail),
    );
    if (saved == true && mounted) {
      Toast.show(context, '内容已更新');
      ref.invalidate(contentDetailProvider(detail.id));
    }
  }

  Future<void> _changeTemplate(ContentDetail detail) async {
    final selected = await showModalBottomSheet<String?>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: AppShape.sheetTopBorder,
      ),
      builder: (sheetContext) => _TemplatePicker(detail: detail),
    );
    if (selected == null || !mounted) return;

    final result = await ref
        .read(contentActionsProvider.notifier)
        .setLayoutOverride(
          detail.id,
          selected == _TemplatePicker.autoValue ? null : selected,
        );
    _report(result);
  }

  Future<void> _confirmDelete(ContentDetail detail) async {
    final scheme = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('确认删除'),
        content: const Text('将删除这条内容及其已归档的本地媒体。此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: scheme.error),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final result = await ref
        .read(contentActionsProvider.notifier)
        .deleteContent(detail.id);
    if (!mounted) return;
    _report(result);
    if (result.ok) Navigator.of(context).pop();
  }

  void _report(ContentActionResult result) {
    if (!mounted) return;
    Toast.show(
      context,
      result.message,
      isError: !result.ok,
      action: result.runId == null
          ? null
          : SnackBarAction(
              label: '查看日志',
              onPressed: () =>
                  context.push('/tasks/${Uri.encodeComponent(result.runId!)}'),
            ),
    );
  }

  void _openGallery(
    List<String> images,
    Map<String, List<String>> imageFallbacks,
    int index,
    int contentId,
  ) {
    if (images.isEmpty) return;
    final dio = ref.read(apiClientProvider);
    pushFullScreenGallery(
      context: context,
      images: images,
      fallbackUrlsByImage: imageFallbacks,
      initialIndex: index,
      apiBaseUrl: dio.options.baseUrl,
      apiToken: dio.options.headers['X-API-Token']?.toString(),
      contentId: contentId,
    );
  }
}

/// 详情加载态的共享容器目标。它占据最终详情头的真实位置，而不是把
/// 卡片副本移动到屏幕中央；已知的标题和来源在飞行结束前保持连续。
class _LoadingSharedHeader extends StatelessWidget {
  const _LoadingSharedHeader({
    required this.contentId,
    required this.preview,
    this.immersiveMedia = false,
  });

  final int contentId;
  final ShareCard? preview;
  final bool immersiveMedia;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final surface = Material(
      key: const ValueKey('content-detail-shared-loading-header'),
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: AppShape.cardBorder),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 116),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: preview == null
              ? const _LoadingHeaderPlaceholder()
              : _PreviewHeader(preview: preview!),
        ),
      ),
    );

    if (preview == null) return surface;
    return ContentSharedTransition(
      contentId: contentId,
      immersiveMedia: immersiveMedia,
      child: surface,
    );
  }
}

class _ImmersiveMediaSkeleton extends StatelessWidget {
  const _ImmersiveMediaSkeleton();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surfaceContainerLowest,
      child: Center(
        child: FractionallySizedBox(
          widthFactor: 0.78,
          child: AspectRatio(
            aspectRatio: 4 / 3,
            child: _SkeletonPulse(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PreviewHeader extends StatelessWidget {
  const _PreviewHeader({required this.preview});

  final ShareCard preview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final author = preview.authorName?.trim() ?? '';
    final title = preview.title?.trim() ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          children: [
            PlatformBadge(platform: preview.platform),
            if (author.isNotEmpty) ...[
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  author,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ] else
              const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xs,
                vertical: AppSpacing.xxs,
              ),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppShape.pill),
              ),
              child: Text(
                preview.template.label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          title.isEmpty ? '无标题' : title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            height: 1.25,
          ),
        ),
      ],
    );
  }
}

class _LoadingHeaderPlaceholder extends StatelessWidget {
  const _LoadingHeaderPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _SkeletonBlock(widthFactor: 0.32, height: 16),
        SizedBox(height: AppSpacing.md),
        _SkeletonBlock(widthFactor: 0.78, height: 28),
      ],
    );
  }
}

class _DetailBodySkeleton extends StatelessWidget {
  const _DetailBodySkeleton();

  @override
  Widget build(BuildContext context) {
    return const _SkeletonPulse(
      child: Column(
        key: ValueKey('content-detail-body-skeleton'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SkeletonBlock(widthFactor: 0.44, height: 28),
          SizedBox(height: AppSpacing.xl),
          _SkeletonBlock(widthFactor: 0.96, height: 18),
          SizedBox(height: AppSpacing.sm),
          _SkeletonBlock(widthFactor: 0.88, height: 18),
          SizedBox(height: AppSpacing.sm),
          _SkeletonBlock(widthFactor: 0.93, height: 18),
          SizedBox(height: AppSpacing.xxl),
          _SkeletonBlock(widthFactor: 0.36, height: 24),
          SizedBox(height: AppSpacing.lg),
          _SkeletonBlock(widthFactor: 0.9, height: 18),
          SizedBox(height: AppSpacing.sm),
          _SkeletonBlock(widthFactor: 0.82, height: 18),
          SizedBox(height: AppSpacing.sm),
          _SkeletonBlock(widthFactor: 0.68, height: 18),
        ],
      ),
    );
  }
}

class _DetailSideSkeleton extends StatelessWidget {
  const _DetailSideSkeleton();

  @override
  Widget build(BuildContext context) {
    return const _SkeletonPulse(
      child: Column(
        key: ValueKey('content-detail-side-skeleton'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SkeletonBlock(widthFactor: 0.24, height: 20),
          SizedBox(height: AppSpacing.md),
          _SkeletonBlock(widthFactor: 0.82, height: 14),
          SizedBox(height: AppSpacing.sm),
          Padding(
            padding: EdgeInsets.only(left: AppSpacing.sm),
            child: _SkeletonBlock(widthFactor: 0.74, height: 14),
          ),
          SizedBox(height: AppSpacing.sm),
          Padding(
            padding: EdgeInsets.only(left: AppSpacing.xl),
            child: _SkeletonBlock(widthFactor: 0.62, height: 14),
          ),
          SizedBox(height: AppSpacing.xxl),
          _SkeletonBlock(widthFactor: 0.42, height: 18),
          SizedBox(height: AppSpacing.md),
          _SkeletonBlock(widthFactor: 0.7, height: 14),
          SizedBox(height: AppSpacing.sm),
          _SkeletonBlock(widthFactor: 0.56, height: 14),
        ],
      ),
    );
  }
}

class _SkeletonBlock extends StatelessWidget {
  const _SkeletonBlock({required this.widthFactor, required this.height});

  final double widthFactor;
  final double height;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      widthFactor: widthFactor,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
      ),
    );
  }
}

class _SkeletonPulse extends StatefulWidget {
  const _SkeletonPulse({required this.child});

  final Widget child;

  @override
  State<_SkeletonPulse> createState() => _SkeletonPulseState();
}

class _SkeletonPulseState extends State<_SkeletonPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller
        ..stop()
        ..value = 1;
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(
        begin: 0.58,
        end: 0.9,
      ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut)),
      child: widget.child,
    );
  }
}

/// 真实内容在骨架之后轻微上移并渐入，不参与共享容器飞行。
class _DetailContentReveal extends StatefulWidget {
  const _DetailContentReveal({required this.child});

  final Widget child;

  @override
  State<_DetailContentReveal> createState() => _DetailContentRevealState();
}

class _DetailContentRevealState extends State<_DetailContentReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMotion.contentSwap,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else if (_controller.value == 0) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(
      parent: _controller,
      curve: AppMotion.standardCurve,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.018),
          end: Offset.zero,
        ).animate(curved),
        child: widget.child,
      ),
    );
  }
}

/// 详情头：来源、标题、模板标识。
class _Header extends StatelessWidget {
  const _Header({
    required this.detail,
    required this.apiBaseUrl,
    required this.apiToken,
    required this.showSourceLine,
  });

  final ContentDetail detail;
  final String apiBaseUrl;
  final String? apiToken;
  final bool showSourceLine;

  @override
  Widget build(BuildContext context) {
    final contextData = detail.contextData;
    final isShortPost = detail.template == ContentTemplate.shortPost;
    final normalizedTitle = (detail.title ?? '').trim();
    final normalizedBody = (detail.body ?? '').trim();
    final titleRepeatsBody =
        isShortPost &&
        normalizedTitle.isNotEmpty &&
        normalizedBody.isNotEmpty &&
        (normalizedTitle == normalizedBody ||
            normalizedBody.startsWith(normalizedTitle));
    final isQuestionAnswer =
        detail.contentType == 'answer' &&
        contextData != null &&
        contextData['type'] == 'question';
    final questionTitle = isQuestionAnswer
        ? contextData['title']?.toString().trim()
        : null;
    final statsRaw = isQuestionAnswer ? contextData['stats'] : null;
    final stats = statsRaw is Map
        ? Map<String, dynamic>.from(statsRaw)
        : const <String, dynamic>{};
    final answerCount = _metadataCount(stats['answer_count']);
    final followerCount = _metadataCount(stats['follower_count']);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xxs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            PlatformBadge(platform: detail.platform),
            _ContentKindBadge(label: _contentKindLabel(detail)),
          ],
        ),
        if (!titleRepeatsBody) ...[
          const SizedBox(height: AppSpacing.sm),
          ContentTitleBlock(
            detail: detail,
            titleOverride: questionTitle?.isNotEmpty == true
                ? questionTitle
                : null,
            style: isShortPost ? Theme.of(context).textTheme.titleMedium : null,
          ),
        ],
        if (showSourceLine) ...[
          const SizedBox(height: AppSpacing.md),
          ContentSourceLine(
            detail: detail,
            apiBaseUrl: apiBaseUrl,
            apiToken: apiToken,
            showPlatform: false,
            showOriginalAction: false,
          ),
        ],
        if (isQuestionAnswer && (answerCount > 0 || followerCount > 0)) ...[
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.xxs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _QuestionStat(
                icon: Icons.question_answer_outlined,
                label: '$answerCount 回答',
              ),
              _QuestionStat(
                icon: Icons.people_outline_rounded,
                label: '$followerCount 关注',
              ),
            ],
          ),
        ],
      ],
    );
  }
}

int _metadataCount(Object? value) => switch (value) {
  int count => count,
  num count => count.toInt(),
  String count => int.tryParse(count) ?? 0,
  _ => 0,
};

String _contentKindLabel(ContentDetail detail) => switch (detail.contentType) {
  'answer' => '回答',
  'question' => '问题',
  'article' => '文章',
  'note' => '图文笔记',
  'tweet' || 'status' || 'dynamic' => '短帖子',
  'video' || 'live' || 'bangumi' => '视频',
  'audio' => '音频',
  'user_profile' => '主页',
  _ => detail.template.label,
};

class _ContentKindBadge extends StatelessWidget {
  const _ContentKindBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppShape.pill),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _QuestionStat extends StatelessWidget {
  const _QuestionStat({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: AppSpacing.xxs),
        Text(label, style: theme.textTheme.labelMedium?.copyWith(color: color)),
      ],
    );
  }
}

/// 详情页唯一的共享容器目标。它始终拥有不透明 tonal surface，避免飞行
/// 过程中透出正文；加载态与已加载态任一时刻也只会挂载一个同 tag Hero。
class _SharedDetailHeader extends StatelessWidget {
  const _SharedDetailHeader({
    required this.detail,
    required this.apiBaseUrl,
    required this.apiToken,
    required this.showSourceLine,
  });

  final ContentDetail detail;
  final String apiBaseUrl;
  final String? apiToken;
  final bool showSourceLine;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ContentSharedTransition(
      contentId: detail.id,
      child: Material(
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: AppShape.cardBorder),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: _Header(
            detail: detail,
            apiBaseUrl: apiBaseUrl,
            apiToken: apiToken,
            showSourceLine: showSourceLine,
          ),
        ),
      ),
    );
  }
}

class _DockedArticleTitle extends StatelessWidget {
  const _DockedArticleTitle({
    super.key,
    required this.detail,
    required this.visible,
  });

  final ContentDetail detail;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = _displayDetailTitle(detail);
    return AnimatedSize(
      duration: AppMotion.contentSwap,
      curve: AppMotion.standardCurve,
      alignment: Alignment.topCenter,
      child: visible
          ? Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: AnimatedSlide(
                duration: AppMotion.contentSwap,
                curve: AppMotion.standardCurve,
                offset: visible ? Offset.zero : const Offset(0, -0.08),
                child: AnimatedOpacity(
                  duration: AppMotion.contentSwap,
                  opacity: visible ? 1 : 0,
                  child: Container(
                    key: const ValueKey('content-detail-docked-title'),
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.secondaryContainer,
                      borderRadius: AppShape.paneBorder,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '正在阅读',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSecondaryContainer,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          title,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: theme.colorScheme.onSecondaryContainer,
                            fontWeight: FontWeight.w700,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )
          : const SizedBox.shrink(),
    );
  }
}

String _displayDetailTitle(ContentDetail detail) {
  final contextData = detail.contextData;
  if (detail.contentType == 'answer' &&
      contextData != null &&
      contextData['type'] == 'question') {
    final questionTitle = contextData['title']?.toString().trim() ?? '';
    if (questionTitle.isNotEmpty) return questionTitle;
  }
  final title = detail.title?.trim() ?? '';
  return title.isEmpty ? '无标题' : title;
}

/// 文章与图文笔记限制正文宽度，超宽屏不无限拉伸。
class _ConstrainBody extends StatelessWidget {
  const _ConstrainBody({required this.template, required this.child});

  final ContentTemplate template;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!template.constrainsBodyWidth) return child;
    return Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppPane.readableMaxWidth),
        child: child,
      ),
    );
  }
}

/// 低频动作统一进入"更多"菜单，不在顶栏并列多个同权图标。
class _MoreMenu extends StatelessWidget {
  const _MoreMenu({
    required this.detail,
    required this.onEdit,
    required this.onReParse,
    required this.onDelete,
    required this.onChangeTemplate,
  });

  final ContentDetail detail;
  final VoidCallback onEdit;
  final VoidCallback onReParse;
  final VoidCallback onDelete;
  final VoidCallback onChangeTemplate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopupMenuButton<String>(
      tooltip: '更多操作',
      icon: const Icon(Icons.more_vert_rounded),
      onSelected: (value) {
        switch (value) {
          case 'edit':
            onEdit();
          case 'reparse':
            onReParse();
          case 'template':
            onChangeTemplate();
          case 'delete':
            onDelete();
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'edit',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.edit_outlined),
            title: Text('编辑内容'),
          ),
        ),
        PopupMenuItem(
          value: 'template',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.dashboard_customize_outlined),
            title: const Text('切换模板'),
            subtitle: Text(detail.template.label),
          ),
        ),
        const PopupMenuItem(
          value: 'reparse',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.refresh_rounded),
            title: Text('重新解析'),
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'delete',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.delete_outline_rounded, color: scheme.error),
            title: Text('删除', style: TextStyle(color: scheme.error)),
          ),
        ),
      ],
    );
  }
}

/// 模板选择器。
///
/// 只列出后端 `LayoutType` 枚举实际接受的值——这是 `layout_type_override`
/// 的合法取值域，不是前端自定义的模板名。
class _TemplatePicker extends StatelessWidget {
  const _TemplatePicker({required this.detail});

  final ContentDetail detail;

  static const autoValue = '__auto__';

  /// 与后端 `LayoutType` 枚举一致。
  static const _options = <(String, String, String)>[
    (autoValue, '自动判定', '由来源和内容特征决定'),
    ('article', '文章', '连续阅读，正文限宽'),
    ('gallery', '图集 / 图文', '媒体为主体'),
    ('video', '视频', '播放器与简介'),
    ('audio', '音频', '封面、播放与文字说明'),
    ('link', '书签', '只保留链接与保存记录'),
  ];

  @override
  Widget build(BuildContext context) {
    final current = detail.layoutTypeOverride ?? autoValue;

    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.xs,
            ),
            child: Text('切换模板', style: Theme.of(context).textTheme.titleMedium),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: Text(
              '手动选择后，重新解析不会覆盖你的选择。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          RadioGroup<String>(
            groupValue: current,
            onChanged: (selected) => Navigator.of(context).pop(selected),
            child: Column(
              children: [
                for (final (value, label, hint) in _options)
                  RadioListTile<String>(
                    value: value,
                    title: Text(label),
                    subtitle: Text(hint),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
