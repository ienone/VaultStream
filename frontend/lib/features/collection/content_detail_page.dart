import 'widgets/dialogs/delete_content_dialog.dart';

import 'package:scroll_to_index/scroll_to_index.dart';

import '../automation/widgets/push_content_dialog.dart';
import '../player/global_playback_controller.dart';
import '../events/providers/knowledge_event_provider.dart';

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/responsive_layout.dart';
import '../../core/media/media_asset.dart';
import '../../core/network/api_client.dart';
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
import 'widgets/detail/reading_outline_bar.dart';
import 'widgets/detail/detail_sections.dart';
import 'widgets/detail/components/unified_stats.dart';
import 'widgets/detail/components/tags_section.dart';
import 'widgets/detail/gallery/gallery_navigation.dart';
import 'widgets/dialogs/content_template_picker.dart';
import '../events/widgets/add_to_event_dialog.dart';
import '../events/widgets/content_event_links.dart';

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
    this.initialPlaybackSeconds,
    this.initialMediaAssetId,
    this.onClose,
    this.onToggleFocus,
    this.focused = false,
    this.deferBody = false,
  });

  final int contentId;

  /// 卡片传入的封面主色，仅用于加载态占位，不重新生成整页主题。
  final String? initialColor;

  /// 来源卡片快照，用于加载态立即显示已知信息。
  final ShareCard? preview;

  /// 搜索时间点深链；只在显式秒数非负且目标媒体存在时生效。
  final double? initialPlaybackSeconds;
  final int? initialMediaAssetId;

  /// 内嵌入口的关闭与专注阅读动作；布局仍由阅读器自身空间决定。
  final VoidCallback? onClose;
  final VoidCallback? onToggleFocus;
  final bool focused;
  final bool deferBody;

  @override
  ConsumerState<ContentDetailPage> createState() => _ContentDetailPageState();
}

class _ContentDetailPageState extends ConsumerState<ContentDetailPage> {
  final AutoScrollController _scrollController = AutoScrollController();
  final Map<String, int> _headerIndexes = {};
  final Map<String, GlobalKey> _headerKeys = {};
  final _readingHeaderKey = GlobalKey();
  final _activeHeader = ValueNotifier<String?>(null);
  final _headerProgress = ValueNotifier<double>(0);
  final _readingProgress = ValueNotifier<double>(0);
  int _readingBlockCount = 0;
  bool _readingUpdateScheduled = false;
  String? _parsedBody;
  MarkdownMetadata _markdownMetadata = (headers: [], imageUrls: []);
  int _selectedImageIndex = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(covariant ContentDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.contentId != widget.contentId) {
      _selectedImageIndex = 0;
      _headerKeys.clear();
      _headerIndexes.clear();
      _activeHeader.value = null;
      _headerProgress.value = 0;
      _readingProgress.value = 0;
      _readingBlockCount = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scrollController.hasClients) {
          _scrollController.jumpTo(0);
        }
      });
    }
  }

  void _selectImage(int index) {
    if (mounted && index != _selectedImageIndex) {
      setState(() => _selectedImageIndex = index);
    }
  }

  Future<void> _scrollToHeader(String id) async {
    final index = _headerIndexes[id];
    if (index == null) return;
    final contentId = widget.contentId;
    await _scrollController.scrollToIndex(
      index,
      preferPosition: AutoScrollPosition.begin,
      duration: MediaQuery.disableAnimationsOf(context)
          ? const Duration(milliseconds: 1)
          : AppMotion.contentSwap,
    );
    if (mounted && widget.contentId == contentId) _activeHeader.value = id;
  }

  void _onScroll() {
    if (_readingUpdateScheduled) return;
    _readingUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _readingUpdateScheduled = false;
      if (mounted) _updateReadingPosition();
    });
  }

  void _updateReadingPosition() {
    if (!mounted) return;

    final header = _readingHeaderKey.currentContext?.findRenderObject();
    final threshold = header is RenderBox && header.hasSize
        ? header.size.height
        : 180.0;
    final offset = _scrollController.hasClients
        ? _scrollController.offset
        : 0.0;
    _headerProgress.value = ((offset - threshold + 48) / 48).clamp(0.0, 1.0);

    double blockProgress = 0;
    final readingLine = offset + 32;
    int? visibleIndex;
    for (final entry in _scrollController.tagMap.entries) {
      final box = entry.value.context.findRenderObject();
      if (box is! RenderBox || !box.attached || !_scrollController.hasClients) {
        continue;
      }
      final viewport = RenderAbstractViewport.maybeOf(box);
      if (viewport == null) continue;
      final offset = viewport.getOffsetToReveal(box, 0).offset;
      if (_readingBlockCount > 0 && box.size.height > 0) {
        final fraction = ((readingLine - offset) / box.size.height).clamp(
          0.0,
          1.0,
        );
        if (offset <= readingLine) {
          final progress = (entry.key + fraction) / _readingBlockCount;
          if (progress > blockProgress) blockProgress = progress;
        }
      }
      if (offset <= _scrollController.offset + 32 &&
          (visibleIndex == null || entry.key > visibleIndex)) {
        visibleIndex = entry.key;
      }
    }
    if (_scrollController.hasClients &&
        _readingBlockCount > 0 &&
        _scrollController.tagMap.isNotEmpty) {
      final position = _scrollController.position;
      final atEnd =
          position.extentAfter < 1 &&
          _scrollController.tagMap.containsKey(_readingBlockCount - 1);
      _readingProgress.value = atEnd ? 1 : blockProgress.clamp(0.0, 1.0);
    }
    String? visible;
    if (visibleIndex != null) {
      for (final entry in _headerIndexes.entries) {
        if (entry.value <= visibleIndex) visible = entry.key;
      }
    }

    _activeHeader.value = visible;
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _activeHeader.dispose();
    _headerProgress.dispose();
    _readingProgress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(contentDetailProvider(widget.contentId));

    final detail = detailAsync.asData?.value;
    final loading = detailAsync.isLoading || widget.deferBody;
    return Scaffold(
      appBar: _buildAppBar(loading ? null : detail),
      body: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: detailAsync.when(
          data: (detail) =>
              widget.deferBody ? _buildLoading() : _buildLoaded(detail),
          loading: _buildLoading,
          error: _buildError,
        ),
      ),
    );
  }

  // --- 状态分支 ---

  Widget _buildLoading() {
    final preview = widget.preview;
    return LayoutBuilder(
      builder: (context, constraints) {
        final metrics = WindowMetrics.fromSize(
          Size(
            constraints.maxWidth /
                (MediaQuery.textScalerOf(context).scale(16) / 16),
            constraints.maxHeight,
          ),
        );
        return metrics.supportsSupportingPane
            ? (preview?.usesImmersiveMediaTransition ?? false)
                  ? _buildLoadingImmersive(preview!)
                  : _buildLoadingSinglePane(preview, metrics)
            : _buildLoadingSinglePane(preview, metrics);
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
        _LoadingDetailHeader(preview: preview),
        const SizedBox(height: AppSpacing.lg),
        const _DetailBodySkeleton(),
      ],
    );
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
            const SizedBox(width: AppSpacing.md),
            Expanded(
              flex: 8,
              child: ColoredBox(
                color: scheme.surface,
                child: ListView(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  children: [
                    _LoadingDetailHeader(preview: preview),
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
    final notFound = error is DioException && error.response?.statusCode == 404;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: ContentEmptyState(
          icon: notFound ? Icons.article_outlined : Icons.cloud_off_rounded,
          message: notFound ? '内容不存在' : '无法加载这条内容',
          hint: notFound
              ? null
              : formatApiErrorMessage(error, fallbackMessage: '请重试'),
          action: FilledButton.tonal(
            onPressed: notFound
                ? () {
                    if (widget.onClose != null) {
                      widget.onClose!();
                    } else {
                      context.go('/collection');
                    }
                  }
                : () => ref.invalidate(contentDetailProvider(widget.contentId)),
            child: Text(notFound ? '返回收藏库' : '重试'),
          ),
        ),
      ),
    );
  }

  Widget _buildLoaded(ContentDetail detail) {
    final bodyText = ContentParser.getMarkdownContent(detail);
    if (_parsedBody != bodyText) {
      _parsedBody = bodyText;
      _markdownMetadata = ContentParser.parseMarkdownMetadata(bodyText);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final metrics = WindowMetrics.fromSize(
          Size(
            constraints.maxWidth /
                (MediaQuery.textScalerOf(context).scale(16) / 16),
            constraints.maxHeight,
          ),
        );
        final images = ContentParser.extractAllImages(
          detail,
          includeAvatarFallback: detail.template == ContentTemplate.profile,
        );
        final imageFallbacks = ContentParser.extractImageFallbacks(detail);
        final imageAssets = {
          for (final asset in ContentParser.extractImageAssets(detail))
            asset.sources.first.url: asset,
        };

        final templateContext = TemplateContext(
          detail: detail,
          markdown: _markdownMetadata,
          metrics: metrics,
          headerKeys: _headerKeys,
          images: images,
          selectedImageIndex: images.isEmpty
              ? 0
              : _selectedImageIndex.clamp(0, images.length - 1),
          onImagePageChanged: _selectImage,
          imageFallbacks: imageFallbacks,
          imageAssets: imageAssets,
          onImageTap: (index) => _openGallery(
            images,
            imageFallbacks,
            imageAssets,
            index,
            detail.id,
          ),
          onReParse: () => _reParse(detail),
          onResolveParseCandidate: (field, action, mergedValue) =>
              _resolveParseCandidate(detail.id, field, action, mergedValue),
          initialPlaybackPosition:
              widget.initialPlaybackSeconds != null &&
                  widget.initialPlaybackSeconds!.isFinite &&
                  widget.initialPlaybackSeconds! >= 0
              ? Duration(
                  milliseconds: (widget.initialPlaybackSeconds! * 1000).round(),
                )
              : null,
          initialMediaAssetId: widget.initialMediaAssetId,
        );

        final body = metrics.supportsSupportingPane
            ? templateContext.usesImmersiveMediaLayout
                  ? _buildImmersiveMediaPane(templateContext)
                  : _buildTwoPane(templateContext)
            : _buildSinglePane(templateContext);
        // Text selection must not compete with document pinch/pan gestures.
        return detail.template == ContentTemplate.document
            ? body
            : SelectionArea(child: body);
      },
    );
  }

  // --- 顶栏与动作层级 ---

  /// 顶栏只保留返回、标题和一个主动作，其余动作进入"更多"菜单。
  PreferredSizeWidget _buildAppBar(ContentDetail? detail) {
    return AppBar(
      backgroundColor: Theme.of(context).colorScheme.surface,
      scrolledUnderElevation: 0,
      toolbarHeight: WindowMetrics.of(context).toolbarHeight,
      leading: widget.onClose == null
          ? null
          : BackButton(onPressed: widget.onClose),
      title: Text('阅读', maxLines: 1, overflow: TextOverflow.ellipsis),
      actions: [
        if (detail != null &&
            ref.watch(
                  globalPlaybackProvider.select(
                    (state) => state.request?.contentId,
                  ),
                ) ==
                detail.id)
          IconButton(
            tooltip: '播放设置与队列',
            icon: const Icon(Icons.queue_music_rounded),
            onPressed: () => context.push('/player'),
          ),
        if (widget.onToggleFocus != null)
          IconButton(
            tooltip: widget.focused ? '显示列表' : '专注阅读',
            icon: Icon(
              widget.focused
                  ? Icons.view_sidebar_outlined
                  : Icons.fullscreen_rounded,
            ),
            onPressed: widget.onToggleFocus,
          ),
        if (detail != null && detail.hasExternalOriginal)
          TextButton.icon(
            onPressed: () => SafeUrlLauncher.openExternal(
              context,
              detail.externalOriginalUrl!,
            ),
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: const Text('原文'),
          ),
        if (detail != null)
          _MoreMenu(
            detail: detail,
            onEdit: () => _edit(detail),
            onAddToEvent: () => _addToEvent(detail),
            onReParse: () => _reParse(detail),
            onDelete: () => _confirmDelete(detail),
            onChangeTemplate: () => _changeTemplate(detail),
          ),
        const SizedBox(width: AppSpacing.xs),
      ],
    );
  }

  Widget _revealHeader(Widget child) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 160),
    curve: Curves.easeOut,
    child: child,
    builder: (context, opacity, child) =>
        Opacity(opacity: opacity, child: child),
  );

  // --- 布局 ---

  Widget _buildSinglePane(TemplateContext ctx) => _buildReadingPane(ctx, false);

  Widget _buildTwoPane(TemplateContext ctx) => _buildReadingPane(ctx, true);

  Widget _buildReadingPane(TemplateContext ctx, bool supporting) {
    final article = ctx.detail.template == ContentTemplate.article;
    final events = ref.watch(knowledgeEventsProvider(ctx.detail.id));
    supporting =
        supporting &&
        (widget.onToggleFocus == null || widget.focused) &&
        article &&
        ctx.markdown.headers.length >= 3;
    final sidebarSections = <Widget>[
      if (article && ctx.markdown.headers.isNotEmpty)
        ValueListenableBuilder<String?>(
          valueListenable: _activeHeader,
          builder: (context, active, _) => ContentOutline(
            headers: ctx.markdown.headers,
            activeHeader: active,
            onSelectHeader: _scrollToHeader,
            padding: EdgeInsets.zero,
          ),
        ),
      if (events.hasError || (events.value?.items.isNotEmpty ?? false))
        ContentEventLinks(contentId: ctx.detail.id),
      if (ctx.detail.manualEditFields.isNotEmpty ||
          ctx.detail.parseCandidate != null)
        ParseCandidatePanel(
          detail: ctx.detail,
          onResolve: ctx.onResolveParseCandidate!,
        ),
      if ([
        ...ctx.detail.tags,
        ...ctx.detail.sourceTags,
      ].any((tag) => tag.trim().isNotEmpty))
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const DetailSectionHeader(title: '标签'),
            TagsSection(detail: ctx.detail),
          ],
        ),
    ];
    Widget sectionDivider() => const Divider(height: 32, thickness: 1);
    final floatingOutline =
        !supporting && article && ctx.markdown.headers.isNotEmpty;
    final reading = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppPane.readableMaxWidth,
              ),
              child: CustomScrollView(
                key: const ValueKey('content-detail-primary-scroll'),
                controller: _scrollController,
                slivers: [
                  SliverPadding(
                    padding: EdgeInsets.all(
                      ctx.metrics.isCompact ? AppSpacing.md : AppSpacing.xl,
                    ),
                    sliver: SliverMainAxisGroup(
                      slivers: [
                        SliverToBoxAdapter(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              KeyedSubtree(
                                key: _readingHeaderKey,
                                child: _revealHeader(
                                  _DetailHeaderSurface(
                                    detail: ctx.detail,
                                    showSourceLine: true,
                                  ),
                                ),
                              ),
                              const SizedBox(height: AppSpacing.md),
                              ParseStatusBanner(
                                detail: ctx.detail,
                                onReParse: () => _reParse(ctx.detail),
                              ),
                              if (ctx.detail.isParseFailed ||
                                  ctx.detail.isParsePending)
                                const SizedBox(height: AppSpacing.md),
                            ],
                          ),
                        ),
                        ContentTemplateBody(
                          context_: ctx,
                          scrollController: _scrollController,
                          headerIndexes: _headerIndexes,
                          onBlockCount: (count) {
                            _readingBlockCount = count;
                            _onScroll();
                          },
                        ),
                        SliverToBoxAdapter(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const SizedBox(height: AppSpacing.xl),
                              if (!supporting) ...[
                                ContentEventLinks(contentId: ctx.detail.id),
                                ContentSupportingSections(
                                  showStats: false,
                                  detail: ctx.detail,
                                  onResolveParseCandidate:
                                      ctx.onResolveParseCandidate,
                                ),
                              ],
                              SizedBox(
                                height: floatingOutline ? 88 : AppSpacing.xxl,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (supporting)
          SizedBox(
            width: 256,
            child: Material(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: AppShape.paneBorder,
              clipBehavior: Clip.antiAlias,
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.md),
                children: [
                  ValueListenableBuilder<double>(
                    valueListenable: _headerProgress,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _displayDetailTitle(ctx.detail),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        ContentSourceLine(
                          detail: ctx.detail,
                          showPlatform: false,
                          showOriginalAction: false,
                        ),
                        UnifiedStats(detail: ctx.detail),
                        if (sidebarSections.isNotEmpty) sectionDivider(),
                      ],
                    ),
                    builder: (context, progress, child) => ClipRect(
                      child: Align(
                        alignment: Alignment.topCenter,
                        heightFactor: progress,
                        child: Opacity(
                          opacity: progress,
                          child: Transform.translate(
                            offset: Offset(0, 12 * (1 - progress)),
                            child: child,
                          ),
                        ),
                      ),
                    ),
                  ),
                  for (
                    var index = 0;
                    index < sidebarSections.length;
                    index++
                  ) ...[
                    if (index > 0) sectionDivider(),
                    sidebarSections[index],
                  ],
                ],
              ),
            ),
          ),
      ],
    );
    return Stack(
      children: [
        Positioned.fill(child: reading),
        if (floatingOutline)
          Positioned.fill(
            child: ReadingOutlineBar(
              headers: ctx.markdown.headers,
              activeHeader: _activeHeader,
              progress: _readingProgress,
              onSelect: _scrollToHeader,
            ),
          ),
      ],
    );
  }

  Widget _buildImmersiveMediaPane(TemplateContext ctx) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: ImmersiveMediaDetail(
        context_: ctx,
        sharedHeaderBuilder: _revealHeader,
      ),
    );
  }

  // --- 动作。全部经由控制层。---

  Future<void> _reParse(ContentDetail detail) async {
    if (detail.manualEditFields.isNotEmpty) {
      final confirmed = await showDialog<bool>(
        context: context,
        animationStyle: MediaQuery.disableAnimationsOf(context)
            ? AnimationStyle.noAnimation
            : null,
        builder: (dialogContext) => AlertDialog(
          title: const Text('重新解析并保留人工修改？'),
          content: Text(
            detail.parseCandidate == null
                ? '人工修改的字段不会被覆盖；有差异的新解析结果会出现在详情页供你比较。'
                : '人工修改的字段不会被覆盖；本次结果会替换尚未处理的解析候选。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('继续解析'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    final result = await ref
        .read(contentActionsProvider.notifier)
        .reParse(detail.id);
    _report(result);
  }

  Future<void> _resolveParseCandidate(
    int contentId,
    String field,
    String action,
    String? mergedValue,
  ) async {
    final result = await ref
        .read(contentActionsProvider.notifier)
        .resolveParseCandidate(
          contentId,
          field: field,
          action: action,
          mergedValue: mergedValue,
        );
    _report(result);
  }

  Future<void> _edit(ContentDetail detail) async {
    final saved = await context.push<bool>('/collection/${detail.id}/edit');
    if (saved == true && mounted) {
      Toast.show(context, '内容已更新');
      ref.invalidate(contentDetailProvider(detail.id));
    }
  }

  Future<void> _addToEvent(ContentDetail detail) async {
    final event = await showAddToEventDialog(
      context,
      contentId: detail.id,
      suggestedTitle: _displayDetailTitle(detail),
    );
    if (event == null || !mounted) return;
    Toast.show(
      context,
      '已加入事件',
      action: SnackBarAction(
        label: '查看',
        onPressed: () => context.push('/events/${event.id}'),
      ),
    );
  }

  Future<void> _changeTemplate(ContentDetail detail) async {
    final selected = await showContentTemplatePicker(
      context,
      detail.layoutTypeOverride,
    );
    if (selected == null || !mounted) return;

    final result = await ref
        .read(contentActionsProvider.notifier)
        .setLayoutOverride(
          detail.id,
          selected == ContentTemplatePicker.autoValue ? null : selected,
        );
    _report(result);
  }

  Future<void> _confirmDelete(ContentDetail detail) async {
    final confirmed = await confirmContentDeletion(context);
    if (confirmed != true || !mounted) return;

    final result = await ref
        .read(contentActionsProvider.notifier)
        .deleteContent(detail.id);
    if (!mounted) return;
    _report(result);
    if (result.ok) {
      if (widget.onClose != null) {
        widget.onClose!();
      } else {
        Navigator.of(context).pop();
      }
    }
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
    Map<String, MediaAsset> imageAssets,
    int index,
    int contentId,
  ) {
    if (images.isEmpty) return;
    pushFullScreenGallery(
      context: context,
      images: images,
      fallbackUrlsByImage: imageFallbacks,
      mediaAssetsByImage: imageAssets,
      initialIndex: index,
      onPageChanged: _selectImage,
      contentId: contentId,
    );
  }
}

/// 详情加载时延续已有标题与来源，并保持头部占位。
class _LoadingDetailHeader extends StatelessWidget {
  const _LoadingDetailHeader({required this.preview});

  final ShareCard? preview;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      key: const ValueKey('content-detail-loading-header'),
      color: scheme.surface,
      shape: RoundedRectangleBorder(borderRadius: AppShape.cardBorder),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 116),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: preview == null
              ? const _LoadingHeaderPlaceholder()
              : _PreviewHeader(preview: preview!),
        ),
      ),
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
        if (title.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              height: 1.25,
            ),
          ),
        ],
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
    duration: AppMotion.skeletonPulse,
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
      opacity: Tween<double>(begin: 0.58, end: 0.9).animate(
        CurvedAnimation(parent: _controller, curve: AppMotion.ambientCurve),
      ),
      child: widget.child,
    );
  }
}

/// 真实内容在骨架之后轻微上移并渐入，不参与共享容器飞行。
/// 详情头：来源、标题、模板标识。
class _Header extends StatelessWidget {
  const _Header({required this.detail, required this.showSourceLine});

  final ContentDetail detail;
  final bool showSourceLine;

  @override
  Widget build(BuildContext context) {
    final contextData = detail.contextData;
    final isShortPost = detail.template == ContentTemplate.shortPost;
    final titleRepeatsBody = detail.shortPostTitleRepeatsBody;
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
            if (detail.hasExternalOriginal || detail.platform == 'telegram')
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
                label: '$followerCount 人关注问题',
              ),
            ],
          ),
        ],
        if (showSourceLine) ...[
          const SizedBox(height: AppSpacing.md),
          ContentSourceLine(
            detail: detail,
            showPlatform: false,
            showOriginalAction: false,
          ),
        ],
        UnifiedStats(detail: detail),
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

/// 详情标题与来源使用统一表面，文档标题支持文本选择。
class _DetailHeaderSurface extends StatelessWidget {
  const _DetailHeaderSurface({
    required this.detail,
    required this.showSourceLine,
  });

  final ContentDetail detail;
  final bool showSourceLine;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      shape: RoundedRectangleBorder(borderRadius: AppShape.cardBorder),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: detail.template == ContentTemplate.document
            ? SelectionArea(
                child: _Header(detail: detail, showSourceLine: showSourceLine),
              )
            : _Header(detail: detail, showSourceLine: showSourceLine),
      ),
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
  return title.isEmpty ? detail.template.label : title;
}

/// 文章与图文笔记限制正文宽度，超宽屏不无限拉伸。
/// 低频动作统一进入"更多"菜单，不在顶栏并列多个同权图标。
class _MoreMenu extends StatelessWidget {
  const _MoreMenu({
    required this.detail,
    required this.onEdit,
    required this.onAddToEvent,
    required this.onReParse,
    required this.onDelete,
    required this.onChangeTemplate,
  });

  final ContentDetail detail;
  final VoidCallback onEdit;
  final VoidCallback onAddToEvent;
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
          case 'push':
            showPushContentDialog(context, [detail.id]);
          case 'edit':
            onEdit();
          case 'event':
            onAddToEvent();
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
          value: 'push',
          child: Material(
            type: MaterialType.transparency,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.send_outlined),
              title: Text('推送…'),
            ),
          ),
        ),
        const PopupMenuItem(
          value: 'edit',
          child: Material(
            type: MaterialType.transparency,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.edit_outlined),
              title: Text('编辑内容'),
            ),
          ),
        ),
        const PopupMenuItem(
          value: 'event',
          child: Material(
            type: MaterialType.transparency,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.hub_outlined),
              title: Text('加入事件'),
            ),
          ),
        ),
        PopupMenuItem(
          value: 'template',
          child: Material(
            type: MaterialType.transparency,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.dashboard_customize_outlined),
              title: const Text('切换模板'),
              subtitle: Text(detail.template.label),
            ),
          ),
        ),
        const PopupMenuItem(
          value: 'reparse',
          child: Material(
            type: MaterialType.transparency,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.refresh_rounded),
              title: Text('重新解析'),
            ),
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'delete',
          child: Material(
            type: MaterialType.transparency,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.delete_outline_rounded, color: scheme.error),
              title: Text('删除', style: TextStyle(color: scheme.error)),
            ),
          ),
        ),
      ],
    );
  }
}
