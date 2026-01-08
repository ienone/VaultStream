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
    final apiBaseUrl = dio.options.baseUrl;
    final apiToken = dio.options.headers['X-API-Token']?.toString();

    final imageUrl = _getDisplayImageUrl(apiBaseUrl);
    final imageHeaders = buildImageHeaders(
      imageUrl: imageUrl,
      baseUrl: apiBaseUrl,
      apiToken: apiToken,
    );
    final isTwitter =
        content.platform.toLowerCase() == 'twitter' ||
        content.platform.toLowerCase() == 'x';
    final hasImage = imageUrl.isNotEmpty;

    // 根据封面图宽高比确定卡片布局比例
    // 默认认为宽 > 高 (16:9)
    bool isLandscapeCover = true;
    try {
      if (content.rawMetadata != null &&
          content.rawMetadata!['archive'] != null) {
        final storedImages = content.rawMetadata!['archive']['stored_images'];
        if (storedImages is List && storedImages.isNotEmpty) {
          // 查找当前显示的图片的元数据
          final currentImg = storedImages.firstWhere(
            (img) => _compareUrls(img['orig_url'], content.coverUrl),
            orElse: () => storedImages.first,
          );
          if (currentImg != null &&
              currentImg['width'] != null &&
              currentImg['height'] != null) {
            isLandscapeCover = currentImg['width'] > currentImg['height'];
          }
        }
      }
    } catch (_) {}

    final double aspectRatio = isLandscapeCover ? 16 / 18 : 36 / 78;

    return AspectRatio(
      aspectRatio: aspectRatio,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Image Section
              if (hasImage)
                Expanded(
                  flex: isLandscapeCover ? 11 : 68,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Hero(
                        tag: 'content-image-${content.id}',
                        child: CachedNetworkImage(
                          imageUrl: imageUrl,
                          httpHeaders: imageHeaders,
                          fit: BoxFit.cover,
                          maxHeightDiskCache: 1000,
                          placeholder: (context, url) => Container(
                            color: colorScheme.surfaceContainerHighest,
                            child: const Center(
                              child: CircularProgressIndicator(),
                            ),
                          ),
                          errorWidget: (context, url, error) => Container(
                            color: colorScheme.errorContainer,
                            child: Center(
                              child: Icon(
                                Icons.broken_image,
                                color: colorScheme.error,
                              ),
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
                              color: Colors.black.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.filter,
                                  size: 11,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${content.mediaUrls.length}',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                )
              else if (isLandscapeCover)
                const Spacer(flex: 7),

              // Text/Meta Section
              Expanded(
                flex: isLandscapeCover ? 7 : 10,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Platform & Author Row
                      Row(
                        children: [
                          _PlatformBadge(platform: content.platform),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              content.authorName ?? '未知作者',
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onSurfaceVariant,
                                fontSize: 12,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (content.publishedAt != null) ...[
                            Text(
                              DateFormat(
                                'MM-dd',
                              ).format(content.publishedAt!.toLocal()),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.surfaceTint,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      // Title / Content Text
                      Expanded(
                        child: isTwitter
                            ? (content.description != null &&
                                      content.description!.isNotEmpty
                                  ? Text(
                                      content.description!,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            height: 1.3,
                                            fontSize: 13,
                                            color: colorScheme.onSurface,
                                          ),
                                      maxLines: isLandscapeCover ? 3 : 4,
                                      overflow: TextOverflow.ellipsis,
                                    )
                                  : const SizedBox.shrink())
                            : (content.title != null
                                  ? Text(
                                      content.title!,
                                      style: theme.textTheme.titleSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                            height: 1.25,
                                            color: colorScheme.onSurface,
                                          ),
                                      maxLines: isLandscapeCover ? 3 : 2,
                                      overflow: TextOverflow.ellipsis,
                                    )
                                  : const SizedBox.shrink()),
                      ),
                      const SizedBox(height: 4),
                      // Tags & Stats Row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          if (content.tags.isNotEmpty)
                            Expanded(
                              child: Text(
                                content.tags
                                    .take(isLandscapeCover ? 2 : 1)
                                    .map((t) => '#$t')
                                    .join(' '),
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: colorScheme.primary.withValues(
                                    alpha: 0.8,
                                  ),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            )
                          else
                            const Spacer(),
                          const SizedBox(width: 4),
                          // Mini Stats
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (content.viewCount > 0) ...[
                                Icon(
                                  Icons.remove_red_eye_outlined,
                                  size: 12,
                                  color: colorScheme.outline,
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  _formatCount(content.viewCount),
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    fontSize: 11,
                                    color: colorScheme.outline,
                                  ),
                                ),
                                const SizedBox(width: 6),
                              ],
                              if (content.likeCount > 0) ...[
                                Icon(
                                  Icons.favorite_border,
                                  size: 12,
                                  color: colorScheme.outline,
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  _formatCount(content.likeCount),
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    fontSize: 11,
                                    color: colorScheme.outline,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ).animate().fadeIn().slideY(begin: 0.1);
  }

  String _formatCount(int count) {
    if (count >= 10000) {
      return '${(count / 10000).toStringAsFixed(1)}w';
    } else if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}k';
    }
    return count.toString();
  }

  bool _compareUrls(dynamic url1, String? url2) {
    if (url1 == null || url2 == null) return false;
    final s1 = url1.toString().split('?').first;
    final s2 = url2.split('?').first;
    return s1 == s2;
  }

  String _getDisplayImageUrl(String apiBaseUrl) {
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
              (img) => _compareUrls(img['orig_url'], url),
              orElse: () => null,
            );

            if (localMatch != null) {
              String? localPath = localMatch['url'];
              final String? key = localMatch['key'];

              // 统一使用 key 逻辑，避免路径不匹配
              if (key != null) {
                if (key.startsWith('sha256:')) {
                  final hashVal = key.split(':')[1];
                  localPath =
                      'vaultstream/blobs/sha256/${hashVal.substring(0, 2)}/${hashVal.substring(2, 4)}/$hashVal.webp';
                } else {
                  localPath = key;
                }
              }

              if (localPath != null) {
                return _mapUrl(localPath, apiBaseUrl);
              }
            }

            // 2. 模糊匹配/降级策略 (代理外部链接反盗链)
            if (url.contains('twimg.com') || url.contains('hdslb.com')) {
              final fallback = storedImages.first;
              if (fallback != null) {
                String? localPath = fallback['url'];
                final String? key = fallback['key'];
                if (key != null) {
                  if (key.startsWith('sha256:')) {
                    final hashVal = key.split(':')[1];
                    localPath =
                        'vaultstream/blobs/sha256/${hashVal.substring(0, 2)}/${hashVal.substring(2, 4)}/$hashVal.webp';
                  } else {
                    localPath = key;
                  }
                }
                if (localPath != null) {
                  return _mapUrl(localPath, apiBaseUrl);
                }
              }
            }
          }
        }
      }
    } catch (_) {}

    // =========================================================
    // Level 2: 兜底逻辑 (使用通用 _mapUrl)
    // =========================================================
    return _mapUrl(url, apiBaseUrl);
  }

  String _mapUrl(String url, String apiBaseUrl) {
    if (url.isEmpty) return url;
    if (url.startsWith('//')) url = 'https:$url';

    // 1. 处理需要代理的外部域名
    if (url.contains('pbs.twimg.com') ||
        url.contains('hdslb.com') ||
        url.contains('bilibili.com')) {
      if (url.contains('/proxy/image?url=')) return url;
      return '$apiBaseUrl/proxy/image?url=${Uri.encodeComponent(url)}';
    }

    // 2. 防止重复添加 /media/
    if (url.contains('/api/v1/media/')) return url;

    // 3. 处理本地存储路径
    if (url.contains('blobs/sha256/')) {
      if (url.startsWith('/media/') || url.contains('/media/')) {
        final path = url.contains('http')
            ? url.substring(url.indexOf('/media/'))
            : url;
        final cleanPath = path.startsWith('/') ? path : '/$path';
        return '$apiBaseUrl$cleanPath';
      }
      if (url.contains('/api/v1/')) {
        return url.replaceFirst('/api/v1/', '/api/v1/media/');
      }
      final cleanKey = url.startsWith('/') ? url.substring(1) : url;
      return '$apiBaseUrl/media/$cleanKey';
    }

    if (url.startsWith('/media') || url.contains('/media/')) {
      final path = url.contains('http')
          ? url.substring(url.indexOf('/media/'))
          : url;
      final cleanPath = path.startsWith('/') ? path : '/$path';
      return '$apiBaseUrl$cleanPath';
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
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FaIcon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}
