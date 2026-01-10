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
    @JsonKey(name: 'author_avatar_url') String? authorAvatarUrl,
    @JsonKey(name: 'cover_url') String? coverUrl,
    @JsonKey(name: 'cover_color') String? coverColor,
    @JsonKey(name: 'media_urls') @Default([]) List<String> mediaUrls,
    @Default([]) List<String> tags,
    @JsonKey(name: 'view_count') @Default(0) int viewCount,
    @JsonKey(name: 'like_count') @Default(0) int likeCount,
    @JsonKey(name: 'published_at') DateTime? publishedAt,
    @JsonKey(name: 'raw_metadata') Map<String, dynamic>? rawMetadata,
  }) = _ShareCard;

  bool get isTwitter =>
      platform.toLowerCase() == 'twitter' || platform.toLowerCase() == 'x';

  bool get isBilibili => platform.toLowerCase() == 'bilibili';

  bool get isXiaohongshu => platform.toLowerCase() == 'xiaohongshu';
  bool get isWeibo => platform.toLowerCase() == 'weibo';
  bool get isZhihu => platform.toLowerCase() == 'zhihu';

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
    required String url,
    @JsonKey(name: 'clean_url') String? cleanUrl,
    required String status,
    @JsonKey(name: 'review_status') String? reviewStatus,
    required List<String> tags,
    @JsonKey(name: 'is_nsfw') required bool isNsfw,
    String? title,
    String? description,
    @JsonKey(name: 'author_name') String? authorName,
    @JsonKey(name: 'author_avatar_url') String? authorAvatarUrl,
    @JsonKey(name: 'cover_url') String? coverUrl,
    @JsonKey(name: 'cover_color') String? coverColor,
    @JsonKey(name: 'created_at') required DateTime createdAt,
    @JsonKey(name: 'updated_at') required DateTime updatedAt,
    @JsonKey(name: 'published_at') DateTime? publishedAt,
    @JsonKey(name: 'media_urls') @Default([]) List<String> mediaUrls,
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
