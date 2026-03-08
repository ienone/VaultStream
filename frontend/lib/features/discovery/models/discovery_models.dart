import 'package:freezed_annotation/freezed_annotation.dart';
import '../../collection/models/content.dart';

part 'discovery_models.freezed.dart';
part 'discovery_models.g.dart';

@freezed
abstract class DiscoveryItem with _$DiscoveryItem {
  const factory DiscoveryItem({
    required int id,
    String? title,
    required String url,
    String? body,
    @JsonKey(name: 'author_name') String? authorName,
    @JsonKey(name: 'author_avatar_url') String? authorAvatarUrl,
    @JsonKey(name: 'author_url') String? authorUrl,
    String? summary,
    @JsonKey(name: 'ai_score') double? aiScore,
    @JsonKey(name: 'ai_reason') String? aiReason,
    @JsonKey(name: 'ai_tags') List<String>? aiTags,
    @JsonKey(name: 'source_type') String? sourceType,
    @JsonKey(name: 'discovery_state') String? discoveryState,
    @JsonKey(name: 'discovered_at') DateTime? discoveredAt,
    @JsonKey(name: 'published_at') DateTime? publishedAt,
    @JsonKey(name: 'created_at') required DateTime createdAt,
    // 详情复用字段
    @JsonKey(name: 'cover_url') String? coverUrl,
    @JsonKey(name: 'cover_color') String? coverColor,
    @JsonKey(name: 'platform_id') String? platformId,
    @JsonKey(name: 'content_type') String? contentType,
    @JsonKey(name: 'layout_type') String? layoutType,
    @JsonKey(name: 'source_tags') @Default([]) List<String> sourceTags,
    @JsonKey(name: 'collect_count') @Default(0) int collectCount,
    @JsonKey(name: 'share_count') @Default(0) int shareCount,
    @JsonKey(name: 'comment_count') @Default(0) int commentCount,
    @JsonKey(name: 'media_urls') @Default([]) List<String> mediaUrls,
    @JsonKey(name: 'rich_payload') Map<String, dynamic>? richPayload,
    @JsonKey(name: 'extra_stats') @Default({}) Map<String, dynamic> extraStats,
    @JsonKey(name: 'context_data') Map<String, dynamic>? contextData,
  }) = _DiscoveryItem;

  factory DiscoveryItem.fromJson(Map<String, dynamic> json) =>
      _$DiscoveryItemFromJson(json);
}

extension DiscoveryItemX on DiscoveryItem {
  ContentDetail toContentDetail() {
    return ContentDetail(
      id: id,
      platform: sourceType ?? 'universal',
      platformId: platformId,
      contentType: contentType,
      layoutType: layoutType ?? 'article',
      url: url,
      status: 'parse_success',
      tags: [],
      isNsfw: false,
      title: title,
      summary: summary,
      body: body ?? summary,
      authorName: authorName,
      authorAvatarUrl: authorAvatarUrl,
      authorUrl: authorUrl,
      coverUrl: coverUrl,
      coverColor: coverColor,
      publishedAt: publishedAt,
      mediaUrls: mediaUrls,
      sourceTags: sourceTags,
      collectCount: collectCount,
      shareCount: shareCount,
      commentCount: commentCount,
      richPayload: richPayload == null ? null : _cloneMap(richPayload!),
      extraStats: _cloneMap(extraStats),
      contextData: contextData == null ? null : _cloneMap(contextData!),
      createdAt: createdAt,
      updatedAt: createdAt,
    );
  }
}

Map<String, dynamic> _cloneMap(Map<String, dynamic> source) {
  return source.map((key, value) => MapEntry(key, _cloneValue(value)));
}

List<dynamic> _cloneList(List<dynamic> source) {
  return source.map(_cloneValue).toList(growable: false);
}

dynamic _cloneValue(dynamic value) {
  if (value is Map<String, dynamic>) {
    return _cloneMap(value);
  }
  if (value is Map) {
    return value.map(
      (key, nestedValue) => MapEntry(key.toString(), _cloneValue(nestedValue)),
    );
  }
  if (value is List) {
    return _cloneList(value);
  }
  return value;
}

@freezed
abstract class DiscoveryItemListResponse with _$DiscoveryItemListResponse {
  const factory DiscoveryItemListResponse({
    required List<DiscoveryItem> items,
    required int total,
    required int page,
    required int size,
    @JsonKey(name: 'has_more') required bool hasMore,
  }) = _DiscoveryItemListResponse;

  factory DiscoveryItemListResponse.fromJson(Map<String, dynamic> json) =>
      _$DiscoveryItemListResponseFromJson(json);
}

@freezed
abstract class DiscoverySource with _$DiscoverySource {
  const factory DiscoverySource({
    required int id,
    required String kind,
    required String name,
    required bool enabled,
    @Default({}) Map<String, dynamic> config,
    @JsonKey(name: 'last_sync_at') DateTime? lastSyncAt,
    @JsonKey(name: 'last_error') String? lastError,
    @JsonKey(name: 'sync_interval_minutes') required int syncIntervalMinutes,
    @JsonKey(name: 'created_at') required DateTime createdAt,
  }) = _DiscoverySource;

  factory DiscoverySource.fromJson(Map<String, dynamic> json) =>
      _$DiscoverySourceFromJson(json);
}

@freezed
abstract class DiscoverySettings with _$DiscoverySettings {
  const factory DiscoverySettings({
    @JsonKey(name: 'interest_profile') @Default('') String interestProfile,
    @JsonKey(name: 'score_threshold') @Default(6.0) double scoreThreshold,
    @JsonKey(name: 'retention_days') @Default(7) int retentionDays,
  }) = _DiscoverySettings;

  factory DiscoverySettings.fromJson(Map<String, dynamic> json) =>
      _$DiscoverySettingsFromJson(json);
}

@freezed
abstract class DiscoveryStats with _$DiscoveryStats {
  const factory DiscoveryStats({
    @Default(0) int total,
    @JsonKey(name: 'by_state') @Default({}) Map<String, int> byState,
    @JsonKey(name: 'by_source') @Default({}) Map<String, int> bySource,
  }) = _DiscoveryStats;

  factory DiscoveryStats.fromJson(Map<String, dynamic> json) =>
      _$DiscoveryStatsFromJson(json);
}
