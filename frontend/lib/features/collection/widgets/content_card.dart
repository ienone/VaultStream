import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:palette_generator/palette_generator.dart';
import '../../../core/layout/responsive_layout.dart';
import '../../../theme/app_theme.dart';
import '../models/content.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/image_headers.dart';

class ContentCard extends ConsumerStatefulWidget {
  final ShareCard content;
  final VoidCallback? onTap;

  const ContentCard({super.key, required this.content, this.onTap});

  @override
  ConsumerState<ContentCard> createState() => _ContentCardState();
}

class _ContentCardState extends ConsumerState<ContentCard> {
  bool _isHovered = false;
  Color? _extractedColor;
  static final Map<String, Color> _paletteCache = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updatePalette();
    });
  }

  @override
  void didUpdateWidget(ContentCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.content.id != widget.content.id ||
        oldWidget.content.coverUrl != widget.content.coverUrl) {
      _updatePalette();
    }
  }

  Future<void> _updatePalette() async {
    if (!mounted) return;

    // 1. 优先使用后端预提取的颜色
    // 同时检查封面颜色字段和元数据中的颜色信息
    String? backendColor =
        widget.content.coverColor ??
        widget.content.rawMetadata?['archive']?['dominant_color'];

    if (backendColor != null && backendColor.startsWith('#')) {
      final color = AppTheme.parseHexColor(backendColor);
      if (mounted) {
        setState(() {
          _extractedColor = AppTheme.getAdjustedColor(
            color,
            Theme.of(context).brightness,
          );
        });
        return;
      }
    }

    final dio = ref.read(apiClientProvider);
    final apiBaseUrl = dio.options.baseUrl;
    final apiToken = dio.options.headers['X-API-Token']?.toString();

    final imageUrl = _getDisplayImageUrl(apiBaseUrl);
    if (imageUrl.isEmpty) return;

    // 2. 检查本地提取缓存
    if (_paletteCache.containsKey(imageUrl)) {
      if (mounted) {
        setState(() => _extractedColor = _paletteCache[imageUrl]);
      }
      return;
    }

    // 3. 异步延迟，避免在列表快速滚动时瞬间开启大量计算任务
    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;

    final imageHeaders = buildImageHeaders(
      imageUrl: imageUrl,
      baseUrl: apiBaseUrl,
      apiToken: apiToken,
    );

    try {
      final paletteGenerator = await PaletteGenerator.fromImageProvider(
        CachedNetworkImageProvider(imageUrl, headers: imageHeaders),
        // 减小取色区域及采样点，降低计算压力
        maximumColorCount: 8,
        region: const Rect.fromLTWH(0, 0, 100, 100),
      );

      if (mounted) {
        final color =
            paletteGenerator.vibrantColor?.color ??
            paletteGenerator.dominantColor?.color;

        if (color != null) {
          // 4. 转换并缓存调整后的颜色
          final adjustedColor = AppTheme.getAdjustedColor(
            color,
            Theme.of(context).brightness,
          );
          _paletteCache[imageUrl] = adjustedColor;
          setState(() => _extractedColor = adjustedColor);
        }
      }
    } catch (e) {
      // 忽略提取失败
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final content = widget.content;

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
    final isTwitter = content.isTwitter;
    final hasImage = imageUrl.isNotEmpty;

    final double cardWidth = ResponsiveLayout.getCardWidth(context);
    final bool isTinyCard = cardWidth < 220; // 卡片宽度较小时视为极小卡片

    // 根据封面图宽高比确定卡片布局比例
    final bool isLandscapeCover = content.isLandscapeCover;

    // 标准化图片比例：横屏统一 16:9，竖屏统一 4:5 (0.8)
    final double imageAspectRatio = isLandscapeCover ? 16 / 9 : 0.8;

    // 平衡点：回归固定比例布局以保证对齐美感，但根据卡片宽度选择不同的高度比例
    final double cardAspectRatio = isLandscapeCover
        ? (isTinyCard ? 16 / 20 : 16 / 18)
        : (isTinyCard ? 0.46 : 0.52);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedScale(
        scale: _isHovered ? 1.02 : 1.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutBack,
        child: AspectRatio(
          aspectRatio: cardAspectRatio,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: _isHovered
                  ? [
                      BoxShadow(
                        color: (_extractedColor ?? colorScheme.primary)
                            .withAlpha(40),
                        blurRadius: 15,
                        spreadRadius: 1,
                        offset: const Offset(0, 6),
                      ),
                    ]
                  : null,
            ),
            child: Card(
              elevation: 0,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: _isHovered && _extractedColor != null
                      ? _extractedColor!.withAlpha(120)
                      : colorScheme.outlineVariant.withAlpha(80),
                  width: _isHovered ? 1.5 : 1,
                ),
              ),
              color: _isHovered && _extractedColor != null
                  ? Color.alphaBlend(
                      _extractedColor!.withAlpha(20),
                      colorScheme.surfaceContainer,
                    )
                  : colorScheme.surfaceContainer,
              child: InkWell(
                onTap: widget.onTap,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Image Section
                    if (hasImage)
                      AspectRatio(
                        aspectRatio: imageAspectRatio,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Hero(
                              tag: 'content-image-${content.id}',
                              child: CachedNetworkImage(
                                imageUrl: imageUrl,
                                httpHeaders: imageHeaders,
                                fit: BoxFit.cover,
                                maxHeightDiskCache: 800,
                                placeholder: (context, url) => Container(
                                  color: colorScheme.surfaceContainerHighest,
                                  child: const Center(
                                    child: SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
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
                                right: 12,
                                bottom: 12,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withAlpha(150),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.filter_none_outlined,
                                        size: 12,
                                        color: Colors.white,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${content.mediaUrls.length}',
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
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
                      ),

                    // 内容区域
                    Expanded(
                      child: Padding(
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
                                    style: theme.textTheme.labelMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.w700,
                                          color:
                                              _isHovered &&
                                                  _extractedColor != null
                                              ? _extractedColor
                                              : colorScheme.onSurfaceVariant,
                                          letterSpacing: 0.1,
                                          fontSize: isTinyCard ? 11 : 12,
                                        ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            // Title / Content Text
                            Expanded(
                              child: isTwitter
                                  ? (content.description != null &&
                                            content.description!.isNotEmpty
                                        ? Text(
                                            content.description!.trim(),
                                            style: theme.textTheme.bodyMedium
                                                ?.copyWith(
                                                  fontSize: isTinyCard
                                                      ? 12
                                                      : 13,
                                                  height: 1.4,
                                                  fontWeight: FontWeight.w500,
                                                  color: colorScheme.onSurface,
                                                ),
                                            maxLines: isTinyCard ? 3 : 4,
                                            overflow: TextOverflow.ellipsis,
                                          )
                                        : const SizedBox.shrink())
                                  : (content.title != null
                                        ? Text(
                                            content.title!,
                                            style: theme.textTheme.titleMedium
                                                ?.copyWith(
                                                  fontSize: isTinyCard
                                                      ? 13
                                                      : 14,
                                                  fontWeight: FontWeight.w800,
                                                  height: 1.3,
                                                  color: colorScheme.onSurface,
                                                  letterSpacing: -0.2,
                                                ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          )
                                        : const SizedBox.shrink()),
                            ),
                            const SizedBox(height: 8),
                            // Tags & Stats Row
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                if (content.tags.isNotEmpty)
                                  Expanded(
                                    child: Wrap(
                                      spacing: 4,
                                      runSpacing: 4,
                                      children: content.tags
                                          .take(isTinyCard ? 1 : 2)
                                          .map(
                                            (tag) => Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 2,
                                                  ),
                                              decoration: BoxDecoration(
                                                color:
                                                    (_extractedColor ??
                                                            colorScheme.primary)
                                                        .withAlpha(25),
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                '#$tag',
                                                style: theme
                                                    .textTheme
                                                    .labelSmall
                                                    ?.copyWith(
                                                      color:
                                                          _extractedColor ??
                                                          colorScheme.primary,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      fontSize: 10,
                                                    ),
                                              ),
                                            ),
                                          )
                                          .toList(),
                                    ),
                                  )
                                else
                                  const SizedBox.shrink(),
                                const SizedBox(width: 8),
                                // Date & Stats
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    if (!isTinyCard &&
                                        content.publishedAt != null)
                                      Text(
                                        DateFormat('yyyy-MM-dd').format(
                                          content.publishedAt!.toLocal(),
                                        ),
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                              color: colorScheme.outline
                                                  .withAlpha(150),
                                              fontSize: 10,
                                            ),
                                      ),
                                    const SizedBox(height: 2),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (content.viewCount > 0) ...[
                                          Icon(
                                            Icons.remove_red_eye_outlined,
                                            size: 12,
                                            color: _isHovered && _extractedColor != null 
                                                ? _extractedColor 
                                                : colorScheme.outline,
                                          ),
                                          const SizedBox(width: 2),
                                          Text(
                                            _formatCount(content.viewCount),
                                            style: theme.textTheme.labelSmall
                                                ?.copyWith(
                                                  color: _isHovered && _extractedColor != null 
                                                      ? _extractedColor 
                                                      : colorScheme.outline,
                                                  fontSize: 10,
                                                ),
                                          ),
                                        ],
                                        if (content.likeCount > 0) ...[
                                          if (content.viewCount > 0)
                                            const SizedBox(width: 6),
                                          Icon(
                                            Icons.favorite_border,
                                            size: 11,
                                            color: _isHovered && _extractedColor != null 
                                                ? _extractedColor 
                                                : colorScheme.outline,
                                          ),
                                          const SizedBox(width: 2),
                                          Text(
                                            _formatCount(content.likeCount),
                                            style: theme.textTheme.labelSmall
                                                ?.copyWith(
                                                  color: _isHovered && _extractedColor != null 
                                                      ? _extractedColor 
                                                      : colorScheme.outline,
                                                  fontSize: 10,
                                                ),
                                          ),
                                        ],
                                      ],
                                    ),
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
    final content = widget.content;
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(isDark ? 50 : 30),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(80), width: 0.5),
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
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
