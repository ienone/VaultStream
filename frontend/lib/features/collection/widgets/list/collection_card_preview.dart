import '../../../../core/layout/workspace_geometry.dart';

import 'package:material_ui/material_ui.dart';

import 'collection_card_text.dart';

import 'package:intl/intl.dart';

import '../../../../core/widgets/network_thumbnail.dart';
import '../../../../theme/design_tokens.dart';
import '../../models/content.dart';
import '../../../../core/media/media_asset.dart';

class CollectionCardPreview extends StatefulWidget {
  const CollectionCardPreview({
    super.key,
    required this.content,
    required this.imageFailed,
    required this.onImageFailureChanged,
    this.onTap,
    this.isHovered = false,
    this.isEmphasized = false,
    this.trailingSpace = 0,
    this.transparentSurface = false,
    this.isList = false,
  });

  final ShareCard content;
  final bool imageFailed;
  final ValueChanged<bool> onImageFailureChanged;
  final VoidCallback? onTap;
  final bool isHovered;
  final bool isEmphasized;
  final double trailingSpace;
  final bool transparentSurface;
  final bool isList;

  @override
  State<CollectionCardPreview> createState() => _CollectionCardPreviewState();
}

class _CollectionCardPreviewState extends State<CollectionCardPreview> {
  int? _retryAssetId;

  @override
  Widget build(BuildContext context) {
    final content = widget.content;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final copy = CollectionCardText(content);
    final asset = content.mediaAssets.previewFor(content.contentType);
    final scale = MediaQuery.textScalerOf(context).scale(16) / 16;

    final updateImageFailure = widget.onImageFailureChanged;
    final metadata = _CardMeta(content: content);
    final text = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (copy.primary.isNotEmpty)
          Text(
            copy.primary,
            maxLines: copy.maxLines,
            overflow: TextOverflow.ellipsis,
            style: copy.hasTitle
                ? theme.textTheme.titleMedium
                : theme.textTheme.bodyMedium,
          ),
        if (copy.supporting.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            copy.supporting,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
        if (widget.imageFailed && asset != null)
          SizedBox(
            height: CollectionCardText.retryHeight(scale),
            child: TextButton(
              onPressed: () {
                _retryAssetId = asset.id;
                widget.onImageFailureChanged(false);
              },
              style: TextButton.styleFrom(
                minimumSize: const Size(48, 0),
                padding: const EdgeInsetsDirectional.only(end: AppSpacing.xs),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: theme.textTheme.labelMedium,
              ),
              child: const Text('重试图片'),
            ),
          ),
        if (_statusLabel != null) ...[
          const SizedBox(height: AppSpacing.xs),
          _StatusChip(label: _statusLabel!, isError: _statusIsError),
        ],
      ],
    );
    final media = asset == null || widget.imageFailed
        ? null
        : ClipRRect(
            borderRadius: AppShape.cardMediaBorder,
            child: CardMediaPreview(
              asset: asset,
              refreshBeforeLoad: _retryAssetId == asset.id,
              failureBuilder: (imageContext, _) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (imageContext.mounted) updateImageFailure(true);
                });
                return const SizedBox.shrink();
              },
            ),
          );
    return AnimatedContainer(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : AppMotion.stateChange,
      curve: AppMotion.standardCurve,
      decoration: BoxDecoration(
        borderRadius: AppShape.cardBorder,
        color: widget.transparentSurface
            ? Colors.transparent
            : widget.isEmphasized
            ? scheme.secondaryContainer
            : widget.isHovered
            ? scheme.surfaceContainerHighest
            : scheme.surfaceContainerLowest,
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: EdgeInsets.only(right: widget.trailingSpace),
                  child: metadata,
                ),
                const SizedBox(height: AppSpacing.xs),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      if (media == null) {
                        // 文字按自然行高排版；分栏动画的中间高度由卡片外框裁切。
                        return OverflowBox(
                          alignment: Alignment.topLeft,
                          minHeight: 0,
                          maxHeight: double.infinity,
                          child: text,
                        );
                      }
                      final textScale =
                          MediaQuery.textScalerOf(context).scale(16) / 16;
                      if (constraints.maxWidth / textScale < 200) return text;
                      final pane = WorkspaceGeometry.maybeOf(context);
                      final compact =
                          (pane?.overviewWidth ??
                              MediaQuery.sizeOf(context).width) <
                          600;
                      final progress = compact
                          ? 1.0
                          : (pane?.progress ?? (widget.isList ? 1.0 : 0.0));
                      final gridWidth = pane == null
                          ? constraints.maxWidth
                          : (pane.overviewWidth -
                                        24 -
                                        8 *
                                            ((pane.overviewWidth /
                                                        (300 * textScale))
                                                    .floor()
                                                    .clamp(1, 4) -
                                                1)) /
                                    (pane.overviewWidth / (300 * textScale))
                                        .floor()
                                        .clamp(1, 4) -
                                24;
                      final gridImageHeight = (gridWidth / 2.4).clamp(
                        80.0,
                        160.0,
                      );
                      final mediaWidth =
                          constraints.maxWidth +
                          (88 - constraints.maxWidth) * progress;
                      final mediaHeight =
                          gridImageHeight + (64 - gridImageHeight) * progress;
                      final textTop =
                          (gridImageHeight + AppSpacing.sm) * (1 - progress);
                      return SizedBox(
                        height: constraints.hasBoundedHeight
                            ? constraints.maxHeight
                            : textTop + 120 * textScale,
                        child: Stack(
                          children: [
                            Positioned(
                              top: 0,
                              right: 0,
                              width: mediaWidth,
                              height: mediaHeight,
                              child: IgnorePointer(child: media),
                            ),
                            Positioned(
                              top: textTop,
                              left: 0,
                              right: (88 + AppSpacing.sm) * progress,
                              child: text,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 只暴露对用户有行动价值的状态。
  String? get _statusLabel {
    if (widget.content.status == 'parse_failed') return '解析失败';
    if (widget.content.status == 'processing') return '解析中';
    if (widget.content.status == 'unprocessed') return '待解析';
    if (widget.content.isNsfw) return 'NSFW';
    return null;
  }

  bool get _statusIsError => widget.content.status == 'parse_failed';
}

class _CardMeta extends StatelessWidget {
  const _CardMeta({required this.content});
  final ShareCard content;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final date = content.publishedAt ?? content.createdAt;
    final author = content.authorName?.trim() ?? '';
    final hasWebSource = [
      'http',
      'https',
    ].contains(Uri.tryParse(content.url)?.scheme);
    final source = switch (content.platform.toLowerCase()) {
      'universal' => '网页',
      'bilibili' => '哔哩哔哩',
      'twitter' => 'X',
      'zhihu' => '知乎',
      'xiaohongshu' => '小红书',
      'weibo' => '微博',
      'telegram' => 'Telegram',
      _ => content.platform,
    };
    final platform = hasWebSource || content.platform == 'telegram'
        ? source
        : '';
    final avatarAsset = content.mediaAssets.firstFor(
      role: MediaRole.avatar,
      type: MediaType.image,
    );
    final avatarSources = avatarAsset?.sources ?? const <MediaSource>[];
    final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
    return SizedBox(
      height: 32 * scale,
      child: Row(
        children: [
          if (avatarSources.isNotEmpty) ...[
            ExcludeSemantics(
              child: ClipOval(
                child: NetworkThumbnail(
                  imageUrl: avatarSources.first.url,
                  fallbackUrls: avatarSources
                      .skip(1)
                      .map((s) => s.url)
                      .toList(),
                  mediaAsset: avatarAsset,
                  purpose: MediaPurpose.card,
                  width: 28,
                  height: 28,
                  maxWidthDiskCache: 96,
                  maxHeightDiskCache: 96,
                  errorIcon: Icons.person_outline_rounded,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
          ],
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  author.isNotEmpty ? author : platform,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
                if (author.isNotEmpty && platform.isNotEmpty)
                  Text(
                    platform,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.2,
                    ),
                  ),
              ],
            ),
          ),
          if (date != null) ...[
            const SizedBox(width: AppSpacing.xs),
            Text(
              DateFormat('MM-dd').format(date.toLocal()),
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.isError});

  final String label;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final background = isError
        ? scheme.errorContainer
        : scheme.surfaceContainerHighest;
    final foreground = isError
        ? scheme.onErrorContainer
        : scheme.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppShape.pill),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(color: foreground),
      ),
    );
  }
}
