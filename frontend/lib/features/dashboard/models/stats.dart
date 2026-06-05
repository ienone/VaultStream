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
  const factory TagStats({required String name, required int count}) =
      _TagStats;

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

class BackgroundTaskDiagnostics {
  const BackgroundTaskDiagnostics({
    required this.summary,
    required this.taskStates,
    required this.failedParseTasks,
    required this.failedDistributionItems,
    required this.failedDiscoverySources,
    this.recentTaskRuns = const [],
  });

  factory BackgroundTaskDiagnostics.fromJson(Map<String, dynamic> json) {
    return BackgroundTaskDiagnostics(
      summary: Map<String, dynamic>.from(json['summary'] as Map? ?? {}),
      taskStates: (json['task_states'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(BackgroundTaskState.fromJson)
          .toList(),
      failedParseTasks: (json['failed_parse_tasks'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(FailedParseTask.fromJson)
          .toList(),
      failedDistributionItems:
          (json['failed_distribution_items'] as List<dynamic>? ?? [])
              .whereType<Map<String, dynamic>>()
              .map(FailedDistributionItem.fromJson)
              .toList(),
      failedDiscoverySources:
          (json['failed_discovery_sources'] as List<dynamic>? ?? [])
              .whereType<Map<String, dynamic>>()
              .map(FailedDiscoverySource.fromJson)
              .toList(),
      recentTaskRuns: (json['recent_task_runs'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(BackgroundTaskRun.fromJson)
          .toList(),
    );
  }

  final Map<String, dynamic> summary;
  final List<BackgroundTaskState> taskStates;
  final List<FailedParseTask> failedParseTasks;
  final List<FailedDistributionItem> failedDistributionItems;
  final List<FailedDiscoverySource> failedDiscoverySources;
  final List<BackgroundTaskRun> recentTaskRuns;

  int get totalFailures =>
      failedParseTasks.length +
      failedDistributionItems.length +
      failedDiscoverySources.length +
      taskStates.where((state) => state.status == 'error').length;
}

class BackgroundTaskRun {
  const BackgroundTaskRun({
    required this.raw,
    required this.runId,
    required this.task,
    required this.status,
    this.startedAt,
    this.finishedAt,
    this.error,
    this.result,
  });

  factory BackgroundTaskRun.fromJson(Map<String, dynamic> json) {
    return BackgroundTaskRun(
      raw: Map<String, dynamic>.from(json),
      runId: json['run_id']?.toString() ?? '',
      task: json['task']?.toString() ?? '',
      status: json['status']?.toString() ?? 'unknown',
      startedAt: _parseDate(json['started_at']),
      finishedAt: _parseDate(json['finished_at']),
      error: json['error']?.toString(),
      result: json['result'] is Map
          ? Map<String, dynamic>.from(json['result'] as Map)
          : null,
    );
  }

  final Map<String, dynamic> raw;
  final String runId;
  final String task;
  final String status;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final String? error;
  final Map<String, dynamic>? result;

  String get shortRunId => runId.length > 8 ? runId.substring(0, 8) : runId;

  Map<String, dynamic> get metadata {
    final data = Map<String, dynamic>.from(raw);
    for (final key in [
      'run_id',
      'task',
      'status',
      'started_at',
      'finished_at',
      'error',
      'result',
    ]) {
      data.remove(key);
    }
    return data;
  }
}

DateTime? _parseDate(Object? value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString());
}

class BackgroundTaskState {
  const BackgroundTaskState({
    required this.task,
    required this.status,
    this.lastError,
    this.errorCount = 0,
  });

  factory BackgroundTaskState.fromJson(Map<String, dynamic> json) {
    return BackgroundTaskState(
      task: json['task']?.toString() ?? '',
      status: json['status']?.toString() ?? 'unknown',
      lastError: json['last_error']?.toString(),
      errorCount: (json['error_count'] as num?)?.toInt() ?? 0,
    );
  }

  final String task;
  final String status;
  final String? lastError;
  final int errorCount;
}

class FailedParseTask {
  const FailedParseTask({
    required this.id,
    required this.taskType,
    required this.retryCount,
    required this.maxRetries,
    required this.retryable,
    this.contentId,
    this.lastError,
  });

  factory FailedParseTask.fromJson(Map<String, dynamic> json) {
    return FailedParseTask(
      id: (json['id'] as num?)?.toInt() ?? 0,
      taskType: json['task_type']?.toString() ?? '',
      contentId: (json['content_id'] as num?)?.toInt(),
      retryCount: (json['retry_count'] as num?)?.toInt() ?? 0,
      maxRetries: (json['max_retries'] as num?)?.toInt() ?? 0,
      retryable: json['retryable'] == true,
      lastError: json['last_error']?.toString(),
    );
  }

  final int id;
  final String taskType;
  final int? contentId;
  final int retryCount;
  final int maxRetries;
  final bool retryable;
  final String? lastError;
}

class FailedDistributionItem {
  const FailedDistributionItem({
    required this.id,
    required this.contentId,
    required this.targetPlatform,
    required this.targetId,
    required this.attemptCount,
    required this.maxAttempts,
    required this.retryable,
    this.title,
    this.lastError,
  });

  factory FailedDistributionItem.fromJson(Map<String, dynamic> json) {
    return FailedDistributionItem(
      id: (json['id'] as num?)?.toInt() ?? 0,
      contentId: (json['content_id'] as num?)?.toInt() ?? 0,
      title: json['title']?.toString(),
      targetPlatform: json['target_platform']?.toString() ?? '',
      targetId: json['target_id']?.toString() ?? '',
      attemptCount: (json['attempt_count'] as num?)?.toInt() ?? 0,
      maxAttempts: (json['max_attempts'] as num?)?.toInt() ?? 0,
      retryable: json['retryable'] == true,
      lastError: json['last_error']?.toString(),
    );
  }

  final int id;
  final int contentId;
  final String? title;
  final String targetPlatform;
  final String targetId;
  final int attemptCount;
  final int maxAttempts;
  final bool retryable;
  final String? lastError;
}

class FailedDiscoverySource {
  const FailedDiscoverySource({
    required this.id,
    required this.name,
    required this.kind,
    required this.enabled,
    this.lastError,
  });

  factory FailedDiscoverySource.fromJson(Map<String, dynamic> json) {
    return FailedDiscoverySource(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: json['name']?.toString() ?? '',
      kind: json['kind']?.toString() ?? '',
      enabled: json['enabled'] == true,
      lastError: json['last_error']?.toString(),
    );
  }

  final int id;
  final String name;
  final String kind;
  final bool enabled;
  final String? lastError;
}
