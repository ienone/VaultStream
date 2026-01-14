import '../models/content.dart';

class ContentMediaHelper {
  static String getDisplayImageUrl(ShareCard content, String apiBaseUrl) {
    String url = '';
    // 封面优先，B站Opus等特殊场景回退到首张媒体图
    if (content.coverUrl != null &&
        content.coverUrl!.isNotEmpty &&
        !isVideo(content.coverUrl!)) {
      url = content.coverUrl!;
    } else if (content.mediaUrls.isNotEmpty) {
      // 找第一个不是视频的媒体
      try {
        url = content.mediaUrls.firstWhere((u) => !isVideo(u));
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
                return mapUrl(localPath, apiBaseUrl);
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
                  return mapUrl(localPath, apiBaseUrl);
                }
              }
            }
          }
        }
      }
    } catch (_) {}

    return mapUrl(url, apiBaseUrl);
  }

  static String mapUrl(String url, String apiBaseUrl) {
    if (url.isEmpty) return url;
    if (url.startsWith('//')) url = 'https:$url';

    // 1. 处理需要代理的外部域名
    if (url.contains('pbs.twimg.com') ||
        url.contains('hdslb.com') ||
        url.contains('bilibili.com') ||
        url.contains('xhscdn.com') || // 小红书
        url.contains('sinaimg.cn') || // 微博
        url.contains('zhimg.com')) {
      // 知乎
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
        if (cleanPath == '/media' || cleanPath == '/media/') return '';
        return '$apiBaseUrl$cleanPath';
      }
      if (url.contains('/api/v1/')) {
        return url.replaceFirst('/api/v1/', '/api/v1/media/');
      }
      final cleanKey = url.startsWith('/') ? url.substring(1) : url;
      if (cleanKey.isEmpty) return '';
      return '$apiBaseUrl/media/$cleanKey';
    }

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

  static bool isVideo(String url) {
    if (url.isEmpty) return false;
    final lower = url.toLowerCase().split('?').first;
    return lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.webm') ||
        lower.endsWith('.mkv');
  }

  static bool _compareUrls(dynamic url1, String? url2) {
    if (url1 == null || url2 == null) return false;
    final s1 = url1.toString().split('?').first;
    final s2 = url2.split('?').first;
    return s1 == s2;
  }

  static String formatCount(int count) {
    if (count >= 10000) {
      return '${(count / 10000).toStringAsFixed(1)}w';
    } else if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}k';
    }
    return count.toString();
  }
}
