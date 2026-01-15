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
      default:
        return Icon(Icons.link, size: size);
    }
  }
}
