import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/responsive_layout.dart';
import '../../core/network/api_client.dart';
import '../../core/network/sse_service.dart';
import '../../core/utils/safe_url_launcher.dart';
import '../../core/utils/toast.dart';
import '../../theme/design_tokens.dart';
import 'models/content.dart';
import 'models/content_template.dart';
import 'providers/collection_provider.dart';
import 'providers/content_actions_controller.dart';
import 'utils/content_parser.dart';
import 'widgets/detail/components/post_processing_status_panel.dart';
import 'widgets/detail/content_templates.dart';
import 'widgets/detail/detail_sections.dart';
import 'widgets/detail/gallery/gallery_navigation.dart';
import 'widgets/dialogs/edit_content_dialog.dart';
import 'widgets/list/collection_card_preview.dart';

/// 内容详情页。
///
/// 这是所有内容模板的唯一宿主。页面负责：来源证据、标题、动作层级、
/// 断点布局和后处理状态；模板只负责主体结构（见 [ContentTemplateBody]）。
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
      ref.invalidate(contentProcessingStatusProvider(widget.contentId));
    });
  }

  void _onScroll() {
    if (!mounted || _headerKeys.isEmpty) return;
    final now = DateTime.now();
    if (now.difference(_lastScrollCheck).inMilliseconds < 100) return;
    _lastScrollCheck = now;

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
    return Scaffold(
      appBar: AppBar(title: Text(preview?.title ?? '加载中')),
      body: preview == null
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: AspectRatio(
                  aspectRatio: 0.92,
                  child: CollectionCardPreview(
                    content: preview,
                    isTinyCardOverride: false,
                    mode: CollectionCardPreviewMode.detailLoading,
                  ),
                ),
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
        final images = ContentParser.extractAllImages(detail, apiBaseUrl);
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
                ? _buildTwoPane(templateContext)
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
      title: Text(
        (detail.title ?? '').trim().isEmpty ? '内容详情' : detail.title!.trim(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
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
      controller: _scrollController,
      padding: EdgeInsets.all(
        ctx.metrics.isCompact ? AppSpacing.md : AppSpacing.lg,
      ),
      children: [
        _SharedDetailHeader(detail: ctx.detail),
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
        ContentSupportingSections(
          detail: ctx.detail,
          processingPanel: PostProcessingStatusPanel(contentId: ctx.detail.id),
        ),
        const SizedBox(height: AppSpacing.xxl),
      ],
    );
  }

  Widget _buildTwoPane(TemplateContext ctx) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: ListView(
            controller: _scrollController,
            padding: const EdgeInsets.all(AppSpacing.xl),
            children: [
              _SharedDetailHeader(detail: ctx.detail),
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
        const VerticalDivider(width: 1),
        SizedBox(
          width: AppPane.supportingWidth,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              if (ctx.detail.template == ContentTemplate.article)
                ContentOutline(
                  detail: ctx.detail,
                  activeHeader: _activeHeader,
                  headerKeys: _headerKeys,
                ),
              ContentSupportingSections(
                detail: ctx.detail,
                processingPanel: PostProcessingStatusPanel(
                  contentId: ctx.detail.id,
                  initiallyExpanded: true,
                ),
              ),
            ],
          ),
        ),
      ],
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

/// 详情头：来源、标题、模板标识。
class _Header extends StatelessWidget {
  const _Header({required this.detail});

  final ContentDetail detail;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: ContentSourceLine(detail: detail)),
            TemplateBadge(detail: detail),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        ContentTitleBlock(detail: detail),
      ],
    );
  }
}

/// 详情页唯一的共享容器目标。它始终拥有不透明 tonal surface，避免飞行
/// 过程中透出正文；加载态与已加载态任一时刻也只会挂载一个同 tag Hero。
class _SharedDetailHeader extends StatelessWidget {
  const _SharedDetailHeader({required this.detail});

  final ContentDetail detail;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ContentSharedTransition(
      contentId: detail.id,
      child: Material(
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: AppShape.cardBorder,
          side: BorderSide(color: scheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: _Header(detail: detail),
        ),
      ),
    );
  }
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
