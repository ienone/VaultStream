import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../../core/utils/media_utils.dart' as media_utils;
import '../models/content.dart';
import '../models/header_line.dart';

class ContentParser {
  static Map<String, String> getStoredMap(ContentDetail detail) {
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
                  // 视频保持原后缀，不强转 webp
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

  static List<String> extractAllImages(
    ContentDetail detail,
    String apiBaseUrl,
  ) {
    final list = <String>{};
    final storedMap = getStoredMap(detail);

    // 获取作者头像以便过滤
    final authorAvatar = detail.authorAvatarUrl;

    if (detail.mediaUrls.isNotEmpty) {
      for (var item in detail.mediaUrls) {
        final String url = item.toString();
        if (url.isEmpty || media_utils.isVideo(url)) continue;

        // 过滤头像
        if (authorAvatar != null && url.contains(authorAvatar)) continue;

        if (storedMap.containsKey(url)) {
          list.add(media_utils.mapUrl(storedMap[url]!, apiBaseUrl));
        } else {
          final cleanUrl = url.split('?')[0];
          final match = storedMap.entries.firstWhere(
            (e) => e.key.split('?')[0] == cleanUrl,
            orElse: () => const MapEntry('', ''),
          );
          list.add(
            match.key.isNotEmpty
                ? media_utils.mapUrl(match.value, apiBaseUrl)
                : media_utils.mapUrl(url, apiBaseUrl),
          );
        }
      }
    }
    return list.toList();
  }

  static List<String> extractAllMedia(ContentDetail detail, String apiBaseUrl) {
    final list = <String>{};
    final storedMap = getStoredMap(detail);

    // 获取作者头像 URL，用于排除
    final authorAvatar = detail.authorAvatarUrl;

    if (detail.mediaUrls.isNotEmpty) {
      for (var item in detail.mediaUrls) {
        final String url = item.toString();
        if (url.isEmpty) continue;

        // 如果该媒体是作者头像，则跳过（防止在正文大图/网格中显示）
        if (authorAvatar != null && url.contains(authorAvatar)) continue;

        if (storedMap.containsKey(url)) {
          list.add(media_utils.mapUrl(storedMap[url]!, apiBaseUrl));
        } else {
          final cleanUrl = url.split('?').first;
          final match = storedMap.entries.firstWhere(
            (e) => e.key.split('?').first == cleanUrl,
            orElse: () => const MapEntry('', ''),
          );
          list.add(
            match.key.isNotEmpty
                ? media_utils.mapUrl(match.value, apiBaseUrl)
                : media_utils.mapUrl(url, apiBaseUrl),
          );
        }
      }
    }
    return list.toList();
  }

  static bool hasMarkdown(ContentDetail detail) {
    if (detail.isZhihuArticle || detail.isZhihuAnswer) return true;
    final archive = detail.rawMetadata?['archive'];
    if (archive != null) {
      final md = archive['markdown'];
      if (md != null && md.toString().isNotEmpty) return true;
    }
    return detail.isBilibili && (detail.description?.contains('![') ?? false);
  }

  static String getMarkdownContent(ContentDetail detail) {
    if (detail.rawMetadata != null && detail.rawMetadata!['archive'] != null) {
      return detail.rawMetadata!['archive']['markdown']?.toString() ?? '';
    }
    if (detail.isBilibili && (detail.description?.contains('![') ?? false)) {
      return detail.description ?? '';
    }
    if ((detail.isZhihuArticle || detail.isZhihuAnswer) &&
        detail.description != null) {
      return detail.description!;
    }
    return '';
  }

  static List<HeaderLine> extractHeaders(String markdown) {
    // 移除代码块，防止代码块内的 ### 被识别为标题
    final cleanedMarkdown = markdown.replaceAll(RegExp(r'```[\s\S]*?```'), '');
    final lines = cleanedMarkdown.split('\n');
    final List<HeaderLine> headers = [];
    final Map<String, int> counts = {};

    for (var line in lines) {
      final match = RegExp(r'^(#{1,6})\s+(.+)$').firstMatch(line.trim());
      if (match != null) {
        var text = match.group(2)!;
        text = text.replaceAll(RegExp(r'[*_`~]'), '');
        if (text.trim().isEmpty) continue;
        final count = counts[text] ?? 0;
        counts[text] = count + 1;
        final uniqueId = count == 0 ? text : '$text-$count';
        headers.add(
          HeaderLine(
            level: match.group(1)!.length,
            text: text,
            uniqueId: uniqueId,
          ),
        );
      }
    }
    return headers;
  }

  static Widget getPlatformIcon(String platform, double size) {
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
      case 'xiaohongshu':
        return Icon(
          Icons.book_outlined,
          size: size,
          color: const Color(0xFFFF2442),
        );
      default:
        return Icon(Icons.link, size: size);
    }
  }

  /// 获取卡片显示的封面图 URL
  /// 从 ContentMediaHelper 迁移，优先使用封面，回退到首张媒体图
  static String getDisplayImageUrl(ShareCard content, String apiBaseUrl) {
    String url = '';
    // 封面优先，B站Opus等特殊场景回退到首张媒体图
    if (content.coverUrl != null &&
        content.coverUrl!.isNotEmpty &&
        !media_utils.isVideo(content.coverUrl!)) {
      url = content.coverUrl!;
    } else if (content.mediaUrls.isNotEmpty) {
      // 找第一个不是视频的媒体
      try {
        url = content.mediaUrls.firstWhere((u) => !media_utils.isVideo(u));
      } catch (_) {
        url = '';
      }
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
                return media_utils.mapUrl(localPath, apiBaseUrl);
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
                  return media_utils.mapUrl(localPath, apiBaseUrl);
                }
              }
            }
          }
        }
      }
    } catch (_) {}

    return media_utils.mapUrl(url, apiBaseUrl);
  }

  /// URL 比较辅助函数
  static bool _compareUrls(dynamic url1, String? url2) {
    if (url1 == null || url2 == null) return false;
    final s1 = url1.toString().split('?').first;
    final s2 = url2.split('?').first;
    return s1 == s2;
  }

  /// 格式化数字显示
  /// 从 ContentMediaHelper 迁移，直接调用 media_utils
  static String formatCount(dynamic count) => media_utils.formatCount(count);
}
