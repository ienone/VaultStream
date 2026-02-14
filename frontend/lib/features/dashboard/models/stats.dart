import 'package:freezed_annotation/freezed_annotation.dart';

part 'stats.freezed.dart';
part 'stats.g.dart';

@freezed
abstract class QueueStats with _$QueueStats {
  const factory QueueStats({
    required int unprocessed,
    required int processing,
    @JsonKey(name: 'parse_success') required int parseSuccess,
    @JsonKey(name: 'parse_failed') required int parseFailed,
    required int total,
  }) = _QueueStats;

  factory QueueStats.fromJson(Map<String, dynamic> json) =>
      _$QueueStatsFromJson(json);
}

@freezed
abstract class DistributionStats with _$DistributionStats {
  const factory DistributionStats({
    @JsonKey(name: 'will_push') required int willPush,
    required int filtered,
    @JsonKey(name: 'pending_review') required int pendingReview,
    required int pushed,
    required int total,
  }) = _DistributionStats;

  factory DistributionStats.fromJson(Map<String, dynamic> json) =>
      _$DistributionStatsFromJson(json);
}

@freezed
abstract class QueueOverviewStats with _$QueueOverviewStats {
  const factory QueueOverviewStats({
    required QueueStats parse,
    required DistributionStats distribution,
  }) = _QueueOverviewStats;

  factory QueueOverviewStats.fromJson(Map<String, dynamic> json) =>
      _$QueueOverviewStatsFromJson(json);
}

@freezed
abstract class DashboardStats with _$DashboardStats {
  const factory DashboardStats({
    @JsonKey(name: 'platform_counts') required Map<String, int> platformCounts,
    @JsonKey(name: 'daily_growth')
    required List<Map<String, dynamic>> dailyGrowth,
    @JsonKey(name: 'storage_usage_bytes') required int storageUsageBytes,
  }) = _DashboardStats;

  factory DashboardStats.fromJson(Map<String, dynamic> json) =>
      _$DashboardStatsFromJson(json);
}

@freezed
abstract class TagStats with _$TagStats {
  const factory TagStats({
    required String name,
    required int count,
  }) = _TagStats;

  factory TagStats.fromJson(Map<String, dynamic> json) =>
      _$TagStatsFromJson(json);
}

@freezed
abstract class SystemHealth with _$SystemHealth {
  const factory SystemHealth({
    required String status,
    @JsonKey(name: 'queue_size') int? queueSize,
    Map<String, String>? components,
  }) = _SystemHealth;

  factory SystemHealth.fromJson(Map<String, dynamic> json) =>
      _$SystemHealthFromJson(json);
}
