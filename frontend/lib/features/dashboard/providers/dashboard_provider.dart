import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
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
      final dio = ref.watch(apiClientProvider);
      final response = await dio.get('/background-tasks/diagnostics');
      return BackgroundTaskDiagnostics.fromJson(response.data);
    });

final backgroundTaskRunProvider =
    FutureProvider.family<BackgroundTaskRun, String>((ref, runId) async {
      final dio = ref.watch(apiClientProvider);
      final response = await dio.get('/background-tasks/runs/$runId');
      return BackgroundTaskRun.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
    });
