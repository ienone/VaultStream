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
    final apiBaseUrl = dio.options.baseUrl;
    final apiToken = dio.options.headers['X-API-Token']?.toString();

    return detailAsync.when(
      data: (detail) => _buildDetail(context, detail, apiBaseUrl, apiToken),
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
    String apiBaseUrl,
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
                          Builder(
                            builder: (context) {
                              String? avatarUrl;
                              if (detail.contentType == 'user_profile') {
                                avatarUrl = detail.coverUrl;
                              } else {
                                avatarUrl =
                                    detail.rawMetadata?['user']?['avatar_hd'] ??
                                    detail
                                        .rawMetadata?['user']?['profile_image_url'] ??
                                    detail.rawMetadata?['author']?['face'];
                              }
                              final mappedAvatarUrl = avatarUrl != null
                                  ? _mapUrl(avatarUrl, apiBaseUrl)
                                  : null;

                              return CircleAvatar(
                                radius: 12,
                                backgroundColor: colorScheme.primaryContainer,
                                backgroundImage: mappedAvatarUrl != null
                                    ? CachedNetworkImageProvider(
                                        mappedAvatarUrl,
                                        headers: buildImageHeaders(
                                          imageUrl: mappedAvatarUrl,
                                          baseUrl: apiBaseUrl,
                                          apiToken: apiToken,
                                        ),
                                      )
                                    : null,
                                child: mappedAvatarUrl == null
                                    ? Text(
                                        (detail.authorName ?? '?')
                                            .substring(0, 1)
                                            .toUpperCase(),
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: colorScheme.onPrimaryContainer,
                                        ),
                                      )
                                    : null,
                              );
                            },
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

                      // User Profile Stats (Following count fix)
                      if (detail.contentType == 'user_profile' &&
                          detail.platform.toLowerCase() == 'weibo')
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Wrap(
                            spacing: 20,
                            children: [
                              _LabelStat(
                                label: '粉丝',
                                value: detail.extraStats['followers'] ?? 0,
                              ),
                              _LabelStat(
                                label: '关注',
                                value:
                                    detail.extraStats['following'] ??
                                    detail.extraStats['friends'] ??
                                    0,
                              ),
                              _LabelStat(
                                label: '微博',
                                value: detail.extraStats['statuses'] ?? 0,
                              ),
                            ],
                          ),
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
                      _buildRichContent(context, detail, apiBaseUrl, apiToken),

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
    String apiBaseUrl,
    String? apiToken,
  ) {
    final theme = Theme.of(context);
    final storedMap = _getStoredMap(detail);
    final images = _extractAllMedia(detail, apiBaseUrl);

    // Try to get Markdown content
    String? markdown;
    if (detail.rawMetadata != null && detail.rawMetadata!['archive'] != null) {
      markdown = detail.rawMetadata!['archive']['markdown'];
    }

    // Fallback: Check if description itself is Markdown (heuristic: contains markdown image)
    if ((markdown == null || markdown.isEmpty) &&
        detail.platform.toLowerCase() == 'bilibili' &&
        (detail.description?.contains('![') ?? false)) {
      markdown = detail.description;
    }

    if (markdown != null && markdown.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Markdown(
            data: markdown,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            selectable: true,
            onTapLink: (text, href, title) {
              if (href != null) {
                launchUrl(
                  Uri.parse(href),
                  mode: LaunchMode.externalApplication,
                );
              }
            },
            styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
              // Material 3 Expressive Typography
              p: theme.textTheme.bodyLarge?.copyWith(
                height: 1.7,
                fontSize: 17,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.9),
              ),
              h1: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
              h2: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.secondary,
              ),
              h3: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              blockSpacing: 24,
              listBullet: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
              blockquote: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
                height: 1.6,
                fontStyle: FontStyle.italic,
              ),
              blockquotePadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 16,
              ),
              blockquoteDecoration: BoxDecoration(
                color: theme.colorScheme.secondaryContainer.withValues(
                  alpha: 0.35,
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border(
                  left: BorderSide(
                    color: theme.colorScheme.secondary,
                    width: 6,
                  ),
                ),
              ),
              code: theme.textTheme.bodyMedium?.copyWith(
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                fontFamily: 'monospace',
                color: theme.colorScheme.onSurfaceVariant,
              ),
              codeblockDecoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.5,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            // ignore: deprecated_member_use
            imageBuilder: (uri, title, alt) {
              String url = uri.toString();

              // 尝试在 storedMap 中寻找本地匹配
              if (storedMap.containsKey(url)) {
                url = _mapUrl(storedMap[url]!, apiBaseUrl);
              } else {
                // 尝试去参匹配
                final cleanUrl = url.split('?').first;
                final match = storedMap.entries.firstWhere(
                  (e) => e.key.split('?').first == cleanUrl,
                  orElse: () => const MapEntry('', ''),
                );
                if (match.key.isNotEmpty) {
                  url = _mapUrl(match.value, apiBaseUrl);
                } else {
                  // 兜底：处理原始链接（通常走代理）
                  url = _mapUrl(url, apiBaseUrl);
                }
              }

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: theme.colorScheme.shadow.withValues(
                              alpha: 0.08,
                            ),
                            blurRadius: 15,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: CachedNetworkImage(
                          imageUrl: url,
                          httpHeaders: buildImageHeaders(
                            imageUrl: url,
                            baseUrl: apiBaseUrl,
                            apiToken: apiToken,
                          ),
                          fit: BoxFit.fitWidth,
                          placeholder: (c, u) => Container(
                            height: 240,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest
                                  .withValues(alpha: 0.5),
                            ),
                            child: Center(
                              child: SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: theme.colorScheme.primary.withValues(
                                    alpha: 0.5,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          errorWidget: (context, url, error) => Container(
                            height: 160,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.errorContainer
                                  .withValues(alpha: 0.3),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.error_outline_rounded,
                                  color: theme.colorScheme.error,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '图片无法载入',
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: theme.colorScheme.onErrorContainer,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (alt != null && alt.trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(
                          top: 12,
                          left: 8,
                          right: 8,
                        ),
                        child: Text(
                          alt,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
          if (detail.platform.toLowerCase() == 'bilibili')
            _buildBilibiliStats(context, detail),
        ],
      );
    }

    // Default (Twitter etc) or no Markdown found: Text + Grid
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
                baseUrl: apiBaseUrl,
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

  List<String> _extractAllMedia(ContentDetail detail, String apiBaseUrl) {
    final list = <String>{};
    final storedMap = _getStoredMap(detail);

    if (detail.mediaUrls.isNotEmpty) {
      for (var url in detail.mediaUrls) {
        if (url.isEmpty) continue;

        if (storedMap.containsKey(url)) {
          list.add(_mapUrl(storedMap[url]!, apiBaseUrl));
        } else {
          final cleanUrl = url.split('?').first;
          final match = storedMap.entries.firstWhere(
            (e) => e.key.split('?').first == cleanUrl,
            orElse: () => const MapEntry('', ''),
          );

          if (match.key.isNotEmpty) {
            list.add(_mapUrl(match.value, apiBaseUrl));
          } else {
            list.add(_mapUrl(url, apiBaseUrl));
          }
        }
      }
    }

    return list.toList();
  }

  Map<String, String> _getStoredMap(ContentDetail detail) {
    Map<String, String> storedMap = {};
    try {
      if (detail.rawMetadata != null &&
          detail.rawMetadata!['archive'] != null) {
        final archive = detail.rawMetadata!['archive'];

        // 1. Images
        final storedImages = archive['stored_images'];
        if (storedImages is List) {
          for (var img in storedImages) {
            if (img is Map && img['orig_url'] != null) {
              String? localPath = img['url'];
              final String? key = img['key'];
              if (key != null) {
                if (key.startsWith('sha256:')) {
                  final hashVal = key.split(':')[1];
                  localPath =
                      'vaultstream/blobs/sha256/${hashVal.substring(0, 2)}/${hashVal.substring(2, 4)}/$hashVal.webp';
                } else {
                  localPath = key;
                }
              }
              if (localPath != null) storedMap[img['orig_url']] = localPath;
            }
          }
        }

        // 2. Videos
        final storedVideos = archive['stored_videos'];
        if (storedVideos is List) {
          for (var vid in storedVideos) {
            if (vid is Map && vid['orig_url'] != null) {
              String? localPath = vid['url'];
              final String? key = vid['key'];
              if (key != null) {
                if (key.startsWith('sha256:')) {
                  final hashVal = key.split(':')[1];
                  final ext = key.split('.').last;
                  localPath =
                      'vaultstream/blobs/sha256/${hashVal.substring(0, 2)}/${hashVal.substring(2, 4)}/$hashVal.$ext';
                } else {
                  localPath = key;
                }
              }
              if (localPath != null) storedMap[vid['orig_url']] = localPath;
            }
          }
        }
      }
    } catch (_) {}
    return storedMap;
  }

  String _mapUrl(String url, String apiBaseUrl) {
    if (url.isEmpty) return url;

    // 0. 处理协议相对路径
    if (url.startsWith('//')) {
      url = 'https:$url';
    }

    // 1. 处理需要代理的外部域名 (针对 B 站、Twitter 图片反盗链)
    if (url.contains('pbs.twimg.com') ||
        url.contains('hdslb.com') ||
        url.contains('bilibili.com') ||
        url.contains('xhscdn.com') ||
        url.contains('sinaimg.cn') ||
        url.contains('zhimg.com')) {
      // 避免重复代理
      if (url.contains('/proxy/image?url=')) return url;
      return '$apiBaseUrl/proxy/image?url=${Uri.encodeComponent(url)}';
    }

    // 2. 核心修复：防止重复添加 /media/ 前缀
    // 如果 URL 已经包含 /api/v1/media/，直接返回
    if (url.contains('/api/v1/media/')) return url;

    // 3. 处理本地存储路径 (归档的 blobs)
    if (url.contains('blobs/sha256/')) {
      // 3.1 如果已经包含了 /media/ 但没有 /api/v1/
      if (url.startsWith('/media/') || url.contains('/media/')) {
        final path = url.contains('http')
            ? url.substring(url.indexOf('/media/'))
            : url;
        final cleanPath = path.startsWith('/') ? path : '/$path';
        return '$apiBaseUrl$cleanPath';
      }

      // 3.2 如果包含了 /api/v1/ 但没有 /media/
      if (url.contains('/api/v1/')) {
        return url.replaceFirst('/api/v1/', '/api/v1/media/');
      }

      // 3.3 纯相对路径的情况
      final cleanKey = url.startsWith('/') ? url.substring(1) : url;
      return '$apiBaseUrl/media/$cleanKey';
    }

    // 4. 处理其他原本就在 /media 下的路径
    if (url.startsWith('/media') || url.contains('/media/')) {
      final path = url.contains('http')
          ? url.substring(url.indexOf('/media/'))
          : url;
      final cleanPath = path.startsWith('/') ? path : '/$path';
      return '$apiBaseUrl$cleanPath';
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
