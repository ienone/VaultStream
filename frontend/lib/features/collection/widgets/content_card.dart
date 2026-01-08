import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import '../models/content.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/image_headers.dart';

class ContentCard extends ConsumerWidget {
  final ShareCard content;
  final VoidCallback? onTap;

  const ContentCard({super.key, required this.content, this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // 获取 API Base URL
    final dio = ref.watch(apiClientProvider);
    final baseUrl = dio.options.baseUrl.replaceFirst('/api/v1', '');
    final apiToken = dio.options.headers['X-API-Token']?.toString();

    final imageUrl = _getDisplayImageUrl(baseUrl);
    final imageHeaders = buildImageHeaders(
      imageUrl: imageUrl,
      baseUrl: baseUrl,
      apiToken: apiToken,
    );
    final isTwitter =
        content.platform.toLowerCase() == 'twitter' ||
        content.platform.toLowerCase() == 'x';
    final hasImage = imageUrl.isNotEmpty;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image Section
            if (hasImage)
              Stack(
                children: [
                  CachedNetworkImage(
                    imageUrl: imageUrl,
                    httpHeaders: imageHeaders,
                    fit: BoxFit.cover,
                    // 移除 AspectRatio，让图片自适应，但设置最大高度防止过长
                    maxHeightDiskCache: 1000,
                    placeholder: (context, url) => Container(
                      height: 200, // 占位高度
                      color: colorScheme.surfaceContainerHighest,
                      child: const Center(child: CircularProgressIndicator()),
                    ),
                    errorWidget: (context, url, error) => Container(
                      height: 150,
                      color: colorScheme.errorContainer,
                      child: Center(
                        child: Icon(
                          Icons.broken_image,
                          color: colorScheme.error,
                        ),
                      ),
                    ),
                  ),

                  // Multi-image badge
                  if (content.mediaUrls.length > 1)
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.filter,
                              size: 10,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${content.mediaUrls.length}',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),

            // Text/Meta Section
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Platform & Author Row
                  Row(
                    children: [
                      _PlatformBadge(platform: content.platform),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          content.authorName ?? '未知作者',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (content.publishedAt != null) ...[
                        const SizedBox(width: 4),
                        Text(
                          DateFormat(
                            'MM-dd',
                          ).format(content.publishedAt!.toLocal()),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.surfaceTint,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Title / Content Text
                  if (isTwitter) ...[
                    // Twitter: Show description (text content) instead of Title
                    if (content.description != null &&
                        content.description!.isNotEmpty)
                      Text(
                        content.description!,
                        style: theme.textTheme.bodyMedium,
                        maxLines: hasImage ? 3 : 8, // 无图时多显示一些文字
                        overflow: TextOverflow.ellipsis,
                      ),
                  ] else ...[
                    // Bilibili/Other: Title
                    if (content.title != null)
                      Text(
                        content.title!,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],

                  // Tags
                  if (content.tags.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: content.tags.take(3).map((tag) {
                        return Chip(
                          label: Text(tag),
                          labelStyle: theme.textTheme.labelSmall?.copyWith(
                            fontSize: 10,
                          ),
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                          backgroundColor: colorScheme.surfaceContainerHigh,
                          side: BorderSide.none,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn().slideY(begin: 0.1);
  }

  String _getDisplayImageUrl(String baseUrl) {
    String url = '';
    // 封面优先，B站Opus等特殊场景回退到首张媒体图
    if (content.coverUrl != null && content.coverUrl!.isNotEmpty) {
      url = content.coverUrl!;
    } else if (content.mediaUrls.isNotEmpty) {
      url = content.mediaUrls.first;
    }

    if (url.isEmpty) return '';

    // =========================================================
    // Level 1: 本地优先 (Local First)
    // 尝试在 metadata 中查找该 URL 对应的本地 stored_url
    // =========================================================
    try {
      if (content.rawMetadata != null) {
        final archive = content.rawMetadata!['archive'];
        if (archive != null) {
          final storedImages = archive['stored_images'];
          if (storedImages is List && storedImages.isNotEmpty) {
            // 1. 尝试精确匹配 orig_url
            final localMatch = storedImages.firstWhere(
              (img) => img['orig_url'] == url,
              orElse: () => null,
            );

            if (localMatch != null && localMatch['url'] != null) {
              String localPath = localMatch['url'];
              if (!localPath.startsWith('/')) localPath = '/$localPath';
              return '$baseUrl$localPath';
            }

            // 2. 模糊匹配/降级策略
            // 如果精确匹配失败，但这是一个需要代理的外部链接(Twitter/Bilibili)，
            // 且我们有本地归档图片，则直接使用第一张本地图片作为替代。
            // 这能有效避免代理失效或缓存了损坏数据的问题。
            if (url.contains('twimg.com') || url.contains('hdslb.com')) {
              final fallback = storedImages.first;
              if (fallback != null && fallback['url'] != null) {
                String localPath = fallback['url'];
                if (!localPath.startsWith('/')) localPath = '/$localPath';
                return '$baseUrl$localPath';
              }
            }
          }
        }
      }
    } catch (_) {
      // 查找过程出错则忽略，继续尝试代理
    }

    // =========================================================
    // Level 2: 代理兜底 (Proxy Fallback)
    // =========================================================
    if (url.contains('pbs.twimg.com') || url.contains('hdslb.com')) {
      return '$baseUrl/api/v1/proxy/image?url=${Uri.encodeComponent(url)}';
    }

    // =========================================================
    // Level 3: 原始路径识别 (Legacy Local Check)
    // =========================================================
    if (url.startsWith('/media') || url.contains('/media/')) {
      final path = url.contains('http')
          ? url.substring(url.indexOf('/media/'))
          : url;
      // 避免重复斜杠
      final cleanBase = baseUrl.endsWith('/')
          ? baseUrl.substring(0, baseUrl.length - 1)
          : baseUrl;
      final cleanPath = path.startsWith('/') ? path : '/$path';
      return '$cleanBase$cleanPath';
    }

    return url;
  }
}

class _PlatformBadge extends StatelessWidget {
  final String platform;

  const _PlatformBadge({required this.platform});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    Color color;
    IconData icon;
    String label = platform.toUpperCase();

    switch (platform.toLowerCase()) {
      case 'twitter':
      case 'x':
        color = isDark ? Colors.white : Colors.black;
        icon = FontAwesomeIcons.xTwitter;
        label = 'X';
        break;
      case 'bilibili':
        color = const Color(0xFFFB7299);
        icon = FontAwesomeIcons.bilibili;
        break;
      case 'ku_an':
        color = const Color(0xFF1E88E5);
        icon = Icons.android;
        break;
      default:
        color = theme.colorScheme.secondary;
        icon = Icons.link;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FaIcon(icon, size: 10, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}
