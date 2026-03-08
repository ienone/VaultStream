// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:gap/gap.dart';
import '../../core/widgets/frosted_app_bar.dart';
import '../../core/utils/toast.dart';
import '../../core/utils/safe_url_launcher.dart';
import '../../core/network/api_client.dart';
import '../collection/models/header_line.dart';
import '../collection/utils/content_parser.dart';
import '../collection/widgets/detail/components/content_side_info_card.dart';
import '../collection/widgets/detail/components/rich_content.dart';
import '../collection/widgets/detail/gallery/full_screen_gallery.dart';
import '../collection/widgets/detail/layout/gallery_landscape_layout.dart';
import 'models/discovery_models.dart';
import 'providers/discovery_items_provider.dart';
import 'providers/discovery_actions_provider.dart';

class DiscoveryDetailPage extends ConsumerWidget {
  final int itemId;
  final bool isEmbedded;

  const DiscoveryDetailPage({
    super.key,
    required this.itemId,
    this.isEmbedded = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(discoveryItemDetailProvider(itemId));

    if (isEmbedded) {
      return detailAsync.when(
        data: (item) => _EmbeddedDetailContent(item: item),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: Theme.of(context).colorScheme.error,
              ),
              const Gap(16),
              Text('加载失败: $err'),
              const Gap(16),
              ElevatedButton(
                onPressed: () =>
                    ref.invalidate(discoveryItemDetailProvider(itemId)),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    return detailAsync.when(
      data: (item) => _FullDetailScaffold(item: item),
      loading: () => Scaffold(
        appBar: const FrostedAppBar(title: Text('详情')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (err, _) => Scaffold(
        appBar: const FrostedAppBar(title: Text('详情')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: Theme.of(context).colorScheme.error,
              ),
              const Gap(16),
              Text('加载失败: $err'),
              const Gap(16),
              ElevatedButton(
                onPressed: () =>
                    ref.invalidate(discoveryItemDetailProvider(itemId)),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- Embedded detail (desktop right panel) ---
class _EmbeddedDetailContent extends ConsumerWidget {
  final DiscoveryItem item;
  const _EmbeddedDetailContent({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _DesktopDetailBody(item: item).animate().fadeIn(duration: 200.ms);
  }
}

// --- Full scaffold detail (mobile) ---
class _FullDetailScaffold extends ConsumerWidget {
  final DiscoveryItem item;
  const _FullDetailScaffold({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: FrostedAppBar(
        blurSigma: 12,
        title: Text(
          item.title ?? '详情',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton.filledTonal(
            tooltip: '收藏',
            onPressed: () async {
              try {
                await ref
                    .read(discoveryActionsProvider.notifier)
                    .promoteItem(item.id);
                if (context.mounted) {
                  Toast.show(
                    context,
                    '已收藏',
                    icon: Icons.check_circle_outline_rounded,
                  );
                  Navigator.of(context).pop();
                }
              } catch (e) {
                if (context.mounted) {
                  Toast.show(context, '操作失败: $e', isError: true);
                }
              }
            },
            icon: const Icon(Icons.bookmark_add_rounded, size: 20),
          ),
          const SizedBox(width: 4),
          IconButton.filledTonal(
            tooltip: '移出发现区',
            onPressed: () async {
              try {
                await ref
                    .read(discoveryActionsProvider.notifier)
                    .ignoreItem(item.id);
                if (context.mounted) {
                  Toast.show(
                    context,
                    '已移出发现区',
                    icon: Icons.check_circle_outline_rounded,
                  );
                  Navigator.of(context).pop();
                }
              } catch (e) {
                if (context.mounted) {
                  Toast.show(context, '操作失败: $e', isError: true);
                }
              }
            },
            icon: const Icon(Icons.visibility_off_rounded, size: 20),
          ),
          const SizedBox(width: 4),
          IconButton.filledTonal(
            tooltip: '查看原文',
            onPressed: () => SafeUrlLauncher.openExternal(context, item.url),
            icon: const Icon(Icons.open_in_new_rounded, size: 20),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + kToolbarHeight + 16,
          left: 16,
          right: 16,
          bottom: 32,
        ),
        child: _DetailBody(item: item),
      ),
    ).animate().fadeIn(duration: 300.ms);
  }
}

// --- Shared detail body ---
class _DetailBody extends ConsumerWidget {
  final DiscoveryItem item;
  const _DetailBody({required this.item});

  Color _scoreColor(double score) {
    if (score >= 8) return Colors.green;
    if (score >= 6) return Colors.amber.shade700;
    return Colors.grey;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final contentDetail = item.toContentDetail();
    final headerKeys = <String, GlobalKey>{};
    final headers = ContentParser.extractHeaders(
      ContentParser.getMarkdownContent(contentDetail),
    );

    final dio = ref.read(apiClientProvider);
    final apiBaseUrl = dio.options.baseUrl;
    final apiToken = dio.options.headers['X-API-Token']?.toString();

    return SelectionArea(
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DiscoveryMetaWrap(item: item, scoreColor: _scoreColor),
        const Gap(16),
        ContentSideInfoCard(detail: contentDetail),
        const Gap(24),
        RichContent(
          detail: contentDetail,
          apiBaseUrl: apiBaseUrl,
          apiToken: apiToken,
          headerKeys: headerKeys,
          useHero: false,
        ),
        if (headers.isNotEmpty) ...[
          const Gap(16),
          _DiscoveryTocCard(headers: headers, headerKeys: headerKeys),
        ],

        if (item.aiReason != null && item.aiReason!.isNotEmpty) ...[
          const Gap(16),
          _SectionCard(
            title: 'AI 分析',
            icon: Icons.auto_awesome_rounded,
            child: Text(
              item.aiReason!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                height: 1.6,
              ),
            ),
          ),
        ],
        if (item.aiTags != null && item.aiTags!.isNotEmpty) ...[
          const Gap(16),
          _SectionCard(
            title: '标签',
            icon: Icons.sell_rounded,
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: item.aiTags!
                  .map(
                    (tag) => Chip(
                      label: Text(tag),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ],
    ),
  );
  }
}

// --- Desktop detail body (LayoutBuilder-aware; gallery uses GalleryLandscapeLayout) ---
class _DesktopDetailBody extends ConsumerStatefulWidget {
  final DiscoveryItem item;

  const _DesktopDetailBody({required this.item});

  @override
  ConsumerState<_DesktopDetailBody> createState() => _DesktopDetailBodyState();
}

class _DesktopDetailBodyState extends ConsumerState<_DesktopDetailBody> {
  final _imagePageController = PageController();
  int _currentImageIndex = 0;

  @override
  void dispose() {
    _imagePageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dio = ref.read(apiClientProvider);
    final apiBaseUrl = dio.options.baseUrl;
    final apiToken = dio.options.headers['X-API-Token']?.toString();
    final contentDetail = widget.item.toContentDetail();
    final headerKeys = <String, GlobalKey>{};

    return LayoutBuilder(
      builder: (context, constraints) {
        // Gallery / video: 小红书 style — left image carousel, right info
        final effectiveLayout = ContentParser.getEffectiveLayoutType(contentDetail);
        if (effectiveLayout == 'gallery' || effectiveLayout == 'video') {
          final images =
              ContentParser.extractAllImages(contentDetail, apiBaseUrl);
          return SelectionArea(
            child: GalleryLandscapeLayout(
              detail: contentDetail,
              apiBaseUrl: apiBaseUrl,
              apiToken: apiToken,
              images: images,
              imagePageController: _imagePageController,
              currentImageIndex: _currentImageIndex,
              onImageTap: (idx) => _showFullScreen(
                  context, images, idx, apiBaseUrl, apiToken, contentDetail.id),
              onPageChanged: (idx) {
                if (mounted) setState(() => _currentImageIndex = idx);
              },
              headerKeys: headerKeys,
            ),
          );
        }

        // Article / other: two-column — left RichContent, right sidebar
        final headers = ContentParser.extractHeaders(
          ContentParser.getMarkdownContent(contentDetail),
        );
        return SelectionArea(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 13,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(28, 24, 16, 28),
                  child: RichContent(
                    detail: contentDetail,
                    apiBaseUrl: apiBaseUrl,
                    apiToken: apiToken,
                    headerKeys: headerKeys,
                    useHero: false,
                  ),
                ),
              ),
              Expanded(
                flex: 7,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 24, 28, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _DiscoveryMetaWrap(
                          item: widget.item, scoreColor: _scoreColorForItem),
                      const Gap(16),
                      ContentSideInfoCard(detail: contentDetail),
                      if (headers.isNotEmpty) ...[
                        const Gap(16),
                        _DiscoveryTocCard(
                            headers: headers, headerKeys: headerKeys),
                      ],
                      if (widget.item.aiReason != null &&
                          widget.item.aiReason!.isNotEmpty) ...[
                        const Gap(16),
                        _SectionCard(
                          title: 'AI 分析',
                          icon: Icons.auto_awesome_rounded,
                          child: Text(
                            widget.item.aiReason!,
                            style:
                                Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                              height: 1.6,
                            ),
                          ),
                        ),
                      ],
                      if (widget.item.aiTags != null &&
                          widget.item.aiTags!.isNotEmpty) ...[
                        const Gap(16),
                        _SectionCard(
                          title: '标签',
                          icon: Icons.sell_rounded,
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: widget.item.aiTags!
                                .map(
                                  (tag) => Chip(
                                    label: Text(tag),
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showFullScreen(
    BuildContext context,
    List<String> images,
    int initialIndex,
    String apiBaseUrl,
    String? apiToken,
    int contentId,
  ) async {
    await Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder(
        opaque: false,
        pageBuilder: (context, animation, secondaryAnimation) =>
            FullScreenGallery(
          images: images,
          initialIndex: initialIndex,
          apiBaseUrl: apiBaseUrl,
          apiToken: apiToken,
          contentId: contentId,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }
}

Color _scoreColorForItem(double score) {
  if (score >= 8) return Colors.green;
  if (score >= 6) return Colors.amber.shade700;
  return Colors.grey;
}

class _DiscoveryMetaWrap extends StatelessWidget {
  final DiscoveryItem item;
  final Color Function(double score) scoreColor;

  const _DiscoveryMetaWrap({required this.item, required this.scoreColor});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final score = item.aiScore;

    return Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (score != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: scoreColor(score).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.star_rounded, size: 16, color: scoreColor(score)),
                const Gap(4),
                Text(
                  score.toStringAsFixed(1),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scoreColor(score),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        if (item.sourceType != null)
          Chip(
            avatar: Icon(_sourceIcon(item.sourceType!), size: 16),
            label: Text(item.sourceType!),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
        Text(
          timeago.format(item.discoveredAt ?? item.createdAt, locale: 'zh_CN'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: colorScheme.primary),
              const Gap(8),
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const Gap(12),
          child,
        ],
      ),
    );
  }
}

class _DiscoveryTocCard extends StatelessWidget {
  final List<HeaderLine> headers;
  final Map<String, GlobalKey> headerKeys;

  const _DiscoveryTocCard({required this.headers, required this.headerKeys});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.toc_rounded, size: 18, color: colorScheme.primary),
              const Gap(8),
              Text(
                '目录',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const Gap(12),
          ...headers.map((header) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: InkWell(
                onTap: () {
                  final key = headerKeys[header.uniqueId];
                  final targetContext = key?.currentContext;
                  if (targetContext != null) {
                    Scrollable.ensureVisible(
                      targetContext,
                      duration: const Duration(milliseconds: 500),
                      curve: Curves.easeOutCubic,
                    );
                  }
                },
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    (header.level - 1) * 12.0 + 8,
                    10,
                    10,
                    10,
                  ),
                  child: Text(
                    header.text,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: header.level == 1
                          ? colorScheme.onSurface
                          : colorScheme.onSurfaceVariant,
                      fontWeight: header.level == 1
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

IconData _sourceIcon(String sourceType) {
  switch (sourceType.toLowerCase()) {
    case 'rss':
      return Icons.rss_feed_rounded;
    case 'hackernews' || 'hn':
      return Icons.whatshot_rounded;
    case 'reddit':
      return Icons.forum_rounded;
    case 'telegram_channel' || 'telegram':
      return Icons.telegram_rounded;
    default:
      return Icons.link_rounded;
  }
}
