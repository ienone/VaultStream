import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../../core/network/api_client.dart';
import '../models/discovery_models.dart';

part 'discovery_stats_provider.g.dart';

@riverpod
Future<DiscoveryStats> discoveryStats(Ref ref) async {
  final dio = ref.watch(apiClientProvider);
  final response = await dio.get('/discovery/stats');
  return DiscoveryStats.fromJson(response.data as Map<String, dynamic>);
}
