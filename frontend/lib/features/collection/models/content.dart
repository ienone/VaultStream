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
    @JsonKey(name: 'clean_url') String? cleanUrl,
    @JsonKey(name: 'content_type') String? contentType,
    @JsonKey(name: 'effective_layout_type') String? effectiveLayoutType,
    String? title,
    @JsonKey(name: 'author_name') String? authorName,
    @JsonKey(name: 'author_id') String? authorId,
    @JsonKey(name: 'author_avatar_url') String? authorAvatarUrl,
    @JsonKey(name: 'cover_url') String? coverUrl,
    @JsonKey(name: 'thumbnail_url') String? thumbnailUrl,
    @JsonKey(name: 'cover_color') String? coverColor,
    @Default([]) List<String> tags,
    @JsonKey(name: 'is_nsfw') @Default(false) bool isNsfw,
    @JsonKey(name: 'review_status') String? reviewStatus,
    @JsonKey(name: 'published_at') DateTime? publishedAt,
    @JsonKey(name: 'created_at') DateTime? createdAt,
    @JsonKey(name: 'view_count') @Default(0) int viewCount,
    @JsonKey(name: 'like_count') @Default(0) int likeCount,
  }) = _ShareCard;

  bool get isTwitter =>
      platform.toLowerCase() == 'twitter' || platform.toLowerCase() == 'x';

  bool get isBilibili => platform.toLowerCase() == 'bilibili';

  bool get isXiaohongshu => platform.toLowerCase() == 'xiaohongshu';
  bool get isWeibo => platform.toLowerCase() == 'weibo';
  bool get isZhihu => platform.toLowerCase() == 'zhihu';

  /// 获取有效布局类型：后端已计算
  String get resolvedLayoutType {
    if (effectiveLayoutType != null && effectiveLayoutType!.isNotEmpty) {
      return effectiveLayoutType!;
    }
    return 'article';
  }

  bool get isLandscapeCover {
    // ShareCard 使用统一横版卡片展示
    return true; // Default to landscape
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
    
    // New V2 Fields
    @JsonKey(name: 'context_data') Map<String, dynamic>? contextData,
    @JsonKey(name: 'rich_payload') Map<String, dynamic>? richPayload,
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

  /// 获取有效布局类型：直接使用后端计算结果
  String get resolvedLayoutType {
    if (effectiveLayoutType != null && effectiveLayoutType!.isNotEmpty) {
      return effectiveLayoutType!;
    }
    // Fallback if backend didn't provide it (should not happen with V2)
    if (layoutTypeOverride != null && layoutTypeOverride!.isNotEmpty) {
      return layoutTypeOverride!;
    }
    return layoutType ?? 'article';
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
