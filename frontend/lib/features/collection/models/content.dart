import 'package:freezed_annotation/freezed_annotation.dart';

part 'content.freezed.dart';
part 'content.g.dart';

@freezed
abstract class ShareCard with _$ShareCard {
  const ShareCard._();

  const factory ShareCard({
    required int id,
    required String platform,
    required String url,
    String? title,
    String? summary,
    String? description,
    @JsonKey(name: 'author_name') String? authorName,
    @JsonKey(name: 'author_id') String? authorId,
    @JsonKey(name: 'author_avatar_url') String? authorAvatarUrl,
    @JsonKey(name: 'author_url') String? authorUrl,
    @JsonKey(name: 'content_type') String? contentType,
    @JsonKey(name: 'layout_type') String? layoutType,
    @JsonKey(name: 'cover_url') String? coverUrl,
    @JsonKey(name: 'thumbnail_url') String? thumbnailUrl,  // 缩略图 (优化加载)
    @JsonKey(name: 'cover_color') String? coverColor,
    @JsonKey(name: 'media_urls') @Default([]) List<String> mediaUrls,
    @Default([]) List<String> tags,
    @JsonKey(name: 'is_nsfw') @Default(false) bool isNsfw,
    @JsonKey(name: 'source_tags') @Default([]) List<String> sourceTags,
    @JsonKey(name: 'review_status') String? reviewStatus,
    @JsonKey(name: 'view_count') @Default(0) int viewCount,
    @JsonKey(name: 'like_count') @Default(0) int likeCount,
    @JsonKey(name: 'collect_count') @Default(0) int collectCount,
    @JsonKey(name: 'share_count') @Default(0) int shareCount,
    @JsonKey(name: 'comment_count') @Default(0) int commentCount,
    @JsonKey(name: 'published_at') DateTime? publishedAt,
    @JsonKey(name: 'raw_metadata') Map<String, dynamic>? rawMetadata,
  }) = _ShareCard;

  bool get isTwitter =>
      platform.toLowerCase() == 'twitter' || platform.toLowerCase() == 'x';

  bool get isBilibili => platform.toLowerCase() == 'bilibili';

  bool get isXiaohongshu => platform.toLowerCase() == 'xiaohongshu';
  bool get isWeibo => platform.toLowerCase() == 'weibo';
  bool get isZhihu => platform.toLowerCase() == 'zhihu';

  /// 获取有效布局类型：后端提供 > 兼容回退
  String get resolvedLayoutType {
    // 后端检测值
    if (layoutType != null && layoutType!.isNotEmpty) {
      return layoutType!;
    }
    // 兼容回退：根据 platform/contentType 推断
    return _fallbackLayoutType();
  }

  String _fallbackLayoutType() {
    if (isBilibili) {
      if (contentType == 'article' || contentType == 'opus') return 'article';
      return 'gallery'; // video/dynamic
    }
    if (isWeibo || isTwitter || isXiaohongshu) return 'gallery';
    if (isZhihu) {
      if (contentType == 'article' || contentType == 'answer') return 'article';
      if (contentType == 'pin') return 'gallery';
      return 'article';
    }
    return 'article'; // 默认
  }

  bool get isLandscapeCover {
    try {
      if (rawMetadata != null && rawMetadata!['archive'] != null) {
        final storedImages = rawMetadata!['archive']['stored_images'];
        if (storedImages is List && storedImages.isNotEmpty) {
          final currentImg = storedImages.firstWhere(
            (img) => _compareUrls(img['orig_url'], coverUrl),
            orElse: () => storedImages.first,
          );
          if (currentImg != null &&
              currentImg['width'] != null &&
              currentImg['height'] != null) {
            return (currentImg['width'] as num) >=
                (currentImg['height'] as num);
          }
        }
      }
    } catch (_) {}
    return true; // Default to landscape
  }

  bool _compareUrls(dynamic url1, dynamic url2) {
    if (url1 == null || url2 == null) return false;
    return url1.toString() == url2.toString();
  }

  factory ShareCard.fromJson(Map<String, dynamic> json) =>
      _$ShareCardFromJson(json);
}

@freezed
abstract class ContentDetail with _$ContentDetail {
  const ContentDetail._();

  const factory ContentDetail({
    required int id,
    required String platform,
    @JsonKey(name: 'platform_id') String? platformId,
    @JsonKey(name: 'content_type') String? contentType,
    @JsonKey(name: 'layout_type') String? layoutType,
    @JsonKey(name: 'layout_type_override') String? layoutTypeOverride,
    @JsonKey(name: 'effective_layout_type') String? effectiveLayoutType,
    required String url,
    @JsonKey(name: 'clean_url') String? cleanUrl,
    required String status,
    @JsonKey(name: 'review_status') String? reviewStatus,
    required List<String> tags,
    @JsonKey(name: 'is_nsfw') required bool isNsfw,
    String? title,
    String? description,
    @JsonKey(name: 'author_name') String? authorName,
    @JsonKey(name: 'author_id') String? authorId,
    @JsonKey(name: 'author_avatar_url') String? authorAvatarUrl,
    @JsonKey(name: 'author_url') String? authorUrl,
    @JsonKey(name: 'cover_url') String? coverUrl,
    @JsonKey(name: 'cover_color') String? coverColor,
    @JsonKey(name: 'created_at') required DateTime createdAt,
    @JsonKey(name: 'updated_at') required DateTime updatedAt,
    @JsonKey(name: 'published_at') DateTime? publishedAt,
    @JsonKey(name: 'media_urls') @Default([]) List<String> mediaUrls,
    @JsonKey(name: 'source_tags') @Default([]) List<String> sourceTags,
    @JsonKey(name: 'view_count') @Default(0) int viewCount,
    @JsonKey(name: 'like_count') @Default(0) int likeCount,
    @JsonKey(name: 'collect_count') @Default(0) int collectCount,
    @JsonKey(name: 'share_count') @Default(0) int shareCount,
    @JsonKey(name: 'comment_count') @Default(0) int commentCount,
    @JsonKey(name: 'extra_stats') @Default({}) Map<String, dynamic> extraStats,
    @JsonKey(name: 'raw_metadata') Map<String, dynamic>? rawMetadata,
  }) = _ContentDetail;

  bool get isTwitter =>
      platform.toLowerCase() == 'twitter' || platform.toLowerCase() == 'x';

  bool get isBilibili => platform.toLowerCase() == 'bilibili';

  bool get isXiaohongshu => platform.toLowerCase() == 'xiaohongshu';
  bool get isWeibo => platform.toLowerCase() == 'weibo';
  bool get isZhihu => platform.toLowerCase() == 'zhihu';

  bool get isZhihuArticle => isZhihu && contentType == 'article';
  bool get isZhihuAnswer => isZhihu && contentType == 'answer';
  bool get isZhihuPin => isZhihu && contentType == 'pin';
  bool get isZhihuQuestion => isZhihu && contentType == 'question';
  bool get isZhihuColumn => isZhihu && contentType == 'column';
  bool get isZhihuCollection => isZhihu && contentType == 'collection';

  /// 获取有效布局类型：用户覆盖 > 后端检测 > 兼容回退
  String get resolvedLayoutType {
    // 优先用户覆盖
    if (layoutTypeOverride != null && layoutTypeOverride!.isNotEmpty) {
      return layoutTypeOverride!;
    }
    // 其次后端提供的有效类型
    if (effectiveLayoutType != null && effectiveLayoutType!.isNotEmpty) {
      return effectiveLayoutType!;
    }
    // 后端检测值
    if (layoutType != null && layoutType!.isNotEmpty) {
      return layoutType!;
    }
    // 兼容回退：根据 platform/contentType 推断
    return _fallbackLayoutType();
  }

  String _fallbackLayoutType() {
    if (isBilibili) {
      if (contentType == 'article' || contentType == 'opus') return 'article';
      return 'gallery'; // video/dynamic
    }
    if (isWeibo || isTwitter || isXiaohongshu) return 'gallery';
    if (isZhihu) {
      if (contentType == 'article' || contentType == 'answer') return 'article';
      if (contentType == 'pin') return 'gallery';
      return 'article';
    }
    return 'article'; // 默认
  }

  factory ContentDetail.fromJson(Map<String, dynamic> json) =>
      _$ContentDetailFromJson(json);
}

@freezed
abstract class ContentListResponse with _$ContentListResponse {
  const factory ContentListResponse({
    required List<ContentDetail> items,
    required int total,
    required int page,
    required int size,
    @JsonKey(name: 'has_more') required bool hasMore,
  }) = _ContentListResponse;

  factory ContentListResponse.fromJson(Map<String, dynamic> json) =>
      _$ContentListResponseFromJson(json);
}

@freezed
abstract class ShareCardListResponse with _$ShareCardListResponse {
  const factory ShareCardListResponse({
    required List<ShareCard> items,
    required int total,
    required int page,
    required int size,
    @JsonKey(name: 'has_more') required bool hasMore,
  }) = _ShareCardListResponse;

  factory ShareCardListResponse.fromJson(Map<String, dynamic> json) =>
      _$ShareCardListResponseFromJson(json);
}
