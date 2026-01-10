import 'package:freezed_annotation/freezed_annotation.dart';

part 'stats.freezed.dart';
part 'stats.g.dart';

@freezed
abstract class QueueStats with _$QueueStats {
  const factory QueueStats({
    required int pending,
    required int processing,
    required int failed,
    required int archived,
    required int total,
  }) = _QueueStats;

  factory QueueStats.fromJson(Map<String, dynamic> json) =>
      _$QueueStatsFromJson(json);
}

@freezed
abstract class DashboardStats with _$DashboardStats {
  const factory DashboardStats({
    @JsonKey(name: 'platform_counts') required Map<String, int> platformCounts,
    @JsonKey(name: 'daily_growth') required List<Map<String, dynamic>> dailyGrowth,
    @JsonKey(name: 'storage_usage_bytes') required int storageUsageBytes,
  }) = _DashboardStats;

  factory DashboardStats.fromJson(Map<String, dynamic> json) =>
      _$DashboardStatsFromJson(json);
}