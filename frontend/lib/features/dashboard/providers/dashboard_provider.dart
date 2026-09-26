import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/sse_service.dart';
import '../models/stats.dart';

part 'dashboard_provider.g.dart';

@riverpod
Future<DashboardStats> dashboardStats(Ref ref) async {
  final dio = ref.watch(apiClientProvider);
  final response = await dio.get('/dashboard/stats');
  return DashboardStats.fromJson(response.data);
}

@riverpod
Future<QueueOverviewStats> queueStats(Ref ref) async {
  final dio = ref.watch(apiClientProvider);
  final response = await dio.get('/dashboard/queue');
  return QueueOverviewStats.fromJson(response.data);
}

@riverpod
Future<SystemHealth> systemHealth(Ref ref) async {
  final dio = ref.watch(apiClientProvider);
  final response = await dio.get('/health');
  return SystemHealth.fromJson(response.data);
}

final backgroundTaskDiagnosticsProvider =
    FutureProvider<BackgroundTaskDiagnostics>((ref) async {
      refreshOnEvents(
        ref,
        (event) => _diagnosticsEventTypes.contains(event.type),
      );

      final dio = ref.watch(apiClientProvider);
      final response = await dio.get('/background-tasks/diagnostics');
      return BackgroundTaskDiagnostics.fromJson(response.data);
    });

const _diagnosticsEventTypes = {
  'background_task_updated',
  'content_updated',
  'queue_updated',
  'distribution_push_failed',
  'distribution_push_success',
};

final backgroundTaskRunProvider =
    FutureProvider.family<BackgroundTaskRun, String>((ref, runId) async {
      refreshOnEvents(
        ref,
        (event) =>
            event.type == 'background_task_updated' &&
            event.data['run_id'] == runId,
      );
      final dio = ref.watch(apiClientProvider);
      final response = await dio.get('/background-tasks/runs/$runId');
      return BackgroundTaskRun.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
    });
