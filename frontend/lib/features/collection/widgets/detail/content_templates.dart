import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/layout/responsive_layout.dart';
import '../../../../core/utils/safe_url_launcher.dart';
import '../../../../core/media/media_manifest_client.dart';
import '../../../../core/media/media_source_session.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/widgets/network_thumbnail.dart';
import '../../../../core/widgets/platform_badge.dart';
import '../../../../theme/design_tokens.dart';
import '../../models/content.dart';
import '../../models/content_template.dart';
import '../../models/header_line.dart';
import '../../../../core/media/media_asset.dart';
import '../../../player/global_playback_controller.dart';
import '../../../player/global_player_widgets.dart';
import '../../utils/content_parser.dart';
import '../renderers/payload_block_renderer.dart';
import 'components/media_grid.dart';
import 'components/rich_content.dart';
import 'components/tags_section.dart';
import 'components/unified_stats.dart';
import 'detail_sections.dart';

/// 模板渲染所需的上下文。
class TemplateContext {
  const TemplateContext({
    required this.detail,
    required this.metrics,
    required this.headerKeys,
    required this.images,
    required this.imageFallbacks,
    required this.imageAssets,
    required this.onImageTap,
    required this.onReParse,
    this.onResolveParseCandidate,
    this.initialPlaybackPosition,
    this.initialMediaAssetId,
  });

  final ContentDetail detail;
  final WindowMetrics metrics;
  final Map<String, GlobalKey> headerKeys;

  /// 已解析并映射为可访问 URL 的图片列表。
  final List<String> images;
  final Map<String, List<String>> imageFallbacks;
  final Map<String, MediaAsset> imageAssets;
  final void Function(int index) onImageTap;
  final VoidCallback onReParse;
  final Future<void> Function(String field, String action, String? mergedValue)?
  onResolveParseCandidate;
  final Duration? initialPlaybackPosition;
  final int? initialMediaAssetId;

  bool get isCompact => metrics.isCompact;

  bool get usesImmersiveMediaLayout {
    if (isCompact) return false;
    final hasVisualMedia =
        images.isNotEmpty || _playableMedia(this, audio: false).urls.isNotEmpty;
    if (!hasVisualMedia) return false;
    return switch (detail.template) {
      ContentTemplate.imageNote ||
      ContentTemplate.shortPost ||
      ContentTemplate.gallery ||
      ContentTemplate.profile => true,
      _ => false,
    };
  }
}

/// 模板主体分发。
///
/// 详情页只有这一个模板入口，不存在第二套并行详情实现。
class ContentTemplateBody extends StatelessWidget {
  const ContentTemplateBody({super.key, required this.context_});

  final TemplateContext context_;

  @override
  Widget build(BuildContext context) {
    return switch (context_.detail.template) {
      ContentTemplate.article => _ArticleBody(ctx: context_),
      ContentTemplate.imageNote => _ImageNoteBody(ctx: context_),
      ContentTemplate.shortPost => _ShortPostBody(ctx: context_),
      ContentTemplate.gallery => _GalleryBody(ctx: context_),
      ContentTemplate.video => _VideoBody(ctx: context_),
      ContentTemplate.audio => _AudioBody(ctx: context_),
      ContentTemplate.document => _DocumentBody(ctx: context_),
      ContentTemplate.collectionIndex => _CollectionIndexBody(ctx: context_),
      ContentTemplate.profile => _ProfileBody(ctx: context_),
      ContentTemplate.bookmark => _BookmarkBody(ctx: context_),
    };
  }
}

/// 媒体型内容的桌面阅读器：媒体占据左侧主舞台，右侧集中承载身份、
/// 标题、正文、统计和标签，避免再叠加第三列辅助栏。
class ImmersiveMediaDetail extends StatefulWidget {
  const ImmersiveMediaDetail({
    super.key,
    required this.context_,
    required this.sharedHeaderBuilder,
  });

  final TemplateContext context_;
  final Widget Function(Widget child) sharedHeaderBuilder;

  @override
  State<ImmersiveMediaDetail> createState() => _ImmersiveMediaDetailState();
}

class _ImmersiveMediaDetailState extends State<ImmersiveMediaDetail>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entryController = AnimationController(
    vsync: this,
    duration: AppMotion.containerTransform,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _entryController.value = 1;
    } else if (!_entryController.isAnimating && _entryController.value == 0) {
      _entryController.forward();
    }
  }

  @override
  void dispose() {
    _entryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctx = widget.context_;
    final scheme = Theme.of(context).colorScheme;
    final normalizedTitle = (ctx.detail.title ?? '').trim();
    final normalizedBody = (ctx.detail.body ?? '').trim();
    final titleRepeatsBody =
        ctx.detail.template == ContentTemplate.shortPost &&
        normalizedTitle.isNotEmpty &&
        normalizedBody.isNotEmpty &&
        (normalizedTitle == normalizedBody ||
            normalizedBody.startsWith(normalizedTitle));
    return Row(
      key: const ValueKey('immersive-media-detail'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(flex: 13, child: _ImmersiveMediaViewer(ctx: ctx)),
        VerticalDivider(width: 1, color: scheme.outlineVariant),
        Expanded(
          flex: 8,
          child: FadeTransition(
            key: const ValueKey('immersive-media-side-reveal'),
            opacity: CurvedAnimation(
              parent: _entryController,
              curve: const Interval(0.48, 1, curve: AppMotion.standardCurve),
            ),
            child: SlideTransition(
              position:
                  Tween<Offset>(
                    begin: const Offset(0.045, 0),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(
                      parent: _entryController,
                      curve: const Interval(
                        0.42,
                        1,
                        curve: AppMotion.standardCurve,
                      ),
                    ),
                  ),
              child: ColoredBox(
                color: scheme.surface,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      widget.sharedHeaderBuilder(
                        Material(
                          key: const ValueKey('immersive-media-shared-header'),
                          color: scheme.surfaceContainerLow,
                          shape: RoundedRectangleBorder(
                            borderRadius: AppShape.cardBorder,
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Padding(
                            padding: const EdgeInsets.all(AppSpacing.md),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                PlatformBadge(platform: ctx.detail.platform),
                                const SizedBox(height: AppSpacing.md),
                                ContentSourceLine(
                                  detail: ctx.detail,
                                  showPlatform: false,
                                  showOriginalAction: false,
                                ),
                                if (!titleRepeatsBody) ...[
                                  const SizedBox(height: AppSpacing.lg),
                                  ContentTitleBlock(
                                    detail: ctx.detail,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      _ImmersiveTextBody(ctx: ctx),
                      const SizedBox(height: AppSpacing.xl),
                      ContentSupportingSections(
                        detail: ctx.detail,
                        onResolveParseCandidate: ctx.onResolveParseCandidate,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ImmersiveTextBody extends StatelessWidget {
  const _ImmersiveTextBody({required this.ctx});

  final TemplateContext ctx;

  @override
  Widget build(BuildContext context) {
    final quoted = ctx.detail.richPayload?['quoted_content'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (ctx.detail.hasBody) _BodyText(ctx: ctx, hideMedia: true),
        if (quoted != null) ...[
          const SizedBox(height: AppSpacing.md),
          _QuotedContent(raw: quoted),
        ],
      ],
    );
  }
}

class _ImmersiveMediaViewer extends StatefulWidget {
  const _ImmersiveMediaViewer({required this.ctx});

  final TemplateContext ctx;

  @override
  State<_ImmersiveMediaViewer> createState() => _ImmersiveMediaViewerState();
}

class _ImmersiveMediaViewerState extends State<_ImmersiveMediaViewer> {
  late final PageController _controller = PageController();
  int _index = 0;
  bool _hovered = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goTo(int index) {
    _controller.animateToPage(
      index,
      duration: AppMotion.contentSwap,
      curve: AppMotion.standardCurve,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ctx = widget.ctx;
    final scheme = Theme.of(context).colorScheme;
    final playableVideo = _playableMedia(ctx, audio: false);
    if (ctx.images.isEmpty && playableVideo.urls.isNotEmpty) {
      return ColoredBox(
        key: const ValueKey('immersive-video-viewer'),
        color: scheme.surfaceContainerLowest,
        child: Center(
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: GlobalPlaybackSurface(
              request: _playbackRequest(ctx, playableVideo, audioOnly: false),
              initialPosition: ctx.initialPlaybackPosition,
            ),
          ),
        ),
      );
    }
    return MouseRegion(
      key: const ValueKey('immersive-media-viewer'),
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: ColoredBox(
        color: scheme.surfaceContainerLowest,
        child: Stack(
          fit: StackFit.expand,
          children: [
            PageView.builder(
              controller: _controller,
              itemCount: ctx.images.length,
              onPageChanged: (index) => setState(() => _index = index),
              itemBuilder: (context, index) {
                final image = ctx.images[index];
                return GestureDetector(
                  onTap: () => ctx.onImageTap(index),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      AppSpacing.md,
                      AppSpacing.md,
                      AppSpacing.md,
                      ctx.images.length > 1 ? 92 : AppSpacing.md,
                    ),
                    child: NetworkThumbnail(
                      imageUrl: image,
                      fallbackUrls: ctx.imageFallbacks[image] ?? const [],
                      mediaAsset: ctx.imageAssets[image],
                      purpose: MediaPurpose.detail,
                      fit: BoxFit.contain,
                    ),
                  ),
                );
              },
            ),
            if (ctx.images.length > 1) ...[
              Positioned(
                top: AppSpacing.md,
                right: AppSpacing.md,
                child: _PageCounter(index: _index, total: ctx.images.length),
              ),
              _HoverPageButton(
                key: const ValueKey('immersive-media-previous'),
                alignment: Alignment.centerLeft,
                icon: Icons.chevron_left_rounded,
                visible: _hovered && _index > 0,
                onPressed: () => _goTo(_index - 1),
              ),
              _HoverPageButton(
                key: const ValueKey('immersive-media-next'),
                alignment: Alignment.centerRight,
                icon: Icons.chevron_right_rounded,
                visible: _hovered && _index < ctx.images.length - 1,
                onPressed: () => _goTo(_index + 1),
              ),
              Positioned(
                left: 64,
                right: 64,
                bottom: AppSpacing.md,
                child: Center(
                  child: _ImmersiveThumbnailStrip(
                    images: ctx.images,
                    fallbacks: ctx.imageFallbacks,
                    mediaAssets: ctx.imageAssets,
                    selectedIndex: _index,
                    onSelected: _goTo,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PageCounter extends StatelessWidget {
  const _PageCounter({required this.index, required this.total});

  final int index;
  final int total;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _GlassMediaSurface(
      borderRadius: BorderRadius.circular(AppShape.pill),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xxs,
        ),
        child: Text(
          '${index + 1} / $total',
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: scheme.onPrimaryContainer),
        ),
      ),
    );
  }
}

class _HoverPageButton extends StatelessWidget {
  const _HoverPageButton({
    super.key,
    required this.alignment,
    required this.icon,
    required this.visible,
    required this.onPressed,
  });

  final Alignment alignment;
  final IconData icon;
  final bool visible;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: IgnorePointer(
          ignoring: !visible,
          child: AnimatedOpacity(
            duration: AppMotion.stateChange,
            opacity: visible ? 1 : 0,
            child: _GlassMediaSurface(
              borderRadius: BorderRadius.circular(AppRadius.xl),
              child: IconButton(
                tooltip: icon == Icons.chevron_left_rounded ? '上一张' : '下一张',
                onPressed: onPressed,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
                icon: Icon(icon),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ImmersiveThumbnailStrip extends StatelessWidget {
  const _ImmersiveThumbnailStrip({
    required this.images,
    required this.fallbacks,
    required this.mediaAssets,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<String> images;
  final Map<String, List<String>> fallbacks;
  final Map<String, MediaAsset> mediaAssets;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _GlassMediaSurface(
      key: const ValueKey('immersive-media-thumbnails'),
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 68),
        child: ListView.separated(
          shrinkWrap: true,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.all(AppSpacing.xs),
          itemCount: images.length,
          separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.xs),
          itemBuilder: (context, index) {
            final image = images[index];
            final selected = selectedIndex == index;
            return Tooltip(
              message: '第 ${index + 1} 张',
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                onTap: () => onSelected(index),
                child: AnimatedContainer(
                  duration: AppMotion.stateChange,
                  width: selected ? 58 : 48,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: Border.all(
                      color: selected
                          ? scheme.primary
                          : scheme.onPrimaryContainer.withValues(alpha: 0.16),
                      width: selected ? 2 : 0.5,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: NetworkThumbnail(
                    imageUrl: image,
                    fallbackUrls: fallbacks[image] ?? const [],
                    mediaAsset: mediaAssets[image],
                    purpose: MediaPurpose.detail,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _GlassMediaSurface extends StatelessWidget {
  const _GlassMediaSurface({
    super.key,
    required this.child,
    required this.borderRadius,
  });

  final Widget child;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.primaryContainer.withValues(alpha: 0.35),
            borderRadius: borderRadius,
            border: Border.all(
              color: scheme.onPrimaryContainer.withValues(alpha: 0.15),
              width: 0.5,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

// --- 共享片段 ---

/// 正文。缺失时给出与模板相符的空状态，不用摘要顶替原文。
class _BodyText extends StatelessWidget {
  const _BodyText({
    required this.ctx,
    this.emptyMessage,
    this.hideMedia = true,
  });

  final TemplateContext ctx;
  final String? emptyMessage;
  final bool hideMedia;

  @override
  Widget build(BuildContext context) {
    final detail = ctx.detail;
    if (!detail.hasBody) {
      if (detail.isParseFailed || detail.isParsePending) {
        // 解析横幅已经解释了原因，这里不重复报错。
        return const SizedBox.shrink();
      }
      return ContentEmptyState(
        icon: Icons.notes_rounded,
        message: emptyMessage ?? '这条内容没有正文',
      );
    }

    return RichContent(
      detail: detail,
      headerKeys: ctx.headerKeys,
      useHero: false,
      hideMedia: hideMedia,
    );
  }
}

/// 媒体网格。仅主要媒体缺失时显示空态。
class _MediaBlock extends StatelessWidget {
  const _MediaBlock({required this.ctx, this.emptyMessage});

  final TemplateContext ctx;
  final String? emptyMessage;

  @override
  Widget build(BuildContext context) {
    if (ctx.images.isEmpty) {
      return ContentEmptyState(
        icon: Icons.image_not_supported_outlined,
        message: emptyMessage ?? '没有归档的图片',
      );
    }

    return MediaGrid(
      images: ctx.images,
      fallbackUrlsByImage: ctx.imageFallbacks,
      mediaAssetsByImage: ctx.imageAssets,
      contentId: ctx.detail.id,
      onImageTap: ctx.onImageTap,
      isLandscape: false,
    );
  }
}

/// 可选封面只在有可访问资产时占据空间。
class _CoverBlock extends StatelessWidget {
  const _CoverBlock({required this.ctx, this.aspectRatio = 16 / 9, this.width});

  final TemplateContext ctx;
  final double aspectRatio;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final asset = ctx.detail.mediaAssets
        .where(
          (asset) =>
              asset.mediaType == MediaType.image &&
              (asset.role == MediaRole.cover ||
                  asset.role == MediaRole.poster) &&
              asset.sources.isNotEmpty,
        )
        .firstOrNull;
    if (asset == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: SizedBox(
        width: width,
        child: ClipRRect(
          borderRadius: AppShape.paneBorder,
          child: AspectRatio(
            aspectRatio: aspectRatio,
            child: NetworkThumbnail(
              imageUrl: asset.sources.first.url,
              fallbackUrls: asset.sources
                  .skip(1)
                  .map((source) => source.url)
                  .toList(),
              mediaAsset: asset,
              purpose: MediaPurpose.detail,
              fit: BoxFit.cover,
            ),
          ),
        ),
      ),
    );
  }
}

/// 从统一媒体资产中挑出可播放的媒体。没有则返回空列表。
({MediaAsset? asset, List<String> urls}) _playableMedia(
  TemplateContext ctx, {
  required bool audio,
}) {
  final type = audio ? MediaType.audio : MediaType.video;
  for (final asset in ctx.detail.mediaAssets) {
    if (asset.mediaType == type &&
        asset.sources.isNotEmpty &&
        (ctx.initialMediaAssetId == null ||
            asset.id == ctx.initialMediaAssetId)) {
      return (
        asset: asset,
        urls: asset.sources.map((source) => source.url).toList(growable: false),
      );
    }
  }
  return (asset: null, urls: const []);
}

// --- 模板主体 ---

/// 文章：连续阅读为主，正文限宽。
class _ArticleBody extends StatelessWidget {
  const _ArticleBody({required this.ctx});

  final TemplateContext ctx;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _BodyText(ctx: ctx, hideMedia: false),
        if (ctx.images.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xl),
          const DetailSectionHeader(title: '文内媒体'),
          _MediaBlock(ctx: ctx),
        ],
      ],
    );
  }
}

/// 用户上传的原始文档或附件。这里不伪装成已经完成 OCR 的正文，
/// 只展示保存说明并提供签名原文件入口。
class _DocumentBody extends StatelessWidget {
  const _DocumentBody({required this.ctx});

  final TemplateContext ctx;

  @override
  Widget build(BuildContext context) {
    final attachments = ctx.detail.mediaAssets
        .where(
          (asset) =>
              (asset.mediaType == MediaType.document ||
                  asset.mediaType == MediaType.other) &&
              asset.sources.isNotEmpty,
        )
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (ctx.detail.hasBody) ...[
          const DetailSectionHeader(title: '保存说明'),
          _BodyText(ctx: ctx),
          const SizedBox(height: AppSpacing.lg),
        ],
        const DetailSectionHeader(title: '原始文件'),
        if (attachments.isEmpty)
          const ContentEmptyState(
            icon: Icons.file_present_outlined,
            message: '没有可打开的归档文件',
            hint: '文件可能仍在处理，或归档未成功。',
          )
        else
          ...attachments.map(
            (asset) => _DocumentAttachmentTile(
              key: ValueKey('document-attachment-${asset.id}'),
              asset: asset,
            ),
          ),
      ],
    );
  }
}

class _DocumentAttachmentTile extends ConsumerStatefulWidget {
  const _DocumentAttachmentTile({super.key, required this.asset});

  final MediaAsset asset;

  @override
  ConsumerState<_DocumentAttachmentTile> createState() =>
      _DocumentAttachmentTileState();
}

class _DocumentAttachmentTileState
    extends ConsumerState<_DocumentAttachmentTile> {
  late MediaSourceSession _session;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _session = MediaSourceSession.fromAsset(widget.asset);
  }

  @override
  void didUpdateWidget(covariant _DocumentAttachmentTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.asset != widget.asset) {
      _session = MediaSourceSession.fromAsset(widget.asset);
      _busy = false;
      _error = null;
    }
  }

  Future<void> _open() async {
    if (_busy) return;
    if (_error != null) _session.resetForManualRetry();
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      if (_session.currentSignatureExpired()) {
        _session.markAutomaticRefreshAttempted();
        try {
          final refreshed = await refreshMediaManifest(
            ref.read(apiClientProvider),
            assetId: widget.asset.id,
            purpose: MediaPurpose.detail,
          );
          if (!mounted) return;
          _session.replaceManifest(refreshed);
        } catch (_) {
          if (!_session.moveNext()) {
            if (mounted) setState(() => _error = '媒体授权刷新失败');
            return;
          }
        }
      }

      final source = _session.current;
      if (source == null) {
        if (mounted) setState(() => _error = '归档文件当前不可用');
        return;
      }
      await SafeUrlLauncher.openExternal(context, source.url);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final firstSource = widget.asset.sources.firstOrNull;
    final rawName = widget.asset.metadata['filename']?.toString().trim();
    final name = rawName == null || rawName.isEmpty ? '归档文件' : rawName;
    final size =
        firstSource?.sizeBytes ??
        (widget.asset.metadata['size_bytes'] as num?)?.toInt();
    final metadata = [
      if (firstSource?.mimeType != null) firstSource!.mimeType!,
      if (size != null) _formatFileSize(size),
    ].join(' · ');

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ListTile(
        leading: const Icon(Icons.description_outlined),
        title: Text(name),
        subtitle: Text(
          [
            if (metadata.isNotEmpty) metadata,
            if (_error != null) _error!,
          ].join('\n'),
        ),
        trailing: _busy
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(
                _error == null
                    ? Icons.open_in_new_rounded
                    : Icons.error_outline_rounded,
              ),
        onTap: _busy ? null : _open,
      ),
    );
  }
}

String _formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kib = bytes / 1024;
  if (kib < 1024) return '${kib.toStringAsFixed(kib < 10 ? 1 : 0)} KB';
  final mib = kib / 1024;
  return '${mib.toStringAsFixed(mib < 10 ? 1 : 0)} MB';
}

class _ImageNoteMediaViewer extends StatefulWidget {
  const _ImageNoteMediaViewer({required this.ctx});

  final TemplateContext ctx;

  @override
  State<_ImageNoteMediaViewer> createState() => _ImageNoteMediaViewerState();
}

class _ImageNoteMediaViewerState extends State<_ImageNoteMediaViewer> {
  late final PageController _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctx = widget.ctx;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        AspectRatio(
          aspectRatio: 4 / 5,
          child: ClipRRect(
            borderRadius: AppShape.paneBorder,
            child: Stack(
              fit: StackFit.expand,
              children: [
                PageView.builder(
                  controller: _controller,
                  itemCount: ctx.images.length,
                  onPageChanged: (index) => setState(() => _index = index),
                  itemBuilder: (context, index) {
                    final image = ctx.images[index];
                    return GestureDetector(
                      onTap: () => ctx.onImageTap(index),
                      child: NetworkThumbnail(
                        imageUrl: image,
                        fallbackUrls: ctx.imageFallbacks[image] ?? const [],
                        mediaAsset: ctx.imageAssets[image],
                        purpose: MediaPurpose.detail,
                        fit: BoxFit.contain,
                      ),
                    );
                  },
                ),
                if (ctx.images.length > 1)
                  Positioned(
                    top: AppSpacing.sm,
                    right: AppSpacing.sm,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xs,
                        vertical: AppSpacing.xxs,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.inverseSurface.withValues(alpha: 0.72),
                        borderRadius: BorderRadius.circular(AppShape.pill),
                      ),
                      child: Text(
                        '${_index + 1} / ${ctx.images.length}',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onInverseSurface,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (ctx.images.length > 1) ...[
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            height: 64,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: ctx.images.length,
              separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.xs),
              itemBuilder: (context, index) {
                final image = ctx.images[index];
                final selected = index == _index;
                return InkWell(
                  borderRadius: AppShape.cardMediaBorder,
                  onTap: () => _controller.animateToPage(
                    index,
                    duration: AppMotion.contentSwap,
                    curve: AppMotion.standardCurve,
                  ),
                  child: AnimatedContainer(
                    duration: AppMotion.stateChange,
                    width: selected ? 76 : 58,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: selected
                            ? scheme.primary
                            : scheme.outlineVariant,
                        width: selected ? 2 : 1,
                      ),
                      borderRadius: AppShape.cardMediaBorder,
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: NetworkThumbnail(
                      imageUrl: image,
                      fallbackUrls: ctx.imageFallbacks[image] ?? const [],
                      mediaAsset: ctx.imageAssets[image],
                      purpose: MediaPurpose.detail,
                      fit: BoxFit.cover,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}

/// 图文笔记：文字与图片交错，两者的对应关系是主体。
class _ImageNoteBody extends StatelessWidget {
  const _ImageNoteBody({required this.ctx});

  final TemplateContext ctx;

  @override
  Widget build(BuildContext context) {
    if (!ctx.isCompact && ctx.images.isNotEmpty && ctx.detail.hasBody) {
      return LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 720) {
            return Row(
              key: const ValueKey('image-note-split-layout'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 6, child: _ImageNoteMediaViewer(ctx: ctx)),
                const SizedBox(width: AppSpacing.xl),
                Expanded(
                  flex: 4,
                  child: Container(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerLow,
                      borderRadius: AppShape.paneBorder,
                    ),
                    child: _BodyText(ctx: ctx, emptyMessage: '这条笔记没有文字说明'),
                  ),
                ),
              ],
            );
          }
          return _ImageNoteStack(ctx: ctx);
        },
      );
    }
    return _ImageNoteStack(ctx: ctx);
  }
}

class _ImageNoteStack extends StatelessWidget {
  const _ImageNoteStack({required this.ctx});

  final TemplateContext ctx;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (ctx.images.isNotEmpty) ...[
          _MediaBlock(ctx: ctx),
          if (ctx.detail.hasBody) const SizedBox(height: AppSpacing.lg),
        ],
        if (ctx.detail.hasBody || ctx.images.isEmpty)
          _BodyText(ctx: ctx, emptyMessage: '没有归档的笔记内容'),
      ],
    );
  }
}

/// 短帖子：紧凑，作者与来源是重点，不套用长文排版。
class _ShortPostBody extends StatelessWidget {
  const _ShortPostBody({required this.ctx});

  final TemplateContext ctx;

  @override
  Widget build(BuildContext context) {
    final quoted = ctx.detail.richPayload?['quoted_content'];
    final scheme = Theme.of(context).colorScheme;

    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: DecoratedBox(
          key: const ValueKey('short-post-compact-body'),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: AppShape.paneBorder,
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (ctx.detail.hasBody ||
                    (quoted == null && ctx.images.isEmpty))
                  _BodyText(ctx: ctx, emptyMessage: '没有归档的帖子内容'),
                if (quoted != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  _QuotedContent(raw: quoted),
                ],
                if (ctx.images.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  _MediaBlock(ctx: ctx),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 引用/转发内容。保留转发者与原内容的边界。
class _QuotedContent extends StatelessWidget {
  const _QuotedContent({required this.raw});

  final Object raw;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final quote = _quoteData(raw);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: AppShape.paneBorder,
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.format_quote_rounded,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.xxs),
              Text(
                '引用内容',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          if (quote.author.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              quote.author,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (quote.body.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            SelectableText(
              quote.body,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.55),
            ),
          ],
          if (quote.url.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            ActionChip(
              avatar: const Icon(Icons.open_in_new_rounded, size: 16),
              label: const Text('查看引用原文'),
              onPressed: () => SafeUrlLauncher.openExternal(context, quote.url),
            ),
          ],
        ],
      ),
    );
  }

  _QuoteData _quoteData(Object? value) {
    if (value is String) return _QuoteData(body: value.trim());
    if (value is Map) {
      final author =
          value['author_name'] ?? value['author'] ?? value['username'];
      final body =
          value['text'] ?? value['body'] ?? value['content'] ?? value['title'];
      final url = value['url'];
      return _QuoteData(
        author: author?.toString().trim() ?? '',
        body: body?.toString().trim() ?? '',
        url: url?.toString().trim() ?? '',
      );
    }
    if (value is List) {
      return _QuoteData(
        body: value
            .map((item) => _quoteData(item).body)
            .where((text) => text.isNotEmpty)
            .join('\n\n'),
      );
    }
    return _QuoteData(body: value?.toString().trim() ?? '');
  }
}

class _QuoteData {
  const _QuoteData({this.author = '', this.body = '', this.url = ''});

  final String author;
  final String body;
  final String url;
}

/// 图集：媒体本身是主体，文字是补充。
class _GalleryBody extends StatelessWidget {
  const _GalleryBody({required this.ctx});

  final TemplateContext ctx;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _MediaBlock(ctx: ctx, emptyMessage: '这个图集没有可显示的图片'),
        if (ctx.detail.hasBody) ...[
          const SizedBox(height: AppSpacing.lg),
          const DetailSectionHeader(title: '说明'),
          _BodyText(ctx: ctx),
        ],
      ],
    );
  }
}

/// 视频。
///
/// 当前多数平台适配器只归档封面和元数据，不保存原视频，
/// 因此必须显式表达"没有本地视频"，并提供回到来源的入口。
class _VideoBody extends StatelessWidget {
  const _VideoBody({required this.ctx});

  final TemplateContext ctx;

  @override
  Widget build(BuildContext context) {
    final playable = _playableMedia(ctx, audio: false);
    final playbackRequest = playable.urls.isEmpty
        ? null
        : _playbackRequest(ctx, playable, audioOnly: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (playbackRequest != null) ...[
          ClipRRect(
            borderRadius: AppShape.paneBorder,
            child: GlobalPlaybackSurface(
              request: playbackRequest,
              initialPosition: ctx.initialPlaybackPosition,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          PlaybackSegmentList(request: playbackRequest),
        ] else ...[
          _CoverBlock(ctx: ctx),
          ContentEmptyState(
            icon: Icons.smart_display_outlined,
            message: '没有归档视频文件',
            action: ctx.detail.hasExternalOriginal
                ? FilledButton.tonalIcon(
                    onPressed: () =>
                        SafeUrlLauncher.openExternal(context, ctx.detail.url),
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: const Text('到来源观看'),
                  )
                : null,
          ),
        ],
        if (ContentParser.getMarkdownContent(ctx.detail).trim().isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          const DetailSectionHeader(title: '简介'),
          _BodyText(ctx: ctx),
        ],
      ],
    );
  }
}

/// 音频与播客。
///
/// 播放由全局会话持有；离开详情后由 Root Shell 的 mini player 继续承接。
class _AudioBody extends StatelessWidget {
  const _AudioBody({required this.ctx});

  final TemplateContext ctx;

  @override
  Widget build(BuildContext context) {
    final playable = _playableMedia(ctx, audio: true);
    final playbackRequest = playable.urls.isEmpty
        ? null
        : _playbackRequest(ctx, playable, audioOnly: true);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CoverBlock(ctx: ctx, aspectRatio: 1, width: ctx.isCompact ? 120 : 160),
        if (playbackRequest != null) ...[
          GlobalPlaybackSurface(
            request: playbackRequest,
            initialPosition: ctx.initialPlaybackPosition,
          ),
          const SizedBox(height: AppSpacing.md),
          PlaybackSegmentList(request: playbackRequest),
        ] else
          ContentEmptyState(
            icon: Icons.music_off_outlined,
            message: '没有归档音频文件',
            action: ctx.detail.hasExternalOriginal
                ? FilledButton.tonalIcon(
                    onPressed: () =>
                        SafeUrlLauncher.openExternal(context, ctx.detail.url),
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: const Text('到来源收听'),
                  )
                : null,
          ),
        if (ContentParser.getMarkdownContent(ctx.detail).trim().isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          const DetailSectionHeader(title: '内容说明'),
          _BodyText(ctx: ctx),
        ],
      ],
    );
  }
}

PlaybackRequest _playbackRequest(
  TemplateContext ctx,
  ({List<String> urls, MediaAsset? asset}) playable, {
  required bool audioOnly,
}) => PlaybackRequest(
  contentId: ctx.detail.id,
  title: (ctx.detail.title ?? '').trim().isEmpty
      ? '内容 ${ctx.detail.id}'
      : ctx.detail.title!.trim(),
  urls: playable.urls,
  audioOnly: audioOnly,
  mediaAsset: playable.asset,
  segments: ctx.detail.mediaSegments,
);

/// 聚合页：知乎问题、收藏夹等，成员条目是主体。
class _CollectionIndexBody extends StatelessWidget {
  const _CollectionIndexBody({required this.ctx});

  final TemplateContext ctx;

  @override
  Widget build(BuildContext context) {
    final blocks = ctx.detail.richPayload?['blocks'];
    final hasMembers = blocks is List && blocks.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (ctx.detail.hasBody) ...[
          _BodyText(ctx: ctx),
          const SizedBox(height: AppSpacing.lg),
        ],
        DetailSectionHeader(
          title: '收录条目',
          trailing: hasMembers
              ? Text(
                  '${(blocks).length} 条',
                  style: Theme.of(context).textTheme.labelMedium,
                )
              : null,
        ),
        if (hasMembers)
          PayloadBlockRenderer(content: ctx.detail)
        else
          const ContentEmptyState(
            icon: Icons.list_alt_rounded,
            message: '没有归档的成员条目',
          ),
      ],
    );
  }
}

/// 平台账号主页。
class _ProfileBody extends StatelessWidget {
  const _ProfileBody({required this.ctx});

  final TemplateContext ctx;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (ctx.detail.hasBody) ...[
          const DetailSectionHeader(title: '简介'),
          _BodyText(ctx: ctx),
        ],
        if (ctx.images.isNotEmpty) ...[
          if (ctx.detail.hasBody) const SizedBox(height: AppSpacing.lg),
          const DetailSectionHeader(title: '主页媒体'),
          _MediaBlock(ctx: ctx),
        ],
      ],
    );
  }
}

/// 书签：只记录链接和"为什么保存"，并提供升级解析入口。
class _BookmarkBody extends ConsumerWidget {
  const _BookmarkBody({required this.ctx});

  final TemplateContext ctx;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final detail = ctx.detail;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            borderRadius: AppShape.paneBorder,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '链接',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              SelectableText(
                detail.cleanUrl ?? detail.url,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.xs,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: () =>
                        SafeUrlLauncher.openExternal(context, detail.url),
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: const Text('打开链接'),
                  ),
                  OutlinedButton.icon(
                    onPressed: ctx.onReParse,
                    icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
                    label: const Text('尝试解析正文'),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (detail.hasBody) ...[
          const SizedBox(height: AppSpacing.lg),
          const DetailSectionHeader(title: '保存时的记录'),
          _BodyText(ctx: ctx),
        ],
      ],
    );
  }
}

/// 侧栏 / 底部的次要信息。所有模板共用同一组，顺序稳定。
class ContentSupportingSections extends StatelessWidget {
  const ContentSupportingSections({
    super.key,
    required this.detail,
    this.onResolveParseCandidate,
    this.showStats = true,
  });

  final ContentDetail detail;
  final Future<void> Function(String field, String action, String? mergedValue)?
  onResolveParseCandidate;
  final bool showStats;

  @override
  Widget build(BuildContext context) {
    final hasTags = detail.tags.isNotEmpty || detail.sourceTags.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ParseCandidatePanel(
          detail: detail,
          onResolve:
              onResolveParseCandidate ?? (field, action, mergedValue) async {},
        ),
        if (detail.manualEditFields.isNotEmpty)
          const SizedBox(height: AppSpacing.md),
        if (detail.hasSummary) ...[
          ContentSummaryBlock(detail: detail),
          const SizedBox(height: AppSpacing.md),
        ],
        if (showStats) ...[UnifiedStats(detail: detail)],
        if (hasTags) ...[
          const SizedBox(height: AppSpacing.md),
          TagsSection(detail: detail),
        ],
      ],
    );
  }
}

/// 目录。仅文章模板在宽屏使用。
class ContentOutline extends StatelessWidget {
  const ContentOutline({
    super.key,
    required this.detail,
    required this.activeHeader,
    required this.headerKeys,
  });

  final ContentDetail detail;
  final String? activeHeader;
  final Map<String, GlobalKey> headerKeys;

  @override
  Widget build(BuildContext context) {
    final headers = ContentParser.extractHeaders(
      ContentParser.getMarkdownContent(detail),
    );
    if (headers.isEmpty) return const SizedBox.shrink();
    final minimumLevel = headers
        .map((header) => header.level)
        .reduce((left, right) => left < right ? left : right);

    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('content-detail-outline-surface'),
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: AppShape.paneBorder,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const DetailSectionHeader(title: '目录'),
          const SizedBox(height: AppSpacing.xs),
          for (final header in headers)
            _OutlineEntry(
              header: header,
              depth: (header.level - minimumLevel).clamp(0, 3),
              active: activeHeader == header.uniqueId,
              onTap: () => _scrollTo(header.uniqueId),
            ),
        ],
      ),
    );
  }

  void _scrollTo(String headerId) {
    final target = headerKeys[headerId]?.currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(
      target,
      duration: AppMotion.contentSwap,
      curve: AppMotion.standardCurve,
    );
  }
}

class _OutlineEntry extends StatelessWidget {
  const _OutlineEntry({
    required this.header,
    required this.depth,
    required this.active,
    required this.onTap,
  });

  final HeaderLine header;
  final int depth;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseStyle = switch (depth) {
      0 => theme.textTheme.bodyMedium,
      1 => theme.textTheme.bodySmall,
      _ => theme.textTheme.labelMedium,
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        onTap: onTap,
        child: AnimatedContainer(
          duration: AppMotion.stateChange,
          curve: AppMotion.standardCurve,
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(
            AppSpacing.sm + depth * AppSpacing.sm,
            depth == 0 ? AppSpacing.xs : 6,
            AppSpacing.sm,
            depth == 0 ? AppSpacing.xs : 6,
          ),
          decoration: BoxDecoration(
            color: active
                ? theme.colorScheme.secondaryContainer.withValues(alpha: 0.55)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Text(
            header.text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: baseStyle?.copyWith(
              height: 1.35,
              color: active
                  ? theme.colorScheme.onSecondaryContainer
                  : depth == 0
                  ? theme.colorScheme.onSurface
                  : theme.colorScheme.onSurfaceVariant,
              fontWeight: active || depth == 0
                  ? FontWeight.w700
                  : depth == 1
                  ? FontWeight.w500
                  : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}
