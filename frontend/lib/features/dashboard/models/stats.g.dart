// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'stats.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_QueueStats _$QueueStatsFromJson(Map<String, dynamic> json) => _QueueStats(
  pending: (json['pending'] as num).toInt(),
  processing: (json['processing'] as num).toInt(),
  failed: (json['failed'] as num).toInt(),
  archived: (json['archived'] as num).toInt(),
  total: (json['total'] as num).toInt(),
);

Map<String, dynamic> _$QueueStatsToJson(_QueueStats instance) =>
    <String, dynamic>{
      'pending': instance.pending,
      'processing': instance.processing,
      'failed': instance.failed,
      'archived': instance.archived,
      'total': instance.total,
    };

_DashboardStats _$DashboardStatsFromJson(Map<String, dynamic> json) =>
    _DashboardStats(
      platformCounts: Map<String, int>.from(json['platform_counts'] as Map),
      dailyGrowth: (json['daily_growth'] as List<dynamic>)
          .map((e) => e as Map<String, dynamic>)
          .toList(),
      storageUsageBytes: (json['storage_usage_bytes'] as num).toInt(),
    );

Map<String, dynamic> _$DashboardStatsToJson(_DashboardStats instance) =>
    <String, dynamic>{
      'platform_counts': instance.platformCounts,
      'daily_growth': instance.dailyGrowth,
      'storage_usage_bytes': instance.storageUsageBytes,
    };
