import '../../../core/utils/media_utils.dart' as media_utils;
import '../models/content.dart';

class ContentMediaHelper {
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

  static bool _compareUrls(dynamic url1, String? url2) {
    if (url1 == null || url2 == null) return false;
    final s1 = url1.toString().split('?').first;
    final s2 = url2.split('?').first;
    return s1 == s2;
  }

  static String formatCount(dynamic count) => media_utils.formatCount(count);
}
