// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'content.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_ShareCard _$ShareCardFromJson(Map<String, dynamic> json) => _ShareCard(
  id: (json['id'] as num).toInt(),
  platform: json['platform'] as String,
  url: json['url'] as String,
  title: json['title'] as String?,
  summary: json['summary'] as String?,
  description: json['description'] as String?,
  authorName: json['author_name'] as String?,
  coverUrl: json['cover_url'] as String?,
  mediaUrls:
      (json['media_urls'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      const [],
  tags:
      (json['tags'] as List<dynamic>?)?.map((e) => e as String).toList() ??
      const [],
  viewCount: (json['view_count'] as num?)?.toInt() ?? 0,
  likeCount: (json['like_count'] as num?)?.toInt() ?? 0,
  publishedAt: json['published_at'] == null
      ? null
      : DateTime.parse(json['published_at'] as String),
  rawMetadata: json['raw_metadata'] as Map<String, dynamic>?,
);

Map<String, dynamic> _$ShareCardToJson(_ShareCard instance) =>
    <String, dynamic>{
      'id': instance.id,
      'platform': instance.platform,
      'url': instance.url,
      'title': instance.title,
      'summary': instance.summary,
      'description': instance.description,
      'author_name': instance.authorName,
      'cover_url': instance.coverUrl,
      'media_urls': instance.mediaUrls,
      'tags': instance.tags,
      'view_count': instance.viewCount,
      'like_count': instance.likeCount,
      'published_at': instance.publishedAt?.toIso8601String(),
      'raw_metadata': instance.rawMetadata,
    };

_ContentDetail _$ContentDetailFromJson(Map<String, dynamic> json) =>
    _ContentDetail(
      id: (json['id'] as num).toInt(),
      platform: json['platform'] as String,
      platformId: json['platform_id'] as String?,
      contentType: json['content_type'] as String?,
      url: json['url'] as String,
      cleanUrl: json['clean_url'] as String?,
      status: json['status'] as String,
      reviewStatus: json['review_status'] as String?,
      tags: (json['tags'] as List<dynamic>).map((e) => e as String).toList(),
      isNsfw: json['is_nsfw'] as bool,
      title: json['title'] as String?,
      description: json['description'] as String?,
      authorName: json['author_name'] as String?,
      coverUrl: json['cover_url'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      publishedAt: json['published_at'] == null
          ? null
          : DateTime.parse(json['published_at'] as String),
      mediaUrls:
          (json['media_urls'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      viewCount: (json['view_count'] as num?)?.toInt() ?? 0,
      likeCount: (json['like_count'] as num?)?.toInt() ?? 0,
      extraStats: json['extra_stats'] as Map<String, dynamic>? ?? const {},
      rawMetadata: json['raw_metadata'] as Map<String, dynamic>?,
    );

Map<String, dynamic> _$ContentDetailToJson(_ContentDetail instance) =>
    <String, dynamic>{
      'id': instance.id,
      'platform': instance.platform,
      'platform_id': instance.platformId,
      'content_type': instance.contentType,
      'url': instance.url,
      'clean_url': instance.cleanUrl,
      'status': instance.status,
      'review_status': instance.reviewStatus,
      'tags': instance.tags,
      'is_nsfw': instance.isNsfw,
      'title': instance.title,
      'description': instance.description,
      'author_name': instance.authorName,
      'cover_url': instance.coverUrl,
      'created_at': instance.createdAt.toIso8601String(),
      'updated_at': instance.updatedAt.toIso8601String(),
      'published_at': instance.publishedAt?.toIso8601String(),
      'media_urls': instance.mediaUrls,
      'view_count': instance.viewCount,
      'like_count': instance.likeCount,
      'extra_stats': instance.extraStats,
      'raw_metadata': instance.rawMetadata,
    };

_ContentListResponse _$ContentListResponseFromJson(Map<String, dynamic> json) =>
    _ContentListResponse(
      items: (json['items'] as List<dynamic>)
          .map((e) => ContentDetail.fromJson(e as Map<String, dynamic>))
          .toList(),
      total: (json['total'] as num).toInt(),
      page: (json['page'] as num).toInt(),
      size: (json['size'] as num).toInt(),
      hasMore: json['has_more'] as bool,
    );

Map<String, dynamic> _$ContentListResponseToJson(
  _ContentListResponse instance,
) => <String, dynamic>{
  'items': instance.items,
  'total': instance.total,
  'page': instance.page,
  'size': instance.size,
  'has_more': instance.hasMore,
};

_ShareCardListResponse _$ShareCardListResponseFromJson(
  Map<String, dynamic> json,
) => _ShareCardListResponse(
  items: (json['items'] as List<dynamic>)
      .map((e) => ShareCard.fromJson(e as Map<String, dynamic>))
      .toList(),
  total: (json['total'] as num).toInt(),
  page: (json['page'] as num).toInt(),
  size: (json['size'] as num).toInt(),
  hasMore: json['has_more'] as bool,
);

Map<String, dynamic> _$ShareCardListResponseToJson(
  _ShareCardListResponse instance,
) => <String, dynamic>{
  'items': instance.items,
  'total': instance.total,
  'page': instance.page,
  'size': instance.size,
  'has_more': instance.hasMore,
};
