import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../../core/utils/media_utils.dart' as media_utils;
import '../../../core/constants/platform_constants.dart';
import '../models/content.dart';
import '../models/header_line.dart';

class ContentParser {
  static List<String> extractAllImages(
    ContentDetail detail,
    String apiBaseUrl, {
    bool includeAvatarFallback = false,
  }) {
    final list = <String>{};

    // 获取作者头像以便过滤
    final authorAvatar = detail.authorAvatarUrl;

    // 1. 优先添加封面图 (如果不是视频)
    if (detail.coverUrl != null &&
        detail.coverUrl!.isNotEmpty &&
        !media_utils.isVideo(detail.coverUrl!)) {
      final url = detail.coverUrl!;
      // 过滤头像
      if (authorAvatar == null || !url.contains(authorAvatar)) {
        list.add(media_utils.mapUrl(url, apiBaseUrl));
      }
    }

    // 2. 添加媒体列表中的图片
    if (detail.mediaUrls.isNotEmpty) {
      for (var item in detail.mediaUrls) {
        final String url = item.toString();
        if (url.isEmpty || media_utils.isVideo(url)) continue;

        // 过滤头像
        if (authorAvatar != null && url.contains(authorAvatar)) continue;

        list.add(media_utils.mapUrl(url, apiBaseUrl));
      }
    }
    
    // 无图时使用头像补充
    if (list.isEmpty && includeAvatarFallback && authorAvatar != null) {
      list.add(media_utils.mapUrl(authorAvatar, apiBaseUrl));
    }
    
    return list.toList();
  }

  static List<String> extractAllMedia(ContentDetail detail, String apiBaseUrl) {
    final list = <String>{};

    // 获取作者头像 URL，用于排除
    final authorAvatar = detail.authorAvatarUrl;

    if (detail.mediaUrls.isNotEmpty) {
      for (var item in detail.mediaUrls) {
        final String url = item.toString();
        if (url.isEmpty) continue;

        // 如果该媒体是作者头像，则跳过（防止在正文大图/网格中显示）
        if (authorAvatar != null && url.contains(authorAvatar)) continue;

        list.add(media_utils.mapUrl(url, apiBaseUrl));
      }
    }
    return list.toList();
  }

  static bool hasMarkdown(ContentDetail detail) {
    if (detail.isZhihuArticle || detail.isZhihuAnswer) return true;
    return detail.platform.isBilibili && (detail.body?.contains('![') ?? false);
  }

  static String getMarkdownContent(ContentDetail detail) {
    return detail.body ?? '';
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
  /// 后端已返回优化后的coverUrl，直接使用即可
  static String getDisplayImageUrl(ShareCard content, String apiBaseUrl) {
    String url = '';
    // 封面优先
    if (content.coverUrl != null &&
        content.coverUrl!.isNotEmpty &&
        !media_utils.isVideo(content.coverUrl!)) {
      url = content.coverUrl!;
    }

    // 无封面时，使用作者头像
    if (url.isEmpty && content.authorAvatarUrl != null && content.authorAvatarUrl!.isNotEmpty) {
      url = content.authorAvatarUrl!;
    }

    return url.isEmpty ? '' : media_utils.mapUrl(url, apiBaseUrl);
  }


  /// 格式化数字显示
  /// 直接调用 media_utils 处理媒体资源。
  static String formatCount(dynamic count) => media_utils.formatCount(count);
}
