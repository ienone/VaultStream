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
import '../collection/widgets/detail/components/rich_content.dart';
import '../collection/widgets/renderers/payload_block_renderer.dart';
import '../collection/widgets/detail/components/unified_stats.dart';
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
              Icon(Icons.error_outline, size: 48,
                  color: Theme.of(context).colorScheme.error),
              const Gap(16),
              Text('加载失败: $err'),
              const Gap(16),
              ElevatedButton(
                onPressed: () => ref.invalidate(discoveryItemDetailProvider(itemId)),
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
              Icon(Icons.error_outline, size: 48,
                  color: Theme.of(context).colorScheme.error),
              const Gap(16),
              Text('加载失败: $err'),
              const Gap(16),
              ElevatedButton(
                onPressed: () => ref.invalidate(discoveryItemDetailProvider(itemId)),
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      children: [
        // Action buttons at top for embedded mode
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _promote(context, ref),
                  icon: const Icon(Icons.bookmark_add_rounded),
                  label: const Text('收藏'),
                  style: FilledButton.styleFrom(
                    backgroundColor: colorScheme.primary,
                  ),
                ),
              ),
              const Gap(12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _ignore(context, ref),
                  icon: const Icon(Icons.visibility_off_rounded),
                  label: const Text('忽略'),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // Scrollable content
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: _DetailBody(item: item),
          ),
        ),
      ],
    ).animate().fadeIn(duration: 200.ms);
  }

  Future<void> _promote(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(discoveryActionsProvider.notifier).promoteItem(item.id);
      if (context.mounted) {
        Toast.show(context, '已收藏', icon: Icons.check_circle_outline_rounded);
      }
    } catch (e) {
      if (context.mounted) {
        Toast.show(context, '操作失败: $e', isError: true);
      }
    }
  }

  Future<void> _ignore(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(discoveryActionsProvider.notifier).ignoreItem(item.id);
      if (context.mounted) {
        Toast.show(context, '已忽略', icon: Icons.check_circle_outline_rounded);
      }
    } catch (e) {
      if (context.mounted) {
        Toast.show(context, '操作失败: $e', isError: true);
      }
    }
  }
}

// --- Full scaffold detail (mobile) ---
class _FullDetailScaffold extends ConsumerWidget {
  final DiscoveryItem item;
  const _FullDetailScaffold({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: FrostedAppBar(
        blurSigma: 12,
        title: Text(
          item.title ?? '详情',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + kToolbarHeight + 16,
          left: 16,
          right: 16,
          bottom: 100,
        ),
        child: _DetailBody(item: item),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () async {
                    try {
                      await ref
                          .read(discoveryActionsProvider.notifier)
                          .promoteItem(item.id);
                      if (context.mounted) {
                        Toast.show(context, '已收藏',
                            icon: Icons.check_circle_outline_rounded);
                        Navigator.of(context).pop();
                      }
                    } catch (e) {
                      if (context.mounted) {
                        Toast.show(context, '操作失败: $e', isError: true);
                      }
                    }
                  },
                  icon: const Icon(Icons.bookmark_add_rounded),
                  label: const Text('收藏'),
                  style: FilledButton.styleFrom(
                    backgroundColor: colorScheme.primary,
                  ),
                ),
              ),
              const Gap(12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    try {
                      await ref
                          .read(discoveryActionsProvider.notifier)
                          .ignoreItem(item.id);
                      if (context.mounted) {
                        Toast.show(context, '已忽略',
                            icon: Icons.check_circle_outline_rounded);
                        Navigator.of(context).pop();
                      }
                    } catch (e) {
                      if (context.mounted) {
                        Toast.show(context, '操作失败: $e', isError: true);
                      }
                    }
                  },
                  icon: const Icon(Icons.visibility_off_rounded),
                  label: const Text('忽略'),
                ),
              ),
            ],
          ),
        ),
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
    final score = item.aiScore;
    final hasAuthorAvatar =
      item.authorAvatarUrl != null && item.authorAvatarUrl!.trim().isNotEmpty;
    final authorInitial = (item.authorName?.trim().isNotEmpty ?? false)
      ? item.authorName!.trim().substring(0, 1).toUpperCase()
      : '?';

    // 获取 API Base URL for Media Proxy
    final dio = ref.read(apiClientProvider);
    final apiBaseUrl = dio.options.baseUrl;
    final apiToken = dio.options.headers['X-API-Token']?.toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Author Info (If available)
        if (item.authorName != null) ...[
          Row(
            children: [
              if (hasAuthorAvatar)
                CircleAvatar(
                  radius: 16,
                  backgroundImage: NetworkImage(item.authorAvatarUrl!.trim()),
                  backgroundColor: colorScheme.surfaceContainerHighest,
                )
              else
                CircleAvatar(
                  radius: 16,
                  backgroundColor: colorScheme.primaryContainer,
                  child: Text(
                    authorInitial,
                    style: TextStyle(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              const Gap(8),
              Expanded(
                child: Text(
                  item.authorName!,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const Gap(16),
        ],

        // Title
        Text(
          item.title ?? item.url,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const Gap(12),
        // Score + source + time row
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (score != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _scoreColor(score).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.star_rounded, size: 16,
                        color: _scoreColor(score)),
                    const Gap(4),
                    Text(
                      score.toStringAsFixed(1),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: _scoreColor(score),
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
              timeago.format(
                item.discoveredAt ?? item.createdAt,
                locale: 'zh_CN',
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const Gap(20),

        // Quoted Content & Sub Items
        if (item.richPayload != null) ...[
          PayloadBlockRenderer(content: item.toContentDetail()),
          const Gap(16),
        ],

        // Rich Content (Markdown + Media)
        RichContent(
          detail: item.toContentDetail(),
          apiBaseUrl: apiBaseUrl,
          apiToken: apiToken,
          headerKeys: const {},
          useHero: false,
        ),
        const Gap(20),

        // Unified Stats (Views, Reactions, etc.)
        UnifiedStats(
          detail: item.toContentDetail(),
          useContainer: false,
        ),
        const Gap(16),

        // AI Reason
        if (item.aiReason != null && item.aiReason!.isNotEmpty) ...[
          Text(
            'AI 分析',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const Gap(8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              item.aiReason!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const Gap(16),
        ],
        // AI Tags
        if (item.aiTags != null && item.aiTags!.isNotEmpty) ...[
          Text(
            '标签',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const Gap(8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: item.aiTags!
                .map((tag) => Chip(
                      label: Text(tag),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ))
                .toList(),
          ),
          const Gap(16),
        ],
        // Multi-source traceability
        if (item.contextData?['source_links'] != null) ...[
          _SourceLinksSection(sourceLinks: item.contextData!['source_links'] as List),
          const Gap(16),
        ],
        // View original button
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => SafeUrlLauncher.openExternal(context, item.url),
            icon: const Icon(Icons.open_in_new_rounded),
            label: const Text('查看原文'),
          ),
        ),
      ],
    );
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
}

class _SourceLinksSection extends StatelessWidget {
  final List sourceLinks;
  const _SourceLinksSection({required this.sourceLinks});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        title: Text('来源 (${sourceLinks.length})',
          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
        leading: const Icon(Icons.hub_rounded),
        tilePadding: EdgeInsets.zero,
        children: sourceLinks.map((link) => _buildSourceItem(context, link)).toList(),
      ),
    );
  }

  Widget _buildSourceItem(BuildContext context, dynamic link) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final String kind = link['source_kind'] ?? 'unknown';
    final String name = link['source_name'] ?? 'Unknown';
    final String title = link['title'] ?? 'No title';
    final String url = link['url'] ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: () => SafeUrlLauncher.openExternal(context, url),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_sourceIcon(kind), size: 16, color: colorScheme.primary),
                const Gap(8),
                Text(name, style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold)),
                const Spacer(),
                const Icon(Icons.open_in_new_rounded, size: 14),
              ],
            ),
            const Gap(4),
            Text(title, style: theme.textTheme.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

  IconData _sourceIcon(String sourceType) {
    switch (sourceType.toLowerCase()) {
      case 'rss': return Icons.rss_feed_rounded;
      case 'hackernews' || 'hn': return Icons.whatshot_rounded;
      case 'reddit': return Icons.forum_rounded;
      case 'telegram_channel' || 'telegram': return Icons.telegram_rounded;
      default: return Icons.link_rounded;
    }
  }
}
