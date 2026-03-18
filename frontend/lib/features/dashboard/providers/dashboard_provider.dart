import 'package:riverpod_annotation/riverpod_annotation.dart';
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
