import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';
import '../models/content.dart';
import '../providers/collection_provider.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/image_headers.dart';

class ContentDetailSheet extends ConsumerWidget {
  final int contentId;

  const ContentDetailSheet({super.key, required this.contentId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(contentDetailProvider(contentId));

    // 获取 API Base URL 用于映射媒体链接
    final dio = ref.watch(apiClientProvider);
    final baseUrl = dio.options.baseUrl.replaceFirst('/api/v1', '');
    final apiToken = dio.options.headers['X-API-Token']?.toString();

    return detailAsync.when(
      data: (detail) => _buildDetail(context, detail, baseUrl, apiToken),
      loading: () => const SizedBox(
        height: 360,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (err, stack) => SizedBox(
        height: 240,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text('加载失败: $err'),
              TextButton(
                onPressed: () =>
                    ref.invalidate(contentDetailProvider(contentId)),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetail(
    BuildContext context,
    ContentDetail detail,
    String baseUrl,
    String? apiToken,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.8,
      minChildSize: 0.6,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(top: 10, bottom: 4),
                  decoration: BoxDecoration(
                    color: colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header with Platform Icon and Title
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _getPlatformIcon(detail.platform, 24),
                          const SizedBox(width: 12),
                          if (detail.platform.toLowerCase() != 'twitter' &&
                              detail.platform.toLowerCase() != 'x')
                            Expanded(
                              child: Text(
                                detail.title ?? '无标题内容',
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            )
                          else
                            // For Twitter, display "推文" instead of the content snippet title
                            Text(
                              '推文',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Author and Stats
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 12,
                            backgroundColor: colorScheme.primaryContainer,
                            child: Text(
                              (detail.authorName ?? '?')
                                  .substring(0, 1)
                                  .toUpperCase(),
                              style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            detail.authorName ?? '未知作者',
                            style: theme.textTheme.titleSmall,
                          ),
                          const SizedBox(width: 12),
                          if (detail.publishedAt != null)
                            Text(
                              DateFormat(
                                'yyyy-MM-dd HH:mm',
                              ).format(detail.publishedAt!),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.outline,
                              ),
                            ),

                          const Spacer(),
                          // Basic Stats
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.visibility_outlined,
                                size: 16,
                                color: colorScheme.outline,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${detail.viewCount}',
                                style: theme.textTheme.bodySmall,
                              ),
                              const SizedBox(width: 12),
                              Icon(
                                Icons.favorite_border,
                                size: 16,
                                color: colorScheme.outline,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${detail.likeCount}',
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Tags
                      if (detail.tags.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: detail.tags
                                .map(
                                  (tag) => Chip(
                                    label: Text(tag),
                                    labelStyle: theme.textTheme.labelSmall,
                                    visualDensity: VisualDensity.compact,
                                    backgroundColor:
                                        colorScheme.surfaceContainerHigh,
                                    side: BorderSide.none,
                                  ),
                                )
                                .toList(),
                          ),
                        ),

                      const Divider(),
                      const SizedBox(height: 16),

                      // RICH CONTENT
                      _buildRichContent(context, detail, baseUrl, apiToken),

                      const SizedBox(height: 24),

                      // Bottom Actions
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () => launchUrl(Uri.parse(detail.url)),
                              icon: const Icon(Icons.open_in_new),
                              label: const Text('原始链接'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          IconButton.filledTonal(
                            onPressed: () {
                              // TODO: Share
                            },
                            icon: const Icon(Icons.share),
                          ),
                        ],
                      ),
                      const SizedBox(height: 40),
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

  Widget _buildRichContent(
    BuildContext context,
    ContentDetail detail,
    String baseUrl,
    String? apiToken,
  ) {
    final theme = Theme.of(context);
    final images = _extractAllImages(detail, baseUrl);

    // Bilibili Article/Opus: Render Markdown which contains images
    if (detail.platform.toLowerCase() == 'bilibili' &&
        (detail.description?.contains('![') ?? false)) {
      // A simple heuristic: if it contains markdown image syntax, treat as markdown
      // Or usually Bilibili description from our backend is mostly Markdown
      return Markdown(
        data: detail.description ?? '',
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        imageBuilder: (uri, title, alt) {
          String url = uri.toString();
          // Fix Proxy for markdown inline images
          if (url.contains('hdslb.com') && !url.contains('proxy')) {
            url = '$baseUrl/api/v1/proxy/image?url=${Uri.encodeComponent(url)}';
          }
          return ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CachedNetworkImage(
              imageUrl: url,
              httpHeaders: buildImageHeaders(
                imageUrl: url,
                baseUrl: baseUrl,
                apiToken: apiToken,
              ),
              placeholder: (c, u) => Container(
                height: 200,
                color: theme.colorScheme.surfaceContainerHighest,
              ),
            ),
          );
        },
      );
    }

    // Default (Twitter etc): Text + Grid
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (detail.description != null && detail.description!.isNotEmpty) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              detail.description!,
              style: theme.textTheme.bodyMedium?.copyWith(
                height: 1.5,
                fontSize: 16,
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],

        if (images.isNotEmpty) ...[
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: images.length == 1
                  ? 1
                  : 2, // Single image = large
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: images.length == 1 ? 16 / 9 : 1.0,
            ),
            itemCount: images.length,
            itemBuilder: (context, index) {
              final headers = buildImageHeaders(
                imageUrl: images[index],
                baseUrl: baseUrl,
                apiToken: apiToken,
              );
              return ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CachedNetworkImage(
                  imageUrl: images[index],
                  httpHeaders: headers,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(
                    color: theme.colorScheme.surfaceContainerHighest,
                  ),
                  errorWidget: (context, url, error) =>
                      const Icon(Icons.broken_image),
                ),
              );
            },
          ),
        ],

        // Bilibili specific Extra Stats
        if (detail.platform.toLowerCase() == 'bilibili')
          _buildBilibiliStats(context, detail),
      ],
    );
  }

  Widget _buildBilibiliStats(BuildContext context, ContentDetail detail) {
    final stats = detail.extraStats;
    if (stats.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Wrap(
        spacing: 20,
        runSpacing: 12,
        children: [
          if (stats['coin'] != null)
            _LabelStat(label: '投币', value: stats['coin']),
          if (stats['danmaku'] != null)
            _LabelStat(label: '弹幕', value: stats['danmaku']),
          if (stats['favorite'] != null)
            _LabelStat(label: '收藏', value: stats['favorite']),
          if (stats['reply'] != null)
            _LabelStat(label: '评论', value: stats['reply']),
        ],
      ),
    );
  }

  List<String> _extractAllImages(ContentDetail detail, String baseUrl) {
    final list = <String>{};

    // 0. 预处理：构建 stored_images 映射表 (orig_url -> local_url)
    Map<String, String> storedMap = {};
    try {
      if (detail.rawMetadata != null) {
        final archive = detail.rawMetadata!['archive'];
        if (archive != null) {
          final storedImages = archive['stored_images'];
          if (storedImages is List) {
            for (var img in storedImages) {
              if (img is Map && img['orig_url'] != null && img['url'] != null) {
                String localPath = img['url'];
                if (!localPath.startsWith('/')) localPath = '/$localPath';
                storedMap[img['orig_url']] = localPath;
              }
            }
          }
        }
      }
    } catch (_) {}

    // 1. 优先使用已经清洗/本地化的 mediaUrls
    if (detail.mediaUrls.isNotEmpty) {
      if (detail.mediaUrls.length == 1 &&
          list.isEmpty &&
          (detail.mediaUrls.first.contains('twimg.com') ||
              detail.mediaUrls.first.contains('hdslb.com'))) {
        // 单图且为外部链接，尝试强行使用第一张本地图片兜底 (Fix for mismatching params)
        if (storedMap.isNotEmpty) {
          list.add(_mapUrl(storedMap.values.first, baseUrl));
        }
      }

      for (var url in detail.mediaUrls) {
        if (url.isEmpty) continue;
        if (list.isNotEmpty) {
          break /* 只做兜底，如果已经加了就不重复加了? 不，这里逻辑有点乱，保持原样但增加单图修正 */;
        }
      }

      // Re-implementing loop correctly
      for (var url in detail.mediaUrls) {
        if (url.isEmpty) continue;

        // 尝试匹配本地存储 (Level 1: Local First)
        if (storedMap.containsKey(url)) {
          list.add(_mapUrl(storedMap[url]!, baseUrl));
        } else {
          // 再次尝试去参匹配 (Ignore query params like ?name=orig)
          final cleanUrl = url.split('?').first;
          final match = storedMap.entries.firstWhere(
            (e) => e.key.split('?').first == cleanUrl,
            orElse: () => const MapEntry('', ''),
          );

          if (match.key.isNotEmpty) {
            list.add(_mapUrl(match.value, baseUrl));
          } else {
            // 确实找不到，只能用原始链接（会走代理）
            list.add(_mapUrl(url, baseUrl));
          }
        }
      }
    }

    // 2. 如果 mediaUrls 为空，再尝试从 rawMetadata 兜底（主要针对未处理或旧数据）
    if (list.isEmpty) {
      if (detail.coverUrl != null && detail.coverUrl!.isNotEmpty) {
        final url = detail.coverUrl!;
        if (storedMap.containsKey(url)) {
          list.add(_mapUrl(storedMap[url]!, baseUrl));
        } else {
          list.add(_mapUrl(url, baseUrl));
        }
      }

      try {
        final meta = detail.rawMetadata;
        if (meta != null) {
          final archive = meta['archive'];
          if (archive != null) {
            // 优先找本地化后的 stored_images
            final stored = archive['stored_images'];
            if (stored is List && stored.isNotEmpty) {
              for (var img in stored) {
                if (img is Map && img['url'] != null) {
                  list.add(_mapUrl(img['url'] as String, baseUrl));
                }
              }
            } else {
              // 找不到则找原始 images
              final images = archive['images'];
              if (images is List) {
                for (var img in images) {
                  if (img is String) {
                    list.add(_mapUrl(img, baseUrl));
                  } else if (img is Map && img['url'] != null) {
                    list.add(_mapUrl(img['url'] as String, baseUrl));
                  }
                }
              }
            }
          }
        }
      } catch (_) {}
    }

    return list.toList();
  }

  String _mapUrl(String url, String baseUrl) {
    if (url.isEmpty) return url;

    // 1. 处理需要代理的外部域名 (优先检查)
    if (url.contains('pbs.twimg.com') || url.contains('hdslb.com')) {
      return '$baseUrl/api/v1/proxy/image?url=${Uri.encodeComponent(url)}';
    }

    // 2. 处理本地存储的相对路径或带 localhost 的路径
    if (url.startsWith('/media') || url.contains('/media/')) {
      final path = url.contains('http')
          ? url.substring(url.indexOf('/media/'))
          : url;
      // 动态使用当前 API 的 base URL
      return '$baseUrl$path';
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

class _LabelStat extends StatelessWidget {
  final String label;
  final dynamic value;
  const _LabelStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.labelSmall),
        Text(
          value.toString(),
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
