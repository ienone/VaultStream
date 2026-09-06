import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../../core/utils/media_utils.dart' as media_utils;
import '../../../core/constants/platform_constants.dart';
import '../models/content.dart';
import '../models/header_line.dart';
import '../../../core/media/media_asset.dart';

class ContentParser {
  static List<String> extractAllImages(
    ContentDetail detail, {
    bool includeAvatarFallback = false,
  }) {
    final archivedImages = extractImageAssets(detail);
    if (archivedImages.isNotEmpty) {
      return archivedImages
          .map((asset) => asset.sources.first.url)
          .toSet()
          .toList(growable: false);
    }
    if (!includeAvatarFallback) return const [];
    final avatar = detail.mediaAssets.firstFor(
      role: MediaRole.avatar,
      type: MediaType.image,
    );
    final source = avatar?.sources.firstOrNull;
    return source == null ? const [] : [source.url];
  }

  static List<MediaAsset> extractImageAssets(ContentDetail detail) {
    final assets = detail.mediaAssets
        .where(
          (asset) =>
              asset.mediaType == MediaType.image &&
              asset.role != MediaRole.avatar &&
              asset.sources.isNotEmpty,
        )
        .toList();
    const roleOrder = {
      MediaRole.cover: 0,
      MediaRole.poster: 1,
      MediaRole.body: 2,
      MediaRole.gallery: 3,
      MediaRole.attachment: 4,
      MediaRole.avatar: 5,
    };
    assets.sort((a, b) {
      final byRole = roleOrder[a.role]!.compareTo(roleOrder[b.role]!);
      return byRole != 0 ? byRole : a.position.compareTo(b.position);
    });
    return assets;
  }

  static MediaAsset? imageAssetForUrl(ContentDetail detail, String rawUrl) {
    final asset = mediaAssetForUrl(detail, rawUrl);
    return asset?.mediaType == MediaType.image ? asset : null;
  }

  static MediaAsset? mediaAssetForUrl(ContentDetail detail, String rawUrl) {
    for (final asset in detail.mediaAssets) {
      if (asset.sources.any((source) => source.url == rawUrl)) {
        return asset;
      }
    }
    return null;
  }

  /// 以每项首选 URL 为键，保留后端给出的后续候选顺序。
  static Map<String, List<String>> extractImageFallbacks(
    ContentDetail detail,
  ) => {
    for (final asset in detail.mediaAssets)
      if (asset.mediaType == MediaType.image && asset.sources.isNotEmpty)
        asset.sources.first.url: asset.sources
            .skip(1)
            .map((source) => source.url)
            .toList(growable: false),
  };

  /// 将正文中的精确来源 URL 解析回同一资产的后端候选顺序。
  ///
  /// 仅按 contract 中的完整 URL 匹配，不按域名、文件名或相似字符串猜测。
  static List<String> imageCandidatesForUrl(
    ContentDetail detail,
    String rawUrl,
  ) {
    for (final asset in detail.mediaAssets) {
      if (asset.mediaType != MediaType.image || asset.sources.isEmpty) continue;
      if (asset.sources.any((source) => source.url == rawUrl)) {
        return asset.sources
            .map((source) => source.url)
            .toList(growable: false);
      }
    }
    return const [];
  }

  static List<String> extractAllMedia(ContentDetail detail) {
    final archivedMedia = detail.mediaAssets.where(
      (asset) =>
          asset.role != MediaRole.avatar &&
          asset.role != MediaRole.cover &&
          asset.role != MediaRole.poster &&
          asset.sources.isNotEmpty,
    );
    return archivedMedia
        .map((asset) => asset.sources.first.url)
        .toSet()
        .toList(growable: false);
  }

  static bool hasMarkdown(ContentDetail detail) {
    if (detail.isZhihuArticle || detail.isZhihuAnswer) return true;
    return detail.platform.isBilibili && (detail.body?.contains('![') ?? false);
  }

  static String getMarkdownContent(ContentDetail detail) {
    return detail.body ?? '';
  }

  /// Returns the effective layout type, inferring 'gallery' for media-only
  /// items (no markdown body) that lack an explicit layout_type — mirrors the
  /// backend's infer_layout_type() logic.
  static String getEffectiveLayoutType(ContentDetail detail) {
    final lt = detail.layoutType ?? 'article';
    if (lt == 'gallery' || lt == 'video') return lt;
    // Infer gallery when there are media attachments but no text body
    if (detail.mediaAssets.isNotEmpty && getMarkdownContent(detail).isEmpty) {
      return 'gallery';
    }
    return lt;
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

  /// 格式化数字显示
  /// 直接调用 media_utils 处理媒体资源。
  static String formatCount(dynamic count) => media_utils.formatCount(count);
}
