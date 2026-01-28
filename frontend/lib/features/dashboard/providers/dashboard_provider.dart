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
Future<QueueStats> queueStats(Ref ref) async {
  final dio = ref.watch(apiClientProvider);
  final response = await dio.get('/dashboard/queue');
  return QueueStats.fromJson(response.data);
}

@riverpod
Future<SystemHealth> systemHealth(Ref ref) async {
  final dio = ref.watch(apiClientProvider);
  final response = await dio.get('/health'); // Relative to /api/v1 as defined in client?
  // Wait, Client base URL usually includes /api/v1?
  // If so, /health call will go to /api/v1/health, which is what I implemented.
  return SystemHealth.fromJson(response.data);
}
