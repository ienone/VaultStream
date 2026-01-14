import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../models/content.dart';
import '../models/header_line.dart';

class ContentParser {
  static bool isVideo(String url) {
    final lower = url.toLowerCase().split('?').first;
    return lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.webm') ||
        lower.endsWith('.mkv');
  }

  static String mapUrl(String url, String apiBaseUrl) {
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
      if (url.contains('/proxy/image?url=')) return url;
      return '$apiBaseUrl/proxy/image?url=${Uri.encodeComponent(url)}';
    }

    // 2. 核心修复：防止重复添加 /media/ 前缀
    // 如果 URL 已经包含 /api/v1/media/，直接返回
    if (url.contains('/api/v1/media/')) return url;

    // 3. 处理包含本地存储路径的情况 (归档的 blobs)
    if (url.contains('blobs/sha256/')) {
      // 3.1 如果已经包含了 /media/ 但没有 /api/v1/
      if (url.startsWith('/media/') || url.contains('/media/')) {
        final path = url.contains('http')
            ? url.substring(url.indexOf('/media/'))
            : url;
        final cleanPath = path.startsWith('/') ? path : '/$path';
        if (cleanPath == '/media' || cleanPath == '/media/') return '';
        return '$apiBaseUrl$cleanPath';
      }

      // 3.2 如果包含了 /api/v1/ 但没有 /media/
      if (url.contains('/api/v1/')) {
        return url.replaceFirst('/api/v1/', '/api/v1/media/');
      }

      // 3.3 纯相对路径的情况
      final cleanKey = url.startsWith('/') ? url.substring(1) : url;
      if (cleanKey.isEmpty) return '';
      return '$apiBaseUrl/media/$cleanKey';
    }

    // 4. 处理其他原本就在 /media 下的普通路径
    if (url.startsWith('/media') || url.contains('/media/')) {
      final path = url.contains('http')
          ? url.substring(url.indexOf('/media/'))
          : url;
      final cleanPath = path.startsWith('/') ? path : '/$path';
      if (cleanPath == '/media' || cleanPath == '/media/') return '';
      return '$apiBaseUrl$cleanPath';
    }

    return url;
  }

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
    if (detail.mediaUrls.isNotEmpty) {
      for (var item in detail.mediaUrls) {
        final String url = item.toString();
        if (url.isEmpty || isVideo(url)) continue;
        if (storedMap.containsKey(url)) {
          list.add(mapUrl(storedMap[url]!, apiBaseUrl));
        } else {
          final cleanUrl = url.split('?').first;
          final match = storedMap.entries.firstWhere(
            (e) => e.key.split('?').first == cleanUrl,
            orElse: () => const MapEntry('', ''),
          );
          list.add(
            match.key.isNotEmpty
                ? mapUrl(match.value, apiBaseUrl)
                : mapUrl(url, apiBaseUrl),
          );
        }
      }
    }
    return list.toList();
  }

  static List<String> extractAllMedia(
    ContentDetail detail,
    String apiBaseUrl,
  ) {
    final list = <String>{};
    final storedMap = getStoredMap(detail);
    if (detail.mediaUrls.isNotEmpty) {
      for (var item in detail.mediaUrls) {
        final String url = item.toString();
        if (url.isEmpty) continue;
        if (storedMap.containsKey(url)) {
          list.add(mapUrl(storedMap[url]!, apiBaseUrl));
        } else {
          final cleanUrl = url.split('?').first;
          final match = storedMap.entries.firstWhere(
            (e) => e.key.split('?').first == cleanUrl,
            orElse: () => const MapEntry('', ''),
          );
          list.add(
            match.key.isNotEmpty
                ? mapUrl(match.value, apiBaseUrl)
                : mapUrl(url, apiBaseUrl),
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
    final lines = markdown.split('\n');
    final List<HeaderLine> headers = [];
    final Map<String, int> counts = {};

    for (var line in lines) {
      final match = RegExp(r'^(#{1,6})\s+(.+)$').firstMatch(line);
      if (match != null) {
        var text = match.group(2)!;
        text = text.replaceAll(RegExp(r'[*_`~]'), '');
        if (text.trim().isEmpty) continue;
        final count = counts[text] ?? 0;
        counts[text] = count + 1;
        final uniqueId = count == 0 ? text : '$text-$count';
        headers.add(HeaderLine(
          level: match.group(1)!.length,
          text: text,
          uniqueId: uniqueId,
        ));
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
