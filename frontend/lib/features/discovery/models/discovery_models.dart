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
    @JsonKey(name: 'created_at') required DateTime createdAt,
    @JsonKey(name: 'media_urls') @Default([]) List<String> mediaUrls,
    @JsonKey(name: 'rich_payload') Map<String, dynamic>? richPayload,
    @JsonKey(name: 'extra_stats') @Default({}) Map<String, dynamic> extraStats,
  }) = _DiscoveryItem;

  factory DiscoveryItem.fromJson(Map<String, dynamic> json) =>
      _$DiscoveryItemFromJson(json);
}

extension DiscoveryItemX on DiscoveryItem {
  ContentDetail toContentDetail() {
    return ContentDetail(
      id: id,
      platform: sourceType ?? 'universal',
      url: url,
      status: 'parse_success',
      tags: [],
      isNsfw: false,
      title: title,
      body: body ?? summary,
      authorName: authorName,
      authorAvatarUrl: authorAvatarUrl,
      authorUrl: authorUrl,
      mediaUrls: mediaUrls,
      richPayload: richPayload,
      extraStats: extraStats,
      createdAt: createdAt,
      updatedAt: createdAt,
      layoutType: 'article',
    );
  }
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
